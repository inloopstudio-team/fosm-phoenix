# FOSM Phoenix Implementation Details

This document covers all implementation details including the nuanced features from the core enhancements.

## Table of Contents

1. [Core Lifecycle DSL](#1-core-lifecycle-dsl)
2. [The fire! Implementation](#2-the-fire-implementation)
3. [Guard Error Messages & Introspection](#3-guard-error-messages--introspection)
4. [Terminal State Enforcement](#4-terminal-state-enforcement)
5. [Side Effects - Error Handling](#5-side-effects---error-handling)
6. [Deferred Side Effects](#6-deferred-side-effects)
7. [Auto-captured Causal Chain](#7-auto-captured-causal-chain)
8. [State Snapshots](#8-state-snapshots)
9. [Graph Generation](#9-graph-generation)
10. [RBAC Cache](#10-rbac-cache)
11. [Background Jobs](#11-background-jobs)
12. [LiveView Admin UI](#12-liveview-admin-ui)
13. [AI Agent Integration](#13-ai-agent-integration)

---

## 1. Core Lifecycle DSL

The main entry point that transforms an Ecto schema into a state machine.

### Usage

```elixir
defmodule MyApp.Fosm.Invoice do
  use Ecto.Schema
  use Fosm.Lifecycle

  schema "invoices" do
    field :name, :string
    field :amount, :decimal
    field :state, :string  # Required - managed by FOSM
    belongs_to :created_by, MyApp.User
    timestamps()
  end

  lifecycle do
    state :draft, initial: true
    state :sent
    state :paid, terminal: true
    state :cancelled, terminal: true

    event :send_invoice, from: :draft, to: :sent
    event :pay, from: :sent, to: :paid
    event :cancel, from: [:draft, :sent], to: :cancelled

    guard :has_line_items, on: :send_invoice do
      # Returns: true | false | "reason" | [:fail, "reason"] | :ok | {:error, reason}
    end

    side_effect :notify_client, on: :send_invoice do
      # Runs in transaction
    end

    access do
      role :owner, default: true do
        can :crud
        can :send_invoice, :cancel
      end

      role :approver do
        can :read
        can :pay
      end
    end

    snapshot every: 10
    snapshot_attributes [:amount, :due_date]
  end
end
```

### Macro Implementation

```elixir
defmodule Fosm.Lifecycle do
  defmacro __using__(_opts) do
    quote do
      import Fosm.Lifecycle, only: [lifecycle: 1]

      Module.register_attribute(__MODULE__, :fosm_states, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_events, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_guards, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_side_effects, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_access, accumulate: false)
      Module.register_attribute(__MODULE__, :fosm_snapshot, accumulate: false)

      @before_compile Fosm.Lifecycle
    end
  end

  defmacro lifecycle(do: block) do
    quote do
      import Fosm.Lifecycle.DSL
      unquote(block)
    end
  end

  defmacro __before_compile__(env) do
    states = Module.get_attribute(env.module, :fosm_states, [])
    events = Module.get_attribute(env.module, :fosm_events, [])
    guards = Module.get_attribute(env.module, :fosm_guards, [])
    side_effects = Module.get_attribute(env.module, :fosm_side_effects, [])
    access = Module.get_attribute(env.module, :fosm_access)
    snapshot = Module.get_attribute(env.module, :fosm_snapshot)

    lifecycle_def = build_lifecycle_definition(states, events, guards, side_effects, access, snapshot)

    quote do
      def fosm_lifecycle, do: unquote(Macro.escape(lifecycle_def))

      unquote(generate_state_predicates(states))
      unquote(generate_event_methods(events))
      unquote(generate_introspection_methods())
      unquote(generate_snapshot_methods())

      def fire!(record, event_name, opts \\ []) do
        Fosm.Lifecycle.Implementation.fire!(__MODULE__, record, event_name, opts)
      end

      def can_fire?(record, event_name) do
        Fosm.Lifecycle.Implementation.can_fire?(__MODULE__, record, event_name)
      end

      def available_events(record) do
        Fosm.Lifecycle.Implementation.available_events(__MODULE__, record)
      end
    end
  end
end
```

---

## 2. The fire! Implementation

Core execution logic with row locking and transaction handling.

```elixir
defmodule Fosm.Lifecycle.Implementation do
  @moduledoc """
  Core state machine execution with:
  - Row-level locking (SELECT FOR UPDATE)
  - Guard evaluation with rich error messages
  - RBAC enforcement
  - Side effect execution (immediate and deferred)
  - Causal chain tracking
  - State snapshots
  """

  alias Fosm.Errors

  def fire!(module, record, event_name, opts) do
    lifecycle = module.fosm_lifecycle()
    actor = Keyword.get(opts, :actor)
    metadata = Keyword.get(opts, :metadata, %{})
    snapshot_data = Keyword.get(opts, :snapshot_data)

    event_def = find_event!(lifecycle, event_name)
    current_state = record.state
    current_state_def = find_state!(lifecycle, current_state)

    # 1. Terminal state check
    if current_state_def.terminal do
      raise Errors.TerminalState, state: current_state, module: module
    end

    # 2. Valid transition check
    unless valid_from?(event_def, current_state) do
      raise Errors.InvalidTransition,
        event: event_name,
        from: current_state,
        module: module
    end

    # 3. Run guards with rich error messages
    guards = get_guards_for_event(lifecycle, event_name)
    Enum.each(guards, fn guard ->
      case evaluate_guard(guard, record) do
        :ok -> :ok
        {:error, reason} ->
          raise Errors.GuardFailed,
            guard: guard.name,
            event: event_name,
            reason: reason
      end
    end)

    # 4. RBAC check
    if lifecycle.access do
      enforce_event_access!(lifecycle, record, event_name, actor)
    end

    # Prepare transition data
    from_state = current_state
    to_state = to_string(event_def.to_state)

    transition_data = %{
      from: from_state,
      to: to_state,
      event: to_string(event_name),
      actor: actor
    }

    # Get triggered_by from causal chain context
    triggered_by = Process.get(:fosm_trigger_context)

    # Merge into metadata
    metadata = if triggered_by do
      Map.put(metadata, :triggered_by, triggered_by)
    else
      metadata
    end

    # 5. Build log data with snapshot consideration
    log_data = build_log_data(
      module, record, event_name, from_state, to_state,
      actor, metadata, snapshot_data, lifecycle, event_def
    )

    # 6. Acquire lock and execute transaction
    repo = get_repo(module)

    result = repo.transaction(fn ->
      # Re-validate after lock
      locked_record = acquire_lock(repo, record)
      locked_state = locked_record.state

      unless valid_from?(event_def, locked_state) do
        repo.rollback({:error, :state_changed})
      end

      # Re-run guards with locked record
      Enum.each(guards, fn guard ->
        case evaluate_guard(guard, locked_record) do
          :ok -> :ok
          {:error, reason} -> repo.rollback({:error, {:guard_failed, guard.name, reason}})
        end
      end)

      # Update state
      changeset = Ecto.Changeset.change(locked_record, state: to_state)
      {:ok, updated} = repo.update(changeset)

      # Sync instance state
      record = %{record | state: to_state}

      # Run immediate side effects with causal context
      immediate_effects = get_immediate_effects(lifecycle, event_name)

      set_trigger_context(%{
        record_type: module.__schema__(:source),
        record_id: to_string(updated.id),
        event_name: to_string(event_name)
      })

      try do
        Enum.each(immediate_effects, fn effect ->
          effect.effect.(updated, transition_data)
        end)
      after
        clear_trigger_context()
      end

      # Store deferred effects for after_commit
      deferred_effects = get_deferred_effects(lifecycle, event_name)
      if deferred_effects != [] do
        # Store in process dictionary for after_commit callback
        Process.put({:fosm_deferred_effects, updated.id}, {
          deferred_effects,
          transition_data,
          module
        })
      end

      # Sync log if strategy is :sync
      if Fosm.config().transition_log_strategy == :sync do
        Fosm.TransitionLog.create!(log_data)
      end

      {:ok, updated, log_data}
    end)

    case result do
      {:ok, updated_record, log_data} ->
        # Run deferred effects now that transaction committed
        run_deferred_effects(updated_record.id)

        # Async logging strategies
        handle_async_logging(log_data)

        # Queue webhooks
        queue_webhooks(log_data)

        {:ok, updated_record}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Guard evaluation with rich return types
  defp evaluate_guard(guard, record) do
    try do
      case guard.check.(record) do
        true -> :ok
        false -> {:error, nil}
        :ok -> :ok
        :error -> {:error, nil}
        {:error, reason} -> {:error, reason}
        "fail" <> _ = msg -> {:error, msg}
        msg when is_binary(msg) -> {:error, msg}
        [:fail, reason] -> {:error, reason}
        _ -> :ok
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # Row locking via raw SQL
  defp acquire_lock(repo, record) do
    table = record.__struct__.__schema__(:source)
    [id_field] = record.__struct__.__schema__(:primary_key)
    id = Map.get(record, id_field)

    repo.query!(
      "SELECT * FROM #{table} WHERE #{id_field} = $1 FOR UPDATE",
      [id]
    )

    repo.get!(record.__struct__, id)
  end

  # Causal chain context management
  defp set_trigger_context(context) do
    Process.put(:fosm_trigger_context, context)
  end

  defp clear_trigger_context do
    Process.delete(:fosm_trigger_context)
  end

  # Deferred effects execution
  defp run_deferred_effects(record_id) do
    case Process.delete({:fosm_deferred_effects, record_id}) do
      nil -> :ok
      {effects, transition_data, module} ->
        set_trigger_context(%{
          record_type: transition_data.record_type,
          record_id: transition_data.record_id,
          event_name: transition_data.event
        })

        try do
          Enum.each(effects, fn effect ->
            # Get the record again (outside transaction)
            record = module.__schema__(:repo).get!(module, record_id)
            effect.effect.(record, transition_data)
          end)
        rescue
          e ->
            require Logger
            Logger.error("[Fosm] Deferred side effect failed: #{Exception.message(e)}")
        after
          clear_trigger_context()
        end
    end
  end

  defp build_log_data(module, record, event_name, from_state, to_state,
                      actor, metadata, snapshot_data, lifecycle, event_def) do
    base = %{
      record_type: module.__schema__(:source),
      record_id: to_string(record.id),
      event_name: to_string(event_name),
      from_state: from_state,
      to_state: to_state,
      actor_type: actor_type(actor),
      actor_id: actor_id(actor),
      actor_label: actor_label(actor),
      metadata: metadata,
      created_at: DateTime.utc_now()
    }

    # Check if we should snapshot
    snapshot_config = lifecycle.snapshot
    if snapshot_config && should_snapshot?(snapshot_config, record, lifecycle, event_def) do
      schema_snapshot = build_schema_snapshot(module, record, snapshot_config)

      # Merge arbitrary observations
      schema_snapshot = if snapshot_data do
        Map.put(schema_snapshot, :_observations, snapshot_data)
      else
        schema_snapshot
      end

      Map.merge(base, %{
        state_snapshot: schema_snapshot,
        snapshot_reason: determine_snapshot_reason(snapshot_config, event_def)
      })
    else
      base
    end
  end

  defp should_snapshot?(config, record, lifecycle, event_def) do
    # Implementation based on strategy
    # - :every: always true
    # - every: N - check transition count since last snapshot
    # - time: seconds - check time since last snapshot
    # - :terminal - true if target state is terminal
    # - :manual - only when metadata[:snapshot] == true
    # Also respect metadata[:snapshot] == false to opt out
  end
end
```

---

## 3. Guard Error Messages & Introspection

### Rich Guard Return Values

Guards can return:
- `true` / `:ok` - passes
- `false` / `:error` - fails with generic message
- `"failure reason"` - fails with custom message
- `[:fail, "reason"]` - fails with structured reason
- `{:error, reason}` - fails with reason

```elixir
defmodule Fosm.Lifecycle.DSL do
  defmacro guard(name, on: event, do: block) do
    quote do
      guard_fn = fn record ->
        try do
          case unquote(block) do
            # Pass cases
            true -> :ok
            :ok -> :ok

            # Fail cases
            false -> {:error, nil}
            :error -> {:error, nil}
            {:error, reason} -> {:error, reason}

            # String message
            msg when is_binary(msg) -> {:error, msg}

            # Structured fail
            [:fail, reason] -> {:error, reason}

            # Default
            _ -> :ok
          end
        rescue
          e -> {:error, Exception.message(e)}
        end
      end

      @fosm_guards %{
        name: unquote(name),
        event: unquote(event),
        check: guard_fn,
        line: __ENV__.line,
        file: __ENV__.file
      }
    end
  end
end
```

### why_cannot_fire? Introspection

```elixir
defmodule Fosm.Lifecycle.Implementation do
  def why_cannot_fire?(module, record, event_name) do
    lifecycle = module.fosm_lifecycle()
    current_state = record.state

    result = %{
      can_fire: true,
      event: to_string(event_name),
      current_state: current_state,
      module: module
    }

    # Check event exists
    event_def = find_event(lifecycle, event_name)
    unless event_def do
      return %{result | can_fire: false, reason: "Unknown event '#{event_name}'"}
    end

    # Check terminal state
    current_state_def = find_state(lifecycle, current_state)
    if current_state_def && current_state_def.terminal do
      return %{
        result |
        can_fire: false,
        reason: "State '#{current_state}' is terminal and cannot transition further",
        is_terminal: true
      }
    end

    # Check valid from state
    unless valid_from?(event_def, current_state) do
      return %{
        result |
        can_fire: false,
        reason: "Cannot fire '#{event_name}' from '#{current_state}' (valid from: #{Enum.join(event_def.from_states, ", ")})",
        valid_from_states: event_def.from_states
      }
    end

    # Evaluate guards with detailed results
    guards = get_guards_for_event(lifecycle, event_name)
    {passed, failed} = Enum.reduce(guards, {[], []}, fn guard, {passed, failed} ->
      case evaluate_guard(guard, record) do
        :ok -> {[guard.name | passed], failed}
        {:error, reason} -> {passed, [%{name: guard.name, reason: reason} | failed]}
      end
    end)

    if failed != [] do
      first_failure = hd(Enum.reverse(failed))
      reason = "Guard '#{first_failure.name}' failed"
      reason = if first_failure.reason, do: "#{reason}: #{first_failure.reason}", else: reason

      %{
        result |
        can_fire: false,
        failed_guards: Enum.reverse(failed),
        passed_guards: Enum.reverse(passed),
        reason: reason
      }
    else
      result
    end
  end
end
```

### Generated Module Functions

```elixir
defmacro generate_introspection_methods do
  quote do
    def why_cannot_fire?(record, event_name) do
      Fosm.Lifecycle.Implementation.why_cannot_fire?(__MODULE__, record, event_name)
    end
  end
end
```

---

## 4. Terminal State Enforcement

Terminal states have `terminal: true` and block ALL transitions.

```elixir
defmodule Fosm.Lifecycle.DSL do
  defmacro state(name, opts \\ []) do
    terminal = Keyword.get(opts, :terminal, false)

    quote do
      @fosm_states %{
        name: unquote(name),
        initial: unquote(!!opts[:initial]),
        terminal: unquote(terminal)
      }
    end
  end
end
```

Terminal states are enforced in `fire!`:

```elixir
# Before any other checks
if current_state_def.terminal do
  raise Errors.TerminalState, state: current_state, module: module
end
```

Terminal state errors in `can_fire?`:

```elixir
def can_fire?(module, record, event_name) do
  lifecycle = module.fosm_lifecycle()
  current_state = record.state

  event_def = find_event(lifecycle, event_name)
  return false unless event_def

  current_state_def = find_state(lifecycle, current_state)
  return false if current_state_def && current_state_def.terminal  # Terminal blocks all
  return false unless valid_from?(event_def, current_state)

  # ... guard checks
end
```

---

## 5. Side Effects - Error Handling

Side effects run inside the transaction. Errors propagate naturally (raising rolls back the transaction).

```elixir
defmacro side_effect(name, on: event, opts \\ [], do: block) do
    defer = Keyword.get(opts, :defer, false)

    quote do
      effect_fn = fn record, transition ->
        unquote(block)  # Errors propagate naturally
      end

      @fosm_side_effects %{
        name: unquote(name),
        event: unquote(event),
        effect: effect_fn,
        defer: unquote(defer),
        line: __ENV__.line,
        file: __ENV__.file
      }
    end
  end
end
```

Usage patterns:

```elixir
# 1. Default - errors fail the transition
side_effect :critical_payment, on: :pay do |invoice, transition|
  PaymentGateway.charge!(invoice)
end

# 2. Host app rescues for non-critical operations
side_effect :notify_slack, on: :pay do |invoice, transition|
  Slack.notify("Invoice #{invoice.id} paid")
rescue
  e ->
    require Logger
    Logger.error("Slack notify failed: #{Exception.message(e)}")
    # Transition continues because we rescued
end

# 3. Deferred side effects (after commit)
side_effect :trigger_contract, on: :pay, defer: true do |invoice, transition|
  invoice.contract&.activate!(actor: :system)
end
```

---

## 6. Deferred Side Effects

Run after transaction commits to avoid cross-machine deadlocks.

```elixir
defmacro side_effect(name, on: event, opts \\ [], do: block) do
  defer = Keyword.get(opts, :defer, false)

  quote do
    effect_fn = fn record, transition ->
      unquote(block)
    end

    @fosm_side_effects %{
      name: unquote(name),
      event: unquote(event),
      effect: effect_fn,
      defer: unquote(defer)
    }
  end
end
```

Execution in `fire!`:

```elixir
# Inside transaction
immediate_effects = get_immediate_effects(lifecycle, event_name)
Enum.each(immediate_effects, fn effect ->
  effect.effect.(updated, transition_data)
end)

# Store deferred for after commit
deferred_effects = get_deferred_effects(lifecycle, event_name)
if deferred_effects != [] do
  Process.put({:fosm_deferred_effects, updated.id}, {
    deferred_effects,
    transition_data,
    module
  })
end

# After transaction commits
run_deferred_effects(updated_record.id)
```

Deferred effects execution:

```elixir
defp run_deferred_effects(record_id) do
  case Process.delete({:fosm_deferred_effects, record_id}) do
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
          record = module.__schema__(:repo).get!(module, record_id)
          effect.effect.(record, transition_data)
        end)
      rescue
        e ->
          require Logger
          Logger.error("[Fosm] Deferred side effect failed: #{Exception.message(e)}")
          # Don't re-raise - transaction already committed
      after
        clear_trigger_context()
      end
  end
end
```

---

## 7. Auto-captured Causal Chain

Automatically track when `fire!` is called from within a side effect.

```elixir
# Process dictionary keys
@trigger_context_key :fosm_trigger_context

# Set context before running side effects
defp set_trigger_context(context) do
  Process.put(@trigger_context_key, context)
end

defp clear_trigger_context do
  Process.delete(@trigger_context_key)
end

# Get current context
defp get_trigger_context do
  Process.get(@trigger_context_key)
end
```

Usage in `fire!`:

```elixir
# Before running side effects
set_trigger_context(%{
  record_type: module.__schema__(:source),
  record_id: to_string(updated.id),
  event_name: to_string(event_name)
})

try do
  Enum.each(immediate_effects, fn effect ->
    effect.effect.(updated, transition_data)
  end)
after
  clear_trigger_context()
end

# Build log data includes triggered_by
triggered_by = get_trigger_context()

metadata = if triggered_by do
  Map.put(metadata, :triggered_by, triggered_by)
else
  metadata
end
```

Querying the causal chain:

```elixir
# The triggering transition
contract_log = Fosm.TransitionLog.for_record("Fosm.Contract", contract.id) |> last()

contract_log.metadata["triggered_by"]
# => %{
#   "record_type" => "Fosm.Invoice",
#   "record_id" => "456",
#   "event_name" => "pay"
# }
```

---

## 8. State Snapshots

Capture both schema state and arbitrary observations for replay and audit.

### DSL

```elixir
defmodule Fosm.Lifecycle.DSL do
  defmacro snapshot(strategy) when is_atom(strategy) do
    quote do
      @fosm_snapshot %{strategy: unquote(strategy), options: []}
    end
  end

  defmacro snapshot(opts) when is_list(opts) do
    cond do
      Keyword.has_key?(opts, :every) ->
        quote do
          @fosm_snapshot %{strategy: :count, count: unquote(opts[:every])}
        end

      Keyword.has_key?(opts, :time) ->
        quote do
          @fosm_snapshot %{strategy: :time, seconds: unquote(opts[:time])}
        end

      true ->
        quote do
          @fosm_snapshot %{strategy: :custom, options: unquote(opts)}
        end
    end
  end

  defmacro snapshot_attributes(attrs) do
    quote do
      @fosm_snapshot_attrs unquote(attrs)
    end
  end
end
```

### Snapshot Configuration Module

```elixir
defmodule Fosm.Lifecycle.SnapshotConfiguration do
  defstruct [:strategy, :count, :seconds, :attributes]

  def should_snapshot?(config, transition_count, seconds_since_last, to_state, to_state_terminal, force: force) do
    # Manual override
    if force == true, do: return true
    if force == false, do: return false

    case config.strategy do
      :every -> true
      :count -> transition_count >= config.count
      :time -> seconds_since_last >= config.seconds
      :terminal -> to_state_terminal
      :manual -> false
      _ -> false
    end
  end

  def build_snapshot(module, record, attrs \\ nil) do
    attrs = attrs || default_attributes(module)

    base = %{
      _fosm_snapshot_meta: %{
        snapshot_at: DateTime.utc_now(),
        record_class: module.__schema__(:source),
        record_id: to_string(record.id)
      }
    }

    Enum.reduce(attrs, base, fn attr, acc ->
      value = Map.get(record, attr)
      Map.put(acc, attr, serialize_value(value))
    end)
  end

  defp default_attributes(module) do
    # Exclude internal fields
    module.__schema__(:fields)
    |> Enum.reject(& &1 in [:id, :state, :inserted_at, :updated_at, :created_by_id])
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(%Date{} = d), do: Date.to_iso8601(d)
  defp serialize_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp serialize_value(%_{} = struct), do: Map.from_struct(struct)
  defp serialize_value(value), do: value
end
```

### Usage

```elixir
lifecycle do
  snapshot every: 10
  snapshot :terminal
  snapshot_attributes [:amount, :line_items_count, :state]
end

# Capture with arbitrary observations
invoice.pay!(
  actor: user,
  snapshot_data: %{
    external_ref: "pi_123456",
    risk_score: 0.85,
    ip_address: "192.168.1.1",
    raw_webhook_payload: webhook_body
  }
)
```

Resulting snapshot:

```json
{
  "amount": 100.00,
  "line_items_count": 5,
  "state": "paid",
  "_fosm_snapshot_meta": {
    "snapshot_at": "2024-03-22T08:45:00Z",
    "record_class": "fosm_invoices",
    "record_id": "123"
  },
  "_observations": {
    "external_ref": "pi_123456",
    "risk_score": 0.85,
    "ip_address": "192.168.1.1"
  }
}
```

### Query Methods on Record

```elixir
defmacro generate_snapshot_methods do
  quote do
    def last_snapshot(record) do
      Fosm.TransitionLog
      |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
      |> Fosm.TransitionLog.with_snapshot()
      |> order_by(desc: :created_at)
      |> first()
      |> Fosm.Repo.one()
    end

    def last_snapshot_data(record) do
      case last_snapshot(record) do
        nil -> nil
        log -> log.state_snapshot
      end
    end

    def snapshots(record) do
      Fosm.TransitionLog
      |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
      |> Fosm.TransitionLog.with_snapshot()
      |> order_by(:created_at)
      |> Fosm.Repo.all()
    end

    def replay_from(record, transition_log_id) do
      # Returns all transitions after the given log ID
      Fosm.TransitionLog
      |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
      |> where([l], l.id > ^transition_log_id)
      |> order_by(:created_at)
      |> Fosm.Repo.all()
    end

    def transitions_since_snapshot(record) do
      case last_snapshot(record) do
        nil ->
          Fosm.TransitionLog
          |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
          |> Fosm.Repo.aggregate(:count)

        log ->
          Fosm.TransitionLog
          |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
          |> where([l], l.created_at > ^log.created_at)
          |> Fosm.Repo.aggregate(:count)
      end
    end
  end
end
```

### TransitionLog Scopes

```elixir
defmodule Fosm.TransitionLog do
  use Ecto.Schema

  schema "fosm_transition_logs" do
    # ... fields ...
    field :state_snapshot, :map
    field :snapshot_reason, :string
  end

  def with_snapshot(query) do
    where(query, [l], not is_nil(l.state_snapshot))
  end

  def without_snapshot(query) do
    where(query, [l], is_nil(l.state_snapshot))
  end

  def by_snapshot_reason(query, reason) do
    where(query, [l], l.snapshot_reason == ^reason)
  end
end
```

---

## 9. Graph Generation

Generate JSON representations for visual state machine exploration.

```elixir
# lib/fosm/graph.ex
defmodule Fosm.Graph do
  @moduledoc """
  Generate JSON graph representations of FOSM state machines.
  """

  def generate(module, opts \\ []) do
    lifecycle = module.fosm_lifecycle()
    system_wide = Keyword.get(opts, :system, false)

    base = %{
      machine: module.__schema__(:source),
      states: Enum.map(lifecycle.states, fn s ->
        %{
          name: s.name,
          initial: s.initial,
          terminal: s.terminal
        }
      end),
      events: Enum.map(lifecycle.events, fn e ->
        %{
          name: e.name,
          from: e.from_states,
          to: e.to_state,
          guards: Enum.map(get_guards(lifecycle, e.name), & &1.name),
          side_effects: Enum.map(get_effects(lifecycle, e.name), & &1.name)
        }
      end)
    }

    if system_wide do
      Map.put(base, :cross_machine_connections, find_cross_machine_connections(module))
    else
      base
    end
  end

  defp get_guards(lifecycle, event_name) do
    Enum.filter(lifecycle.guards, & &1.event == event_name)
  end

  defp get_effects(lifecycle, event_name) do
    Enum.filter(lifecycle.side_effects, & &1.event == event_name)
  end

  defp find_cross_machine_connections(module) do
    # Analyze deferred side effects that trigger other FOSM machines
    lifecycle = module.fosm_lifecycle()

    lifecycle.side_effects
    |> Enum.filter(& &1.defer)
    |> Enum.map(fn effect ->
      # This is heuristic - we'd need to analyze the effect's AST
      # or have explicit metadata
      %{
        via: effect.name,
        # target_machine would need to be determined by analyzing the effect
      }
    end)
  end

  def generate_system_graph(modules) when is_list(modules) do
    Enum.map(modules, &generate/1)
  end

  def save_to_file(module, path, opts \\ []) do
    graph = generate(module, opts)
    json = Jason.encode!(graph, pretty: true)
    File.write!(path, json)
    path
  end
end
```

### Mix Task

```elixir
# lib/mix/tasks/fosm.graph.generate.ex
defmodule Mix.Tasks.Fosm.Graph.Generate do
  use Mix.Task

  @shortdoc "Generate FOSM state machine graph JSON"

  @moduledoc """
  Generate JSON graph representation for FOSM state machines.

  ## Examples

      mix fosm.graph.generate MyApp.Fosm.Invoice
      mix fosm.graph.generate MyApp.Fosm.Invoice --system
      mix fosm.graph.generate --all
  """

  def run(args) do
    {opts, [module_name | _]} = OptionParser.parse!(args,
      switches: [system: :boolean, all: :boolean, output: :string],
      aliases: [s: :system, a: :all, o: :output]
    )

    Mix.Task.run("app.start")

    if opts[:all] do
      # Generate for all registered FOSM modules
      Fosm.Registry.all()
      |> Enum.each(fn {slug, module} ->
        path = opts[:output] || "priv/graphs/#{slug}_graph.json"
        File.mkdir_p!(Path.dirname(path))
        Fosm.Graph.save_to_file(module, path, opts)
        Mix.shell().info("Generated: #{path}")
      end)
    else
      module = Module.concat([module_name])
      path = opts[:output] || "priv/graphs/#{Macro.underscore(module)}_graph.json"
      File.mkdir_p!(Path.dirname(path))
      Fosm.Graph.save_to_file(module, path, opts)
      Mix.shell().info("Generated: #{path}")
    end
  end
end
```

---

## 10. RBAC Cache

Per-process caching of role assignments using Process dictionary.

```elixir
defmodule Fosm.Current do
  @moduledoc """
  Per-process RBAC cache.

  Loads ALL role assignments for an actor in ONE query,
  serves subsequent checks from in-memory map (O(1)).

  Cache structure:
  %{"User:42" => %{"Fosm.Invoice" => %{nil => [:owner], "5" => [:approver]}}}
  """

  @cache_key :fosm_access_cache

  def roles_for(actor, resource_type, record_id \\ nil) do
    actor_key = cache_key(actor)
    cache = get_cache()

    actor_data = case Map.get(cache, actor_key) do
      nil ->
        data = load_for_actor(actor)
        put_cache(Map.put(cache, actor_key, data))
        data
      data -> data
    end

    type_roles = get_in(actor_data, [resource_type, nil]) || []
    record_roles = if record_id do
      get_in(actor_data, [resource_type, to_string(record_id)]) || []
    else
      []
    end

    Enum.uniq(type_roles ++ record_roles)
  end

  def invalidate_for(actor) do
    cache = get_cache()
    put_cache(Map.delete(cache, cache_key(actor)))
  end

  def clear_cache do
    Process.delete(@cache_key)
  end

  defp get_cache, do: Process.get(@cache_key, %{})
  defp put_cache(cache), do: Process.put(@cache_key, cache)

  defp cache_key(actor) do
    "#{actor.__struct__}:#{actor.id}"
  end

  defp load_for_actor(actor) do
    import Ecto.Query

    Fosm.RoleAssignment
    |> where([r], r.user_type == ^to_string(actor.__struct__) and r.user_id == ^to_string(actor.id))
    |> Fosm.Repo.all()
    |> Enum.reduce(%{}, fn assignment, cache ->
      type = assignment.resource_type
      id = assignment.resource_id
      role = String.to_atom(assignment.role_name)

      cache
      |> Map.put_new(type, %{})
      |> put_in([type, id], [role | (get_in(cache, [type, id]) || [])])
    end)
  end

  defp get_in(map, keys) do
    Enum.reduce(keys, map, fn key, acc ->
      case acc do
        nil -> nil
        %{} -> Map.get(acc, key)
        _ -> nil
      end
    end)
  end
end
```

---

## 11. Background Jobs

### Oban Workers

```elixir
defmodule Fosm.Jobs.TransitionLogJob do
  use Oban.Worker, queue: :fosm_logs

  @impl Oban.Worker
  def perform(%Oban.Job{args: log_data}) do
    Fosm.TransitionLog.create!(log_data)
    :ok
  end
end

defmodule Fosm.Jobs.WebhookDeliveryJob do
  use Oban.Worker, queue: :fosm_webhooks, max_attempts: 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{} = args}) do
    url = args["url"]
    payload = args["payload"]
    secret = args["secret_token"]

    headers = [
      {"Content-Type", "application/json"},
      {"X-FOSM-Event", args["event_name"]},
      {"X-FOSM-Record-Type", args["record_type"]}
    ]

    headers = if secret do
      signature = compute_signature(payload, secret)
      [{"X-FOSM-Signature", "sha256=#{signature}"} | headers]
    else
      headers
    end

    case Req.post(url, json: payload, headers: headers) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp compute_signature(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, Jason.encode!(payload))
    |> Base.encode16(case: :lower)
  end
end

defmodule Fosm.Jobs.AccessEventJob do
  use Oban.Worker, queue: :fosm_logs

  @impl Oban.Worker
  def perform(%Oban.Job{args: event_data}) do
    Fosm.AccessEvent.create!(event_data)
    :ok
  end
end
```

### Transition Buffer GenServer

```elixir
defmodule Fosm.TransitionBuffer do
  use GenServer

  @flush_interval_ms 1000
  @max_buffer_size 100

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def push(log_data) do
    GenServer.cast(__MODULE__, {:push, log_data})
  end

  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @impl GenServer
  def init(_opts) do
    schedule_flush()
    {:ok, %{buffer: []}}
  end

  @impl GenServer
  def handle_cast({:push, log_data}, %{buffer: buffer} = state) do
    new_buffer = [log_data | buffer]

    if length(new_buffer) >= @max_buffer_size do
      do_flush(new_buffer)
      {:noreply, %{state | buffer: []}}
    else
      {:noreply, %{state | buffer: new_buffer}}
    end
  end

  @impl GenServer
  def handle_call(:flush, _from, %{buffer: buffer} = state) do
    do_flush(buffer)
    {:reply, :ok, %{state | buffer: []}}
  end

  @impl GenServer
  def handle_info(:scheduled_flush, %{buffer: buffer} = state) do
    do_flush(buffer)
    schedule_flush()
    {:noreply, %{state | buffer: []}}
  end

  defp schedule_flush do
    Process.send_after(self(), :scheduled_flush, @flush_interval_ms)
  end

  defp do_flush([]), do: :ok
  defp do_flush(buffer) do
    buffer
    |> Enum.reverse()
    |> Enum.chunk_every(100)
    |> Enum.each(fn chunk ->
      # Bulk insert
      Fosm.Repo.insert_all(Fosm.TransitionLog, chunk)
    end)
  end
end
```

---

## 12. LiveView Admin UI

### Dashboard

```elixir
defmodule FosmWeb.Admin.DashboardLive do
  use FosmWeb, :live_view

  def mount(_params, _session, socket) do
    apps = Fosm.Registry.all()

    apps_with_stats = Enum.map(apps, fn {slug, module} ->
      {slug, module, %{
        total: count_records(module),
        states: state_distribution(module)
      }}
    end)

    {:ok, assign(socket, apps: apps_with_stats)}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <h1 class="text-2xl font-bold mb-6">FOSM Admin Dashboard</h1>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%= for {slug, module, stats} <- @apps do %>
          <.link navigate={~p"/fosm/admin/apps/#{slug}"} class="block">
            <div class="bg-white p-4 rounded shadow hover:shadow-md transition">
              <h2 class="font-semibold text-lg"><%= module.__schema__(:source) %></h2>
              <p class="text-gray-600 text-sm"><%= stats.total %> records</p>
              <div class="mt-2 flex flex-wrap gap-2">
                <%= for {state, count} <- stats.states do %>
                  <span class="text-xs bg-gray-100 px-2 py-1 rounded">
                    <%= state %>: <%= count %>
                  </span>
                <% end %>
              </div>
            </div>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  defp count_records(module) do
    Fosm.Repo.aggregate(module, :count)
  end

  defp state_distribution(module) do
    import Ecto.Query

    lifecycle = module.fosm_lifecycle()

    from(r in module,
      group_by: r.state,
      select: {r.state, count(r.id)}
    )
    |> Fosm.Repo.all()
    |> Map.new()
  end
end
```

### Agent Chat

```elixir
defmodule FosmWeb.Admin.Agent.ChatLive do
  use FosmWeb, :live_view

  def mount(%{"slug" => slug}, _session, socket) do
    module = Fosm.Registry.lookup!(slug)
    agent = build_agent(module)

    {:ok, assign(socket,
      slug: slug,
      module: module,
      agent: agent,
      messages: [],
      input: ""
    )}
  end

  def handle_event("send", %{"message" => text}, socket) do
    messages = socket.assigns.messages ++ [%{role: "user", content: text}]

    # Run agent (async to not block UI)
    Task.async(fn ->
      socket.assigns.agent.run(text)
    end)

    {:noreply, assign(socket, messages: messages, input: "")}
  end

  def handle_info({ref, {:ok, result}}, socket) when is_reference(ref) do
    messages = socket.assigns.messages ++ [
      %{role: "assistant", content: result.text, tool_calls: result.tool_calls}
    ]

    {:noreply, assign(socket, messages: messages)}
  end

  def render(assigns) do
    ~H"""
    <div class="container mx-auto p-6">
      <h1 class="text-2xl font-bold mb-4">Agent Chat: <%= @slug %></h1>

      <div class="bg-gray-50 rounded-lg p-4 h-96 overflow-y-auto mb-4">
        <%= for msg <- @messages do %>
          <div class={"mb-2 #{if msg.role == "user", do: "text-right", else: "text-left"}">
            <div class={"inline-block p-2 rounded #{if msg.role == "user", do: "bg-blue-100", else: "bg-white border"}">
              <p class="text-sm"><%= msg.content %></p>
              <%= if msg[:tool_calls] do %>
                <div class="mt-1 text-xs text-gray-500">
                  Tools: <%= Enum.map(msg.tool_calls, & &1.name) |> Enum.join(", ") %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <form phx-submit="send" class="flex gap-2">
        <input
          type="text"
          name="message"
          value={@input}
          placeholder="Ask the agent..."
          class="flex-1 border rounded px-3 py-2"
        />
        <button type="submit" class="bg-blue-500 text-white px-4 py-2 rounded">
          Send
        </button>
      </form>
    </div>
    """
  end
end
```

---

## 13. AI Agent Integration

Using Instructor for structured LLM outputs.

```elixir
defmodule Fosm.Agent do
  @moduledoc """
  Base module for FOSM AI agents.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @model_class opts[:model_class]
      @default_model opts[:default_model] || "anthropic/claude-sonnet-4-20250514"

      def model_class, do: @model_class
      def default_model, do: @default_model

      def tools do
        build_standard_tools() ++ build_custom_tools()
      end

      def build_agent(opts \\ []) do
        model = opts[:model] || @default_model
        instructions = build_system_instructions(opts[:instructions])

        %Fosm.Agent.Runtime{
          model: model,
          tools: tools(),
          instructions: instructions
        }
      end

      defp build_standard_tools do
        lifecycle = @model_class.fosm_lifecycle()
        resource_name = @model_class |> Module.split() |> List.last() |> Macro.underscore()

        [
          build_list_tool(resource_name),
          build_get_tool(resource_name),
          build_available_events_tool(resource_name),
          build_transition_history_tool(resource_name)
        ] ++ build_event_tools(lifecycle, resource_name)
      end

      defp build_list_tool(name) do
        %{
          name: "list_#{name}s",
          description: "List #{name}s with their current state. Pass state to filter.",
          parameters: %{
            type: "object",
            properties: %{
              state: %{type: "string", description: "Optional state filter"}
            }
          },
          handler: fn args ->
            query = if args["state"],
              do: where(@model_class, state: args["state"]),
              else: @model_class

            Fosm.Repo.all(query)
            |> Enum.map(&format_record/1)
          end
        }
      end

      defp build_get_tool(name) do
        %{
          name: "get_#{name}",
          description: "Get a #{name} by ID with its current state and available events.",
          parameters: %{
            type: "object",
            properties: %{
              id: %{type: "integer"}
            },
            required: ["id"]
          },
          handler: fn args ->
            case Fosm.Repo.get(@model_class, args["id"]) do
              nil -> %{error: "#{name} ##{args["id"]} not found"}
              record ->
                Map.merge(
                  format_record(record),
                  %{
                    available_events: @model_class.available_events(record)
                  }
                )
            end
          end
        }
      end

      defp build_event_tools(lifecycle, resource_name) do
        Enum.map(lifecycle.events, fn event ->
          from_desc = Enum.join(event.from_states, " or ")
          has_guards = get_guards(lifecycle, event.name) != []
          guard_note = if has_guards, do: " Requires guards.", else: ""

          %{
            name: "#{event.name}_#{resource_name}",
            description: "Fire the '#{event.name}' event. Valid from [#{from_desc}] → #{event.to_state}.#{guard_note}",
            parameters: %{
              type: "object",
              properties: %{
                id: %{type: "integer", description: "The #{resource_name} ID"}
              },
              required: ["id"]
            },
            handler: fn args ->
              record = Fosm.Repo.get(@model_class, args["id"])

              unless record do
                return %{success: false, error: "#{resource_name} ##{args["id"]} not found"}
              end

              case @model_class.fire!(record, event.name, actor: :agent) do
                {:ok, updated} ->
                  %{success: true, id: updated.id, new_state: updated.state}

                {:error, reason} ->
                  %{success: false, error: format_error(reason), current_state: record.state}
              end
            end
          }
        end)
      end

      defp build_system_instructions(extra) do
        lifecycle = @model_class.fosm_lifecycle()

        state_names = Enum.map(lifecycle.states, & &1.name) |> Enum.join(", ")
        terminal_states = lifecycle.states |> Enum.filter(& &1.terminal) |> Enum.map(& &1.name) |> Enum.join(", ")
        event_names = Enum.map(lifecycle.events, & &1.name) |> Enum.join(", ")
        resource_name = @model_class |> Module.split() |> List.last() |> Macro.underscore()

        base = """
        You are a FOSM AI agent managing #{@model_class.__schema__(:source)}.

        ARCHITECTURE CONSTRAINTS:
        1. State changes ONLY via lifecycle event tools. Never direct updates.
        2. Valid states: #{state_names}
        3. Terminal states (no transitions): #{terminal_states}
        4. Available events: #{event_names}
        5. ALWAYS call available_events_for_#{resource_name} before firing.
        6. If a tool returns { success: false }, DO NOT retry.
        7. Records in terminal states cannot transition.
        8. Think step by step. State reasoning before actions.
        """

        if extra, do: base <> "\n\n" <> extra, else: base
      end

      defp format_record(record) do
        %{
          id: record.id,
          state: record.state
        }
      end

      defp format_error(%Fosm.Errors.GuardFailed{} = e) do
        "Guard '#{e.guard}' failed" <> if(e.reason, do: ": #{e.reason}", else: "")
      end
      defp format_error(%Fosm.Errors.TerminalState{}), do: "Terminal state - no transitions allowed"
      defp format_error(%Fosm.Errors.InvalidTransition{} = e), do: "Cannot #{e.event} from #{e.from}"
      defp format_error(%Fosm.Errors.AccessDenied{}), do: "Access denied"
      defp format_error(e), do: Exception.message(e)

      # Override to add custom tools
      defp build_custom_tools, do: []

      defoverridable build_custom_tools: 0
    end
  end

  # Agent runtime struct
  defstruct [:model, :tools, :instructions]

  def run(%__MODULE__{} = agent, prompt) do
    # Use Instructor or direct API
    # This is a simplified version

    messages = [
      %{role: "system", content: agent.instructions},
      %{role: "user", content: prompt}
    ]

    # Call LLM with tools
    # Parse tool calls
    # Execute tools
    # Return result
  end
end
```

---

## Complete Feature Checklist

### Core Features
- [x] State definitions (initial, terminal)
- [x] Event definitions (from, to)
- [x] Guard definitions with rich error messages
- [x] Side effects (immediate and deferred)
- [x] Access control / RBAC
- [x] The `fire!` function
- [x] Row locking (SELECT FOR UPDATE)
- [x] State predicates (`draft?`, `sent?`, etc.)
- [x] Event methods (`send!`, `can_send?`)

### Enhanced Features
- [x] `why_cannot_fire?` introspection
- [x] Terminal state enforcement (no bypass)
- [x] Guard evaluation with rich return values
- [x] Side effect error propagation
- [x] Deferred side effects (after commit)
- [x] Auto-captured causal chain (`triggered_by`)
- [x] State snapshots (multiple strategies)
- [x] Arbitrary observations in snapshots
- [x] Graph generation (JSON output)

### Infrastructure
- [x] Transition log (immutable)
- [x] Role assignments (type-level + record-level)
- [x] Access events (RBAC audit)
- [x] Webhook subscriptions
- [x] Per-process RBAC cache
- [x] Oban jobs (logs, webhooks, access events)
- [x] Transition buffer GenServer

### Admin UI
- [x] Dashboard (LiveView)
- [x] App detail with lifecycle visualization
- [x] Role management
- [x] Transition log viewer
- [x] Agent explorer (tool catalog)
- [x] Agent chat interface
- [x] Webhook configuration

### AI Agent
- [x] Base agent module
- [x] Auto-generated tools from lifecycle
- [x] System prompt generation
- [x] Bounded autonomy (fire! only)
- [x] Custom tool support

### Developer Experience
- [x] Mix generator (`fosm.gen.app`)
- [x] Graph generation task
- [x] Comprehensive error types
- [x] Query methods on records
- [x] Documentation

---

## Migration Notes from Rails

### What Gets Simpler
1. **Deferred side effects** - Process dictionary instead of `after_commit` callbacks
2. **RBAC cache** - Process dictionary instead of `CurrentAttributes`
3. **Admin UI** - LiveView instead of ERB + Turbo
4. **Background jobs** - Oban instead of ActiveJob configuration
5. **Transition buffer** - GenServer instead of Thread-based

### What Needs Care
1. **Row locking** - Raw SQL for `SELECT FOR UPDATE`
2. **LLM integration** - No Gemlings equivalent, need Instructor or custom
3. **Connection pooling** - Different model than Rails' multi-db

### New Capabilities
1. **Compile-time validation** - Macros validate DSL at compile time
2. **Real-time updates** - LiveView PubSub for transition events
3. **Better observability** - BEAM introspection tools
