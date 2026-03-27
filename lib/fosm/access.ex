defmodule Fosm.Access do
  @moduledoc """
  Access control enforcement helpers and fire! integration.

  Provides controller helpers and lifecycle event access enforcement.

  ## Controller Helpers

      defmodule MyAppWeb.InvoiceController do
        use MyAppWeb, :controller
        import Fosm.Access

        def show(conn, %{"id" => id}) do
          invoice = Fosm.Invoice |> Repo.get!(id)

          # Enforce read access
          authorize!(conn, invoice, :read)

          render(conn, :show, invoice: invoice)
        end

        def pay(conn, %{"id" => id}) do
          invoice = Fosm.Invoice |> Repo.get!(id)

          # Enforce event access
          authorize_event!(conn, invoice, :pay)

          case Fosm.Invoice.fire!(invoice, :pay, actor: conn.assigns.current_user) do
            {:ok, updated} -> json(conn, %{id: updated.id, state: updated.state})
            {:error, reason} -> json(conn, %{error: reason})
          end
        end
      end

  ## Lifecycle Integration

  Automatically called by `fire!` to enforce event access:

      lifecycle do
        access do
          role :owner, default: true do
            can :crud
            can :send_invoice, :cancel
          end
        end
      end
  """

  alias Fosm.Errors.AccessDenied

  # ============================================================================
  # Controller Helpers
  # ============================================================================

  @doc """
  Authorizes a basic CRUD action on a record.

  Raises `Fosm.Errors.AccessDenied` if the actor lacks permission.

  ## Parameters

    * `conn` - The Plug.Conn with `current_user` assigned
    * `record` - The record to check access against
    * `action` - The action atom (:read, :create, :update, :delete)

  ## Examples

      # In a controller action
      authorize!(conn, invoice, :read)
      authorize!(conn, invoice, :update)
  """
  @spec authorize!(Plug.Conn.t(), struct(), atom()) :: :ok
  def authorize!(conn, record, action) do
    actor = conn.assigns[:current_user]
    module = record.__struct__

    if can?(actor, module, record, action) do
      :ok
    else
      raise AccessDenied,
        action: action,
        resource_type: module.__schema__(:source),
        resource_id: record.id,
        actor: actor,
        reason: "Actor lacks #{action} permission on this record"
    end
  end

  @doc """
  Authorizes a lifecycle event on a record.

  Raises `Fosm.Errors.AccessDenied` if the actor cannot fire the event.

  ## Parameters

    * `conn` - The Plug.Conn with `current_user` assigned
    * `record` - The record to check event access against
    * `event_name` - The lifecycle event to authorize

  ## Examples

      # Before firing a lifecycle event
      authorize_event!(conn, invoice, :pay)
      {:ok, updated} = Fosm.Invoice.fire!(invoice, :pay, actor: conn.assigns.current_user)
  """
  @spec authorize_event!(Plug.Conn.t(), struct(), atom()) :: :ok
  def authorize_event!(conn, record, event_name) do
    actor = conn.assigns[:current_user]
    module = record.__struct__

    if can_fire_event?(actor, module, record, event_name) do
      :ok
    else
      raise AccessDenied,
        action: event_name,
        resource_type: module.__schema__(:source),
        resource_id: record.id,
        actor: actor,
        reason: "Actor cannot fire '#{event_name}' event on this record"
    end
  end

  @doc """
  Checks if an actor can perform an action without raising.

  Returns `true` or `false`.

  ## Examples

      if can?(conn, invoice, :read) do
        render(conn, :show, invoice: invoice)
      else
        redirect(conn, to: "/")
      end
  """
  @spec can?(Plug.Conn.t(), struct(), atom()) :: boolean()
  def can?(conn, record, action) when is_struct(record) do
    actor = conn.assigns[:current_user]
    module = record.__struct__
    can?(actor, module, record, action)
  end

  @doc """
  Checks if an actor can perform an action on a module/record.

  ## Parameters

    * `actor` - The actor (user, :system, :agent, nil)
    * `module` - The FOSM module
    * `record` - Optional record for record-level checks (nil for type-level)
    * `action` - The action atom

  ## Examples

      can?(user, Fosm.Invoice, nil, :read)
      can?(user, Fosm.Invoice, invoice, :update)
  """
  @spec can?(any(), module(), struct() | nil, atom()) :: boolean()
  def can?(actor, module, record \\ nil, action) do
    lifecycle = module.fosm_lifecycle()

    # If no access control defined, allow all
    if is_nil(lifecycle.access) or lifecycle.access == [] do
      true
    else
      # Get actor's roles
      resource_type = module.__schema__(:source)
      record_id = if record, do: record.id, else: nil
      roles = Fosm.Current.roles_for(actor, resource_type, record_id)

      # Check if any role allows the action
      Enum.any?(lifecycle.access, fn role_def ->
        role_name = role_def.name

        # Check if actor has this role
        if role_name in roles or :_all in roles do
          # Check if role allows the action
          action in role_def.permissions or :crud in role_def.permissions
        else
          false
        end
      end)
    end
  end

  @doc """
  Checks if an actor can fire a specific lifecycle event.

  ## Parameters

    * `actor` - The actor
    * `module` - The FOSM module
    * `record` - The record
    * `event_name` - The event to check

  ## Examples

      if can_fire_event?(user, Fosm.Invoice, invoice, :pay) do
        # Show pay button
      end
  """
  @spec can_fire_event?(any(), module(), struct(), atom()) :: boolean()
  def can_fire_event?(actor, module, record, event_name) do
    lifecycle = module.fosm_lifecycle()
    event_name = String.to_atom(to_string(event_name))

    # If no access control defined, allow all
    if is_nil(lifecycle.access) or lifecycle.access == [] do
      true
    else
      # Get actor's roles
      resource_type = module.__schema__(:source)
      record_id = if record, do: record.id, else: nil
      roles = Fosm.Current.roles_for(actor, resource_type, record_id)

      # Check if any role allows this event
      Enum.any?(lifecycle.access, fn role_def ->
        role_name = role_def.name

        # Check if actor has this role
        if role_name in roles or :_all in roles do
          # Check if role allows this specific event
          event_name in role_def.event_permissions or
            :crud in role_def.permissions or
            :manage in role_def.permissions
        else
          false
        end
      end)
    end
  end

  # ============================================================================
  # Lifecycle fire! Integration
  # ============================================================================

  @doc """
  Enforces access control during lifecycle event execution.

  Called automatically by `Fosm.Lifecycle.Implementation.fire!`.

  ## Parameters

    * `lifecycle` - The lifecycle definition struct
    * `record` - The record being transitioned
    * `event_name` - The event being fired
    * `actor` - The actor performing the transition

  ## Raises

    * `Fosm.Errors.AccessDenied` - If actor lacks permission

  ## Examples

      # This is called internally by fire!, not directly
      enforce_event_access!(lifecycle, invoice, :pay, current_user)
  """
  @spec enforce_event_access!(any(), struct(), atom(), any()) :: :ok
  def enforce_event_access!(lifecycle, record, event_name, actor) do
    cond do
      # Skip if no access control defined
      is_nil(lifecycle.access) or lifecycle.access == [] ->
        :ok

      # Skip for bypassed actors
      bypassed_actor?(actor) ->
        :ok

      true ->
        module = record.__struct__
        resource_type = module.__schema__(:source)
        record_id = record.id

        # Get roles (uses cache internally)
        roles = Fosm.Current.roles_for(actor, resource_type, record_id)

        # Check permission
        event_name = String.to_atom(to_string(event_name))

        has_permission =
          Enum.any?(lifecycle.access, fn role_def ->
            role_name = role_def.name

            if role_name in roles or :_all in roles do
              event_name in role_def.event_permissions or
                :crud in role_def.permissions or
                :manage in role_def.permissions
            else
              false
            end
          end)

        if has_permission do
          :ok
        else
          raise AccessDenied,
            action: event_name,
            resource_type: resource_type,
            resource_id: record_id,
            actor: actor,
            roles: roles,
            reason: "Actor lacks permission to fire '#{event_name}'"
        end
    end
  end

  @doc """
  Returns a list of available events for an actor on a record.

  Filters the lifecycle events to only those the actor can fire.

  ## Examples

      available_events = Fosm.Access.available_events(user, invoice)
      # => [:view, :edit, :send]  (only permitted events)
  """
  @spec available_events(any(), struct()) :: [atom()]
  def available_events(actor, record) do
    module = record.__struct__
    lifecycle = module.fosm_lifecycle()

    # Get all available events from the lifecycle
    all_events = Fosm.Lifecycle.Implementation.available_events(module, record)

    # Filter by access control
    if is_nil(lifecycle.access) or lifecycle.access == [] do
      all_events
    else
      Enum.filter(all_events, fn event_name ->
        can_fire_event?(actor, module, record, event_name)
      end)
    end
  end

  # ============================================================================
  # Internal Functions
  # ============================================================================

  # Check if actor is in bypass list
  # nil, :system, :agent are always allowed
  defp bypassed_actor?(nil), do: true
  defp bypassed_actor?(actor) when is_atom(actor) and not is_struct(actor), do: true

  defp bypassed_actor?(actor) when is_struct(actor) do
    # Check superadmin
    cond do
      function_exported?(actor.__struct__, :superadmin?, 1) ->
        actor.__struct__.superadmin?(actor)

      Map.has_key?(actor, :superadmin) ->
        Map.get(actor, :superadmin) == true

      Map.has_key?(actor, :is_superadmin) ->
        Map.get(actor, :is_superadmin) == true

      true ->
        false
    end
  rescue
    _ -> false
  end

  defp bypassed_actor?(_), do: false
end
