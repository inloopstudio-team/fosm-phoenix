defmodule Fosm.RoleAssignment.Auto do
  @moduledoc """
  Automatic role assignment for creators and owners.

  Handles auto-granting roles when records are created, based on associations
  like `created_by`, `user`, or `owner`.

  ## Configuration

  Configure in your lifecycle:

      lifecycle do
        access do
          role :owner, default: true, auto_assign: :created_by do
            can :crud
          end
        end
      end

  ## Supported Associations

    * `:created_by` - Most common, uses `created_by_id` field
    * `:user` - Uses `user_id` field
    * `:owner` - Uses `owner_id` field

  ## Usage

  Auto-assignment is triggered automatically when `fire!` creates a transition
  that results in the initial state of a new record.
  """

  require Logger

  alias Fosm.RoleAssignment
  alias Fosm.Current

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Assigns default roles to a record's creator after creation.

  This should be called after a record is created with lifecycle state.
  Finds the `created_by`, `user`, or `owner` association and assigns
  the default role.

  ## Parameters

    * `record` - The newly created FOSM record
    * `opts` - Options:
      * `:actor` - The actor who created the record (if known)

  ## Examples

      # In a changeset or after_insert callback
      Fosm.RoleAssignment.Auto.assign_creator_roles(new_invoice)

      # With explicit actor
      Fosm.RoleAssignment.Auto.assign_creator_roles(invoice, actor: current_user)
  """
  def assign_creator_roles(record, opts \\ []) do
    module = record.__struct__
    lifecycle = module.fosm_lifecycle()
    explicit_actor = opts[:actor]

    # Find default roles in lifecycle access config
    default_roles = get_default_roles(lifecycle)

    if default_roles == [] do
      return {:ok, :no_default_roles}
    end

    # Try to find the creator from various associations
    creator =
      explicit_actor ||
        find_creator_from_associations(record, [:created_by, :user, :owner])

    if is_nil(creator) do
      Logger.debug("[Fosm] No creator found for #{module}:#{record.id}, skipping auto role assignment")
      return {:ok, :no_creator}
    end

    # Assign each default role
    results =
      Enum.map(default_roles, fn role_def ->
        assign_role(record, creator, role_def)
      end)

    # Invalidate cache for the creator
    Current.invalidate_for(creator)

    # Log access events
    Enum.each(default_roles, fn role_def ->
      log_auto_grant(record, creator, role_def)
    end)

    {:ok, results}
  end

  @doc """
  Assigns a specific role to a user on a record.

  ## Parameters

    * `record` - The FOSM record
    * `user` - The user to assign the role to
    * `role_name` - The role atom (e.g., :owner)
    * `opts` - Options:
      * `:granted_by` - The actor who granted this role (default: :system)

  ## Examples

      Fosm.RoleAssignment.Auto.assign_role(invoice, user, :owner)
      Fosm.RoleAssignment.Auto.assign_role(invoice, user, :approver, granted_by: admin_user)
  """
  def assign_role(record, user, role_name, opts \\ []) do
    module = record.__struct__
    granted_by = opts[:granted_by] || :system

    # Extract user identity
    {user_type, user_id} = extract_actor_identity(user)

    # Extract granter identity
    {granted_by_type, granted_by_id} = extract_actor_identity(granted_by)

    # Build assignment attributes
    attrs = %{
      user_type: user_type,
      user_id: user_id,
      resource_type: module.__schema__(:source),
      resource_id: to_string(record.id),
      role_name: to_string(role_name),
      granted_by_type: granted_by_type,
      granted_by_id: granted_by_id
    }

    # Create the assignment
    case %RoleAssignment{}
         |> RoleAssignment.changeset(attrs)
         |> Fosm.Repo.insert() do
      {:ok, assignment} ->
        Logger.debug("[Fosm] Auto-assigned #{role_name} role to #{user_type}:#{user_id} for #{module}:#{record.id}")
        {:ok, assignment}

      {:error, %{errors: [user_type_user_id_resource_type_resource_id_role_name: {"has already been taken", _}]}} ->
        # Role already exists, that's fine
        {:ok, :already_assigned}

      {:error, changeset} ->
        Logger.warning("[Fosm] Failed to auto-assign role: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Revokes a role from a user on a record.

  ## Examples

      Fosm.RoleAssignment.Auto.revoke_role(invoice, user, :owner)
  """
  def revoke_role(record, user, role_name) do
    module = record.__struct__
    {user_type, user_id} = extract_actor_identity(user)

    # Find the assignment
    assignment =
      from(ra in RoleAssignment,
        where: ra.user_type == ^user_type,
        where: ra.user_id == ^user_id,
        where: ra.resource_type == ^module.__schema__(:source),
        where: ra.resource_id == ^to_string(record.id),
        where: ra.role_name == ^to_string(role_name)
      )
      |> Fosm.Repo.one()

    if assignment do
      # Delete and invalidate cache
      Fosm.Repo.delete!(assignment)
      Current.invalidate_for(user)

      log_auto_revoke(record, user, role_name)

      {:ok, :revoked}
    else
      {:ok, :not_found}
    end
  end

  @doc """
  Transfers a role from one user to another.

  Useful for reassigning ownership.

  ## Examples

      Fosm.RoleAssignment.Auto.transfer_role(invoice, old_owner, new_owner, :owner)
  """
  def transfer_role(record, from_user, to_user, role_name) do
    # Revoke from old user
    case revoke_role(record, from_user, role_name) do
      {:ok, _} ->
        # Grant to new user
        assign_role(record, to_user, role_name, granted_by: from_user)

        # Invalidate both caches
        Current.invalidate_for(from_user)
        Current.invalidate_for(to_user)

        {:ok, :transferred}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Batch assigns creator roles for multiple records.

  Useful for backfilling roles on existing records.

  ## Examples

      # Find all invoices without owner roles
      invoices = Fosm.Invoice |> where([i], is_nil(i.deleted_at)) |> Repo.all()

      # Batch assign
      Fosm.RoleAssignment.Auto.batch_assign(invoices, :created_by)
  """
  def batch_assign(records, association_key) when is_list(records) do
    Enum.reduce(records, %{success: 0, failed: 0, skipped: 0}, fn record, acc ->
      # Load the association if not already loaded
      record = maybe_preload(record, association_key)

      creator = Map.get(record, association_key)

      if creator do
        case assign_creator_roles(record, actor: creator) do
          {:ok, _} -> %{acc | success: acc.success + 1}
          {:error, _} -> %{acc | failed: acc.failed + 1}
        end
      else
        %{acc | skipped: acc.skipped + 1}
      end
    end)
  end

  # ============================================================================
  # Internal Functions
  # ============================================================================

  # Finds the creator from various associations
  defp find_creator_from_associations(record, associations) do
    Enum.find_value(associations, fn assoc ->
      case Map.get(record, assoc) do
        nil -> nil
        %Ecto.Association.NotLoaded{} -> nil
        value when is_struct(value) -> value
        _ -> nil
      end
    end)
  end

  # Gets default roles from lifecycle access config
  defp get_default_roles(lifecycle) do
    access = lifecycle[:access] || lifecycle.access || []

    Enum.filter(access, fn role_def ->
      role_def[:default] == true || role_def.default == true
    end)
  end

  # Preloads an association if needed
  defp maybe_preload(record, assoc) do
    case Map.get(record, assoc) do
      %Ecto.Association.NotLoaded{} ->
        Fosm.Repo.preload(record, assoc)

      _ ->
        record
    end
  end

  # Extracts user type and id from actor
  defp extract_actor_identity(actor) when is_struct(actor) do
    user_type = to_string(actor.__struct__)
    user_id = to_string(actor.id)
    {user_type, user_id}
  end

  defp extract_actor_identity(actor) when is_atom(actor) do
    {to_string(actor), "system"}
  end

  defp extract_actor_identity(_actor) do
    {"Unknown", "0"}
  end

  # Logs auto-grant access event
  defp log_auto_grant(record, user, role_def) do
    {user_type, user_id} = extract_actor_identity(user)
    module = record.__struct__

    event_data = %{
      action: "auto_grant",
      user_type: user_type,
      user_id: user_id,
      user_label: user_label(user),
      resource_type: module.__schema__(:source),
      resource_id: to_string(record.id),
      role_name: to_string(role_def.name),
      performed_by_type: "system",
      performed_by_id: "system",
      metadata: %{
        reason: "auto-assigned as creator",
        auto_assign_trigger: role_def[:auto_assign] || "creation"
      }
    }

    # Queue async audit log
    Fosm.Jobs.AccessEventJob.new(event_data)
    |> Oban.insert()
  end

  # Logs auto-revoke access event
  defp log_auto_revoke(record, user, role_name) do
    {user_type, user_id} = extract_actor_identity(user)
    module = record.__struct__

    event_data = %{
      action: "auto_revoke",
      user_type: user_type,
      user_id: user_id,
      user_label: user_label(user),
      resource_type: module.__schema__(:source),
      resource_id: to_string(record.id),
      role_name: to_string(role_name),
      performed_by_type: "system",
      performed_by_id: "system",
      metadata: %{
        reason: "role transfer or removal"
      }
    }

    # Queue async audit log
    Fosm.Jobs.AccessEventJob.new(event_data)
    |> Oban.insert()
  end

  # Generates a user label for audit logs
  defp user_label(user) when is_struct(user) do
    parts = []
    parts = if user[:email], do: [user.email | parts], else: parts
    parts = if user[:name], do: [user.name | parts], else: parts
    parts = if user[:username], do: [user.username | parts], else: parts

    case parts do
      [] -> "#{user.__struct__}:#{user.id}"
      _ -> Enum.join(parts, " — ")
    end
  end

  defp user_label(user), do: to_string(user)
end
