defmodule Fosm.Lifecycle.DSL do
  @moduledoc """
  DSL macros for defining FOSM lifecycles.

  Used within the `lifecycle do ... end` block.
  """

  alias Fosm.Lifecycle.{StateDefinition, EventDefinition, GuardDefinition, SideEffectDefinition, AccessDefinition, RoleDefinition, SnapshotConfiguration}

  @doc """
  Defines a state in the lifecycle.

  ## Options
  - `:initial` - Set to `true` if this is the initial state
  - `:terminal` - Set to `true` if this is a terminal state (no transitions allowed)

  ## Examples

      state :draft, initial: true
      state :sent
      state :paid, terminal: true
  """
  defmacro state(name, opts \\ []) do
    quote do
      terminal = Keyword.get(unquote(opts), :terminal, false)
      initial = Keyword.get(unquote(opts), :initial, false)

      @fosm_states %StateDefinition{
        name: unquote(name),
        initial: initial,
        terminal: terminal
      }
    end
  end

  @doc """
  Defines an event (state transition).

  ## Options
  - `:from` - Source state(s), single atom or list of atoms
  - `:to` - Target state

  ## Examples

      event :send_invoice, from: :draft, to: :sent
      event :cancel, from: [:draft, :sent], to: :cancelled
  """
  defmacro event(name, opts) do
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)

    from_states = case from do
      list when is_list(list) -> list
      atom when is_atom(atom) -> [atom]
    end

    quote do
      @fosm_events %EventDefinition{
        name: unquote(name),
        from_states: unquote(from_states),
        to_state: unquote(to),
        guards: [],
        side_effects: []
      }
    end
  end

  @doc """
  Defines a guard condition for an event.

  The guard block should return:
  - `true` or `:ok` - passes
  - `false` or `:error` - fails with generic message
  - `"failure reason"` - fails with custom message
  - `[:fail, "reason"]` - fails with structured reason
  - `{:error, reason}` - fails with reason

  ## Options
  - `:on` - The event name this guard applies to

  ## Examples

      guard :has_line_items, on: :send_invoice do
        length(invoice.line_items) > 0
      end
  """
  defmacro guard(name, opts, do: block) do
    event = Keyword.get(opts, :on)

    quote do
      guard_fn = fn record ->
        try do
          case unquote(block) do
            true -> :ok
            :ok -> :ok
            false -> {:error, nil}
            :error -> {:error, nil}
            {:error, reason} -> {:error, reason}
            msg when is_binary(msg) -> {:error, msg}
            [:fail, reason] -> {:error, reason}
            _ -> :ok
          end
        rescue
          e -> {:error, Exception.message(e)}
        end
      end

      @fosm_guards %GuardDefinition{
        name: unquote(name),
        event: unquote(event),
        check: guard_fn,
        line: __ENV__.line,
        file: __ENV__.file
      }
    end
  end

  @doc """
  Defines a side effect for an event.

  ## Options
  - `:on` - The event name this effect applies to
  - `:defer` - Set to `true` to run after transaction commits (default: false)

  ## Examples

      side_effect :notify_client, on: :send_invoice do
        # Runs in transaction
        Emailer.send(invoice.client, "Invoice sent")
      end

      side_effect :trigger_contract, on: :pay, defer: true do
        # Runs after commit
        invoice.contract.activate!()
      end
  """
  defmacro side_effect(name, opts, do: block) do
    event = Keyword.get(opts, :on)
    defer = Keyword.get(opts, :defer, false)

    quote do
      effect_fn = fn record, transition ->
        unquote(block)
      end

      @fosm_side_effects %SideEffectDefinition{
        name: unquote(name),
        event: unquote(event),
        effect: effect_fn,
        defer: unquote(defer),
        line: __ENV__.line,
        file: __ENV__.file
      }
    end
  end

  @doc """
  Defines access control with roles.

  ## Examples

      access do
        role :owner, default: true do
          can :crud
          can :send_invoice, :pay
        end

        role :approver do
          can :read
          can :pay
        end
      end
  """
  defmacro access(do: block) do
    quote do
      import Fosm.Lifecycle.DSL, only: [role: 2, role: 3]
      @fosm_access_roles []
      unquote(block)
    end
  end

  @doc """
  Defines a role within the access block.

  ## Options
  - `:default` - Set to `true` if this is the default role for new records

  ## Examples

      role :owner, default: true do
        can :crud
        can :send_invoice
      end
  """
  defmacro role(name, opts \\ [], do: block) do
    default = Keyword.get(opts, :default, false)

    quote do
      @fosm_current_role_name unquote(name)
      @fosm_current_role_default unquote(default)
      @fosm_current_role_crud []
      @fosm_current_role_events []
      import Fosm.Lifecycle.DSL, only: [can: 1]
      unquote(block)

      @fosm_roles %RoleDefinition{
        name: @fosm_current_role_name,
        default: @fosm_current_role_default,
        crud_permissions: Enum.reverse(@fosm_current_role_crud),
        event_permissions: Enum.reverse(@fosm_current_role_events)
      }

      @fosm_current_role_name nil
      @fosm_current_role_default nil
      @fosm_current_role_crud nil
      @fosm_current_role_events nil
    end
  end

  @doc """
  Specifies permissions within a role block.

  Can handle:
  - `:crud` - Grants all CRUD permissions
  - Individual CRUD: `:create`, `:read`, `:update`, `:delete`
  - Event names as atoms

  ## Examples

      can :crud
      can :read, :update
      can :send_invoice, :pay
  """
  defmacro can(permissions) when is_atom(permissions) do
    quote do
      can([unquote(permissions)])
    end
  end

  defmacro can(permissions) when is_list(permissions) do
    crud_perms = [:create, :read, :update, :delete]

    quote do
      perms = unquote(permissions)

      Enum.each(perms, fn perm ->
        if perm == :crud do
          @fosm_current_role_crud [:create, :read, :update, :delete]
        else
          if perm in unquote(crud_perms) do
            @fosm_current_role_crud [perm | @fosm_current_role_crud]
          else
            @fosm_current_role_events [perm | @fosm_current_role_events]
          end
        end
      end)
    end
  end

  @doc """
  Defines snapshot strategy with various options.

  ## Strategies
  - `:every` - Snapshot every transition
  - `every: N` - Snapshot every N transitions
  - `time: seconds` - Snapshot every N seconds
  - `:terminal` - Snapshot only on terminal states
  - `:manual` - Only snapshot when explicitly requested

  ## Examples

      snapshot :every
      snapshot every: 10
      snapshot time: 3600
      snapshot :terminal
      snapshot :manual
  """
  defmacro snapshot(strategy) when is_atom(strategy) do
    config = case strategy do
      :every -> quote do: SnapshotConfiguration.every()
      :terminal -> quote do: SnapshotConfiguration.terminal()
      :manual -> quote do: SnapshotConfiguration.manual()
      _ -> quote do: SnapshotConfiguration.manual()
    end

    quote do
      @fosm_snapshot unquote(config)
    end
  end

  defmacro snapshot(opts) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :every) ->
        n = Keyword.get(opts, :every)
        quote do
          @fosm_snapshot SnapshotConfiguration.count(unquote(n))
        end

      Keyword.has_key?(opts, :time) ->
        seconds = Keyword.get(opts, :time)
        quote do
          @fosm_snapshot SnapshotConfiguration.time(unquote(seconds))
        end

      true ->
        quote do
          @fosm_snapshot SnapshotConfiguration.manual()
        end
    end
  end

  @doc """
  Specifies which attributes to include in snapshots.

  ## Examples

      snapshot_attributes [:amount, :line_items_count, :due_date]
  """
  defmacro snapshot_attributes(attrs) when is_list(attrs) do
    quote do
      @fosm_snapshot_attrs unquote(attrs)
    end
  end
end
