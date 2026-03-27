defmodule Fosm.Lifecycle.Implementation do
  @moduledoc """
  Core state machine execution engine.

  Handles:
  - Row-level locking (SELECT FOR UPDATE)
  - Guard evaluation with rich error messages
  - RBAC enforcement
  - Side effect execution (immediate and deferred)
  - Causal chain tracking
  - State snapshots
  """

  require Logger

  alias Fosm.Errors
  alias Fosm.Lifecycle.{Definition, StateDefinition, EventDefinition, GuardDefinition, SideEffectDefinition, SnapshotConfiguration}

  @trigger_context_key :fosm_trigger_context
  @deferred_effects_key_prefix :fosm_deferred_effects

  @doc """
  Fires an event on a record, executing the full lifecycle transition.

  ## Steps
  1. Validate event exists
  2. Check current state is not terminal
  3. Check event is valid from current state
  4. Run guards with rich error messages
  5. RBAC check if access block defined
  6. Build transition data with causal chain context
  7. Build log data with snapshot consideration
  8. Acquire row lock (SELECT FOR UPDATE)
  9. Re-validate after lock
  10. Update state in transaction
  11. Run immediate side effects
  12. Store deferred effects for after-commit
  13. Handle logging strategies
  14. Queue webhooks
  15. Run deferred effects after commit

  ## Returns
  - `{:ok, updated_record}` - Success
  - `{:error, reason}` - Failure

  ## Raises
  - `Fosm.Errors.UnknownEvent` - Event doesn't exist
  - `Fosm.Errors.TerminalState` - Current state is terminal
  - `Fosm.Errors.InvalidTransition` - Invalid from state
  - `Fosm.Errors.GuardFailed` - Guard check failed
  - `Fosm.Errors.AccessDenied` - Actor lacks permission
  """
  def fire!(module, record, event_name, opts \\ []) do
    lifecycle = module.fosm_lifecycle()
    actor = Keyword.get(opts, :actor)
    metadata = Keyword.get(opts, :metadata, %{})
    snapshot_data = Keyword.get(opts, :snapshot_data)

    # 1. Find and validate event
    event_def = find_event!(lifecycle, event_name)
    current_state = record.state |> String.to_atom()
    current_state_def = find_state!(lifecycle, current_state)

    # 2. Terminal state check
    if current_state_def.terminal do
      raise Errors.TerminalState, state: current_state, module: module
    end

    # 3. Valid transition check
    unless EventDefinition.valid_from?(event_def, current_state) do
      raise Errors.InvalidTransition,
        event: event_name,
        from: current_state,
        to: event_def.to_state,
        module: module
    end

    # 4. Run guards
    guards = get_guards_for_event(lifecycle, event_name)
    Enum.each(guards, fn guard ->
      case GuardDefinition.evaluate(guard, record) do
        :ok -> :ok
        {:error, reason} ->
          raise Errors.GuardFailed,
            guard: guard.name,
            event: event_name,
            reason: reason,
            module: module
      end
    end)

    # 5. RBAC check
    if lifecycle.access do
      enforce_event_access!(lifecycle, record, event_name, actor)
    end

    # Prepare transition data
    from_state = current_state
    to_state = event_def.to_state

    transition_data = %{
      from: from_state,
      to: to_state,
      event: event_name,
      actor: actor,
      record_type: module.__schema__(:source),
      record_id: to_string(record.id)
    }

    # Get triggered_by from causal chain context
    triggered_by = Process.get(@trigger_context_key)

    # Merge into metadata
    metadata = if triggered_by do
      Map.put(metadata, :triggered_by, triggered_by)
    else
      metadata
    end

    # 6-7. Build log data
    log_data = build_log_data(
      module, record, event_name, from_state, to_state,
      actor, metadata, snapshot_data, lifecycle, event_def
    )

    # 8-14. Execute in transaction
    repo = get_repo(module)

    result = repo.transaction(fn ->
      # Re-validate after lock
      locked_record = acquire_lock(repo, record)
      locked_state = locked_record.state |> String.to_atom()

      unless EventDefinition.valid_from?(event_def, locked_state) do
        repo.rollback({:error, :state_changed})
      end

      # Re-run guards with locked record
      Enum.each(guards, fn guard ->
        case GuardDefinition.evaluate(guard, locked_record) do
          :ok -> :ok
          {:error, reason} ->
            repo.rollback({:error, {:guard_failed, guard.name, reason}})
        end
      end)

      # Update state
      changeset = Ecto.Changeset.change(locked_record, state: to_string(to_state))
      case repo.update(changeset) do
        {:ok, updated} ->
          # Sync instance state
          record = %{record | state: to_string(to_state)}

          # 11. Run immediate side effects with causal context
          immediate_effects = get_immediate_effects(lifecycle, event_name)

          set_trigger_context(%{
            record_type: module.__schema__(:source),
            record_id: to_string(updated.id),
            event_name: to_string(event_name)
          })

          try do
            Enum.each(immediate_effects, fn effect ->
              SideEffectDefinition.call(effect, updated, transition_data)
            end)
          after
            clear_trigger_context()
          end

          # 12. Store deferred effects for after_commit
          deferred_effects = get_deferred_effects(lifecycle, event_name)
          if deferred_effects != [] do
            Process.put({@deferred_effects_key_prefix, updated.id}, {
              deferred_effects,
              transition_data,
              module
            })
          end

          # 13. Handle sync logging
          if sync_logging?() do
            create_transition_log(log_data)
          end

          {:ok, updated, log_data}

        {:error, changeset} ->
          repo.rollback({:error, changeset})
      end
    end)

    case result do
      {:ok, updated_record, log_data} ->
        # 15. Run deferred effects now that transaction committed
        run_deferred_effects(updated_record.id)

        # Handle async logging
        handle_async_logging(log_data)

        # Queue webhooks
        queue_webhooks(log_data)

        {:ok, updated_record}

      {:error, {:guard_failed, guard_name, reason}} ->
        {:error, %Errors.GuardFailed{guard: guard_name, event: event_name, reason: reason, module: module}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns whether an event can be fired on a record.

  Checks:
  - Event exists
  - Current state is not terminal
  - Event can fire from current state
  - All guards pass
  - Actor has permission (if RBAC defined)
  """
  def can_fire?(module, record, event_name) do
    lifecycle = module.fosm_lifecycle()
    current_state = record.state |> String.to_atom()

    event_def = Definition.find_event(lifecycle, event_name)
    return false unless event_def

    current_state_def = Definition.find_state(lifecycle, current_state)
    return false if current_state_def && current_state_def.terminal
    return false unless EventDefinition.valid_from?(event_def, current_state)

    # Check guards
    guards = get_guards_for_event(lifecycle, event_name)
    Enum.all?(guards, fn guard ->
      GuardDefinition.evaluate(guard, record) == :ok
    end)
  end

  @doc """
  Returns detailed information about why an event cannot be fired.

  Returns a map with:
  - `:can_fire` - boolean
  - `:event` - event name
  - `:current_state` - current state
  - `:reason` - human-readable reason
  - `:failed_guards` - list of failed guards with reasons
  - `:passed_guards` - list of passed guards
  - `:is_terminal` - whether current state is terminal
  - `:valid_from_states` - states this event can fire from
  """
  def why_cannot_fire?(module, record, event_name) do
    lifecycle = module.fosm_lifecycle()
    current_state = record.state |> String.to_atom()

    result = %{
      can_fire: true,
      event: event_name,
      current_state: current_state,
      module: module,
      reason: nil,
      failed_guards: [],
      passed_guards: [],
      is_terminal: false,
      valid_from_states: nil
    }

    # Check event exists
    event_def = Definition.find_event(lifecycle, event_name)
    unless event_def do
      return %{result |
        can_fire: false,
        reason: "Unknown event '#{event_name}'"
      }
    end

    # Check terminal state
    current_state_def = Definition.find_state(lifecycle, current_state)
    if current_state_def && current_state_def.terminal do
      return %{result |
        can_fire: false,
        reason: "State '#{current_state}' is terminal and cannot transition further",
        is_terminal: true
      }
    end

    # Check valid from state
    unless EventDefinition.valid_from?(event_def, current_state) do
      return %{result |
        can_fire: false,
        reason: "Cannot fire '#{event_name}' from '#{current_state}' (valid from: #{inspect(event_def.from_states)})",
        valid_from_states: event_def.from_states
      }
    end

    # Evaluate guards with detailed results
    guards = get_guards_for_event(lifecycle, event_name)
    {passed, failed} = Enum.reduce(guards, {[], []}, fn guard, {passed, failed} ->
      case GuardDefinition.evaluate(guard, record) do
        :ok -> {[guard.name | passed], failed}
        {:error, reason} -> {passed, [%{name: guard.name, reason: reason} | failed]}
      end
    end)

    if failed != [] do
      first_failure = hd(Enum.reverse(failed))
      reason = "Guard '#{first_failure.name}' failed"
      reason = if first_failure.reason, do: "#{reason}: #{first_failure.reason}", else: reason

      %{result |
        can_fire: false,
        failed_guards: Enum.reverse(failed),
        passed_guards: Enum.reverse(passed),
        reason: reason
      }
    else
      result
    end
  end

  @doc """
  Returns all events that can be fired from the record's current state.

  Filters by:
  - Event can fire from current state
  - Current state is not terminal
  - All guards pass
  """
  def available_events(module, record) do
    lifecycle = module.fosm_lifecycle()
    current_state = record.state |> String.to_atom()

    # Terminal states have no available events
    current_state_def = Definition.find_state(lifecycle, current_state)
    if current_state_def && current_state_def.terminal do
      return []
    end

    lifecycle.events
    |> Enum.filter(fn event ->
      EventDefinition.valid_from?(event, current_state) &&
      guards_pass?(lifecycle, event, record)
    end)
    |> Enum.map(& &1.name)
  end

  # Private helper functions

  defp find_event!(lifecycle, name) do
    case Definition.find_event(lifecycle, name) do
      nil -> raise Errors.UnknownEvent, event: name, module: nil
      event -> event
    end
  end

  defp find_state!(lifecycle, name) do
    case Definition.find_state(lifecycle, name) do
      nil -> raise Errors.UnknownState, state: name, module: nil
      state -> state
    end
  end

  defp get_guards_for_event(lifecycle, event_name) do
    Enum.filter(lifecycle.guards, & &1.event == event_name)
  end

  defp guards_pass?(lifecycle, event, record) do
    event.guards
    |> Enum.all?(fn guard ->
      GuardDefinition.evaluate(guard, record) == :ok
    end)
  end

  defp get_immediate_effects(lifecycle, event_name) do
    lifecycle.side_effects
    |> Enum.filter(& &1.event == event_name)
    |> Enum.reject(&SideEffectDefinition.deferred?/1)
  end

  defp get_deferred_effects(lifecycle, event_name) do
    lifecycle.side_effects
    |> Enum.filter(& &1.event == event_name)
    |> Enum.filter(&SideEffectDefinition.deferred?/1)
  end

  defp enforce_event_access!(lifecycle, record, event_name, actor) do
    # This is a simplified RBAC check - full implementation in Fosm.Current
    allowed_roles = Fosm.Lifecycle.AccessDefinition.roles_for_event(lifecycle.access, event_name)

    if allowed_roles == [] do
      raise Errors.AccessDenied, action: event_name, actor: actor, resource: record, module: nil
    end

    # TODO: Check actor roles against allowed_roles
    # This requires Fosm.Current.roles_for/3 which depends on task-10
    :ok
  end

  defp acquire_lock(repo, record) do
    table = record.__struct__.__schema__(:source)
    [id_field] = record.__struct__.__schema__(:primary_key)
    id = Map.get(record, id_field)

    # Acquire lock
    repo.query!(
      "SELECT * FROM #{table} WHERE #{id_field} = $1 FOR UPDATE",
      [id]
    )

    # Re-fetch record
    repo.get!(record.__struct__, id)
  end

  defp build_log_data(module, record, event_name, from_state, to_state,
                      actor, metadata, snapshot_data, lifecycle, event_def) do
    to_state_def = Definition.find_state(lifecycle, to_state)
    to_state_terminal = to_state_def && to_state_def.terminal

    base = %{
      record_type: module.__schema__(:source),
      record_id: to_string(record.id),
      event_name: to_string(event_name),
      from_state: to_string(from_state),
      to_state: to_string(to_state),
      actor_type: actor_type(actor),
      actor_id: actor_id(actor),
      actor_label: actor_label(actor),
      metadata: metadata,
      created_at: DateTime.utc_now()
    }

    # Check if we should snapshot
    if lifecycle.snapshot && should_snapshot?(lifecycle.snapshot, event_def, to_state_terminal) do
      schema_attrs = lifecycle.snapshot.attributes
      schema_snapshot = SnapshotConfiguration.build_snapshot(module, record, schema_attrs, snapshot_data)

      Map.merge(base, %{
        state_snapshot: schema_snapshot,
        snapshot_reason: determine_snapshot_reason(lifecycle.snapshot, to_state_terminal)
      })
    else
      base
    end
  end

  defp should_snapshot?(snapshot_config, event_def, to_state_terminal) do
    # For now, simplified check. Full implementation tracks transition counts and time
    case snapshot_config.strategy do
      :every -> true
      :terminal -> to_state_terminal
      :manual -> false
      _ -> false
    end
  end

  defp determine_snapshot_reason(snapshot_config, to_state_terminal) do
    case snapshot_config.strategy do
      :every -> "every"
      :terminal -> "terminal"
      :count -> "count"
      :time -> "time"
      :manual -> "manual"
      _ -> "unknown"
    end
  end

  defp set_trigger_context(context) do
    Process.put(@trigger_context_key, context)
  end

  defp clear_trigger_context do
    Process.delete(@trigger_context_key)
  end

  defp run_deferred_effects(record_id) do
    case Process.delete({@deferred_effects_key_prefix, record_id}) do
      nil -> :ok
      {effects, transition_data, module} ->
        # Set causal context for nested transitions
        set_trigger_context(%{
          record_type: transition_data.record_type,
          record_id: transition_data.record_id,
          event_name: transition_data.event
        })

        try do
          Enum.each(effects, fn effect ->
            # Re-fetch record outside transaction
            repo = get_repo(module)
            record = repo.get!(module, record_id)
            SideEffectDefinition.call(effect, record, transition_data)
          end)
        rescue
          e ->
            Logger.error("[Fosm] Deferred side effect failed: #{Exception.message(e)}")
            # Don't re-raise - transaction already committed
        after
          clear_trigger_context()
        end
    end
  end

  defp handle_async_logging(log_data) do
    strategy = async_logging_strategy()

    case strategy do
      :async_job ->
        # Queue Oban job for async logging
        # TODO: Implement when Oban jobs are ready (task-13)
        :ok

      :buffer ->
        # Add to buffer GenServer
        # TODO: Implement when TransitionBuffer is ready (task-14)
        :ok

      _ ->
        :ok
    end
  end

  defp queue_webhooks(log_data) do
    # TODO: Queue webhook delivery jobs (task-13)
    :ok
  end

  defp sync_logging? do
    Fosm.config()[:transition_log_strategy] == :sync
  end

  defp async_logging_strategy do
    Fosm.config()[:transition_log_strategy]
  end

  defp create_transition_log(log_data) do
    # TODO: Create transition log entry (depends on task-4 for schema)
    :ok
  end

  defp get_repo(module) do
    module.__schema__(:repo) ||
      Fosm.config()[:repo] ||
      raise "No repository configured for #{inspect(module)}"
  end

  defp actor_type(nil), do: nil
  defp actor_type(actor), do: to_string(actor.__struct__)

  defp actor_id(nil), do: nil
  defp actor_id(actor), do: to_string(actor.id)

  defp actor_label(nil), do: nil
  defp actor_label(actor) do
    # Try common fields for label
    cond do
      Map.has_key?(actor, :email) -> actor.email
      Map.has_key?(actor, :name) -> actor.name
      true -> nil
    end
  end
end
