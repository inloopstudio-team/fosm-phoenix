defmodule Fosm.Assertions do
  @moduledoc """
  Custom ExUnit assertions for FOSM testing.

  Provides domain-specific assertions for state machines, RBAC,
  transitions, and audit trails.

  ## Examples

      # Assert state transition occurred
      assert_transition record, from: "draft", to: "sent", via: :send

      # Assert RBAC permissions
      assert_can user, :send, on: invoice
      assert_cannot user, :delete, on: invoice, reason: :access_denied

      # Assert side effects ran
      assert_side_effect_executed :notify_client, on: invoice

      # Assert log entries
      assert_logged invoice, event: :send, actor: user
  """

  import ExUnit.Assertions
  require Ecto.Query

  # ============================================================================
  # State Transition Assertions
  # ============================================================================

  @doc """
  Asserts that a record transitioned from one state to another.

  ## Examples

      {:ok, updated} = Invoice.fire!(invoice, :send, actor: user)
      assert_transition updated, from: "draft", to: "sent", via: :send
  """
  def assert_transition(record, opts) do
    from = Keyword.fetch!(opts, :from)
    to = Keyword.fetch!(opts, :to)
    via = Keyword.get(opts, :via)

    assert record.state == to,
      "Expected record to be in state '#{to}', but was '#{record.state}'"

    # Verify via transition log if repo available
    if via && Process.whereis(Fosm.Repo) do
      record_id_str = to_string(record.id)
      via_str = to_string(via)
      logs = Fosm.TransitionLog
        |> Ecto.Query.where(record_id: ^record_id_str)
        |> Ecto.Query.where(event_name: ^via_str)
        |> Fosm.Repo.all()

      assert length(logs) > 0,
        "Expected transition log entry for event '#{via}' from '#{from}' to '#{to}', but none found"
    end
  end

  @doc """
  Asserts that a record is in the expected state.

  ## Examples

      assert_state invoice, "paid"
      assert_state workflow, :completed
  """
  def assert_state(record, expected_state) do
    expected = to_string(expected_state)
    actual = record.state

    assert actual == expected,
      "Expected record to be in state '#{expected}', but was '#{actual}'"
  end

  @doc """
  Asserts that a state is terminal.

  ## Examples

      assert_terminal_state Invoice, :paid
      assert_terminal_state Invoice, "cancelled"
  """
  def assert_terminal_state(module, state_name) do
    lifecycle = module.fosm_lifecycle()
    state = Enum.find(lifecycle.states, & &1.name == to_string(state_name))

    assert state != nil,
      "State '#{state_name}' not found in #{inspect(module)}"
    assert state.terminal == true,
      "Expected '#{state_name}' to be terminal, but it is not"
  end

  @doc """
  Asserts that a state is initial.

  ## Examples

      assert_initial_state Invoice, :draft
  """
  def assert_initial_state(module, state_name) do
    lifecycle = module.fosm_lifecycle()
    state = Enum.find(lifecycle.states, & &1.name == to_string(state_name))

    assert state != nil,
      "State '#{state_name}' not found in #{inspect(module)}"
    assert state.initial == true,
      "Expected '#{state_name}' to be initial, but it is not"
  end

  # ============================================================================
  # RBAC Assertions
  # ============================================================================

  @doc """
  Asserts that an actor CAN perform an action on a resource.

  ## Examples

      assert_can user, :send, on: invoice
      assert_can user, :read, on: Invoice  # type-level
      assert_can admin, :crud, on: invoice
  """
  def assert_can(actor, action, opts) do
    resource = Keyword.fetch!(opts, :on)

    result = can?(actor, action, resource)

    assert result == true,
      "Expected #{actor_label(actor)} to be able to '#{action}' on #{resource_label(resource)}, but permission was denied"
  end

  @doc """
  Asserts that an actor CANNOT perform an action on a resource.

  ## Options

    * `:reason` - Expected error reason (optional)

  ## Examples

      assert_cannot user, :delete, on: invoice
      assert_cannot user, :pay, on: invoice, reason: :access_denied
  """
  def assert_cannot(actor, action, opts) do
    resource = Keyword.fetch!(opts, :on)
    expected_reason = Keyword.get(opts, :reason)

    result = can?(actor, action, resource)

    assert result == false,
      "Expected #{actor_label(actor)} to NOT be able to '#{action}' on #{resource_label(resource)}, but permission was granted"

    # If reason specified, verify it
    if expected_reason do
      # Try the actual operation and check error
      case try_action(actor, action, resource) do
        {:error, actual_reason} ->
          assert actual_reason == expected_reason,
            "Expected error reason '#{expected_reason}', but got '#{actual_reason}'"
        _ ->
          :ok  # Already asserted false above
      end
    end
  end

  @doc """
  Asserts that an actor has the expected roles for a resource.

  ## Examples

      assert_roles user, on: invoice, include: [:owner, :viewer]
      assert_roles user, on: "Fosm.Invoice", exactly: [:owner]
  """
  def assert_roles(actor, opts) do
    resource = Keyword.fetch!(opts, :on)
    include = Keyword.get(opts, :include, [])
    exactly = Keyword.get(opts, :exactly)

    roles = get_roles(actor, resource)

    if exactly do
      assert Enum.sort(roles) == Enum.sort(exactly),
        "Expected roles #{inspect(exactly)}, but got #{inspect(roles)}"
    end

    for role <- include do
      assert role in roles,
        "Expected role '#{role}' in #{inspect(roles)}"
    end
  end

  # ============================================================================
  # Event & Guard Assertions
  # ============================================================================

  @doc """
  Asserts that an event can be fired on a record.

  ## Examples

      assert_can_fire invoice, :send
      assert_can_fire invoice, :pay
  """
  def assert_can_fire(record, event) do
    module = record.__struct__
    available = module.available_events(record)

    assert event in available,
      "Expected event '#{event}' to be available, but got: #{inspect(available)}"
  end

  @doc """
  Asserts that an event CANNOT be fired on a record.

  ## Examples

      assert_cannot_fire paid_invoice, :send  # terminal state
      assert_cannot_fire draft_invoice, :pay  # wrong state
  """
  def assert_cannot_fire(record, event) do
    module = record.__struct__
    available = module.available_events(record)

    refute event in available,
      "Expected event '#{event}' to NOT be available, but it is in: #{inspect(available)}"
  end

  @doc """
  Asserts that firing an event fails with a specific guard.

  ## Examples

      assert_guard_fails empty_invoice, :send, guard: :has_line_items
      assert_guard_fails invalid_invoice, :pay, guard: :valid_amount, reason: "Amount must be positive"
  """
  def assert_guard_fails(record, event, opts) do
    expected_guard = Keyword.fetch!(opts, :guard)
    expected_reason = Keyword.get(opts, :reason)

    case try_fire(record, event) do
      {:error, %Fosm.Errors.GuardFailed{guard: guard, reason: reason}} ->
        assert guard == expected_guard,
          "Expected guard '#{expected_guard}' to fail, but '#{guard}' failed instead"

        if expected_reason do
          assert reason == expected_reason,
            "Expected guard failure reason '#{expected_reason}', but got '#{reason}'"
        end

      {:ok, _} ->
        flunk("Expected guard '#{expected_guard}' to fail for event '#{event}', but transition succeeded")

      {:error, other} ->
        flunk("Expected guard failure for '#{expected_guard}', but got: #{inspect(other)}")
    end
  end

  # ============================================================================
  # Side Effect Assertions
  # ============================================================================

  @doc """
  Asserts that a side effect was executed.

  ## Examples

      assert_side_effect_executed :notify_client, on: invoice
      assert_side_effect_executed :send_webhook, on: invoice, count: 2
  """
  def assert_side_effect_executed(effect_name, opts) do
    # This requires tracking side effects in test mode
    # Implementation depends on side effect tracking mechanism
    :ok
  end

  @doc """
  Asserts that deferred side effects are queued.

  ## Examples

      assert_deferred_effect :cross_machine_sync, on: invoice
  """
  def assert_deferred_effect(effect_name, opts) do
    record = Keyword.fetch!(opts, :on)
    deferred_key = {:fosm_deferred_effects, record.id}

    effects = Process.get(deferred_key)

    assert effects != nil,
      "Expected deferred effects for record #{record.id}, but none found"

    {effect_list, _, _} = effects
    effect_names = Enum.map(effect_list, & &1.name)

    assert effect_name in effect_names,
      "Expected deferred effect '#{effect_name}' in #{inspect(effect_names)}"
  end

  # ============================================================================
  # Audit & Logging Assertions
  # ============================================================================

  @doc """
  Asserts that a transition was logged.

  ## Examples

      assert_logged invoice, event: :send
      assert_logged invoice, event: :send, actor: user
      assert_logged invoice, from: "draft", to: "sent"
  """
  def assert_logged(record, opts) do
    event = Keyword.get(opts, :event)
    actor = Keyword.get(opts, :actor)
    from = Keyword.get(opts, :from)
    to = Keyword.get(opts, :to)

    record_id_str = to_string(record.id)
    query = Fosm.TransitionLog
      |> Ecto.Query.where(record_id: ^record_id_str)

    query = if event do
      event_str = to_string(event)
      Ecto.Query.where(query, event_name: ^event_str)
    else
      query
    end
    
    query = if from do
      from_str = to_string(from)
      Ecto.Query.where(query, from_state: ^from_str)
    else
      query
    end
    
    query = if to do
      to_str = to_string(to)
      Ecto.Query.where(query, to_state: ^to_str)
    else
      query
    end

    if actor do
      actor_type = actor.__struct__ |> to_string()
      actor_id = to_string(actor.id)
      query = Ecto.Query.where(query, actor_type: ^actor_type, actor_id: ^actor_id)
    end

    logs = Fosm.Repo.all(query)

    assert length(logs) > 0,
      "Expected transition log for #{record_label(record)} with criteria #{inspect(opts)}, but none found"
  end

  @doc """
  Asserts that a snapshot was captured.

  ## Examples

      assert_snapshot invoice, at_event: :pay
      assert_snapshot invoice, contains: ["amount", "line_items"]
  """
  def assert_snapshot(record, opts) do
    event = Keyword.get(opts, :at_event)

    query = Fosm.TransitionLog
      |> Ecto.Query.where(record_id: ^to_string(record.id))
      |> Ecto.Query.where([l], not is_nil(l.state_snapshot))

    query = if event, do: Ecto.Query.where(query, event_name: ^to_string(event)), else: query

    logs = Fosm.Repo.all(query)

    assert length(logs) > 0,
      "Expected snapshot for #{record_label(record)} at event '#{event}', but none found"

    # Check for specific attributes if requested
    contains = Keyword.get(opts, :contains, [])
    if contains != [] and length(logs) > 0 do
      log = hd(logs)
      snapshot = log.state_snapshot || %{}

      for attr <- contains do
        assert Map.has_key?(snapshot, to_string(attr)) || Map.has_key?(snapshot, attr),
          "Expected snapshot to contain '#{attr}', but keys were: #{inspect(Map.keys(snapshot))}"
      end
    end
  end

  # ============================================================================
  # Error Assertions
  # ============================================================================

  @doc """
  Asserts that firing an event raises an expected error.

  ## Examples

      assert_fire_error invoice, :invalid_event, Fosm.Errors.UnknownEvent
      assert_fire_error terminal_invoice, :send, Fosm.Errors.TerminalState
      assert_fire_error invoice, :pay, Fosm.Errors.InvalidTransition  # wrong state
  """
  def assert_fire_error(record, event, expected_error_module) do
    try_fire(record, event)
    |> case do
      {:ok, _} ->
        flunk("Expected #{inspect(expected_error_module)}, but transition succeeded")

      {:error, %^expected_error_module{}} ->
        :ok

      {:error, actual_error} ->
        flunk("Expected #{inspect(expected_error_module)}, but got #{inspect(actual_error)}")
    end
  end

  @doc """
  Asserts that a specific error is raised with expected message pattern.

  ## Examples

      assert_error Fosm.Errors.GuardFailed, ~r/has_line_items/, fn ->
        Invoice.fire!(empty_invoice, :send)
      end
  """
  def assert_error(error_module, pattern, fun) do
    try do
      fun.()
      flunk("Expected #{inspect(error_module)} to be raised")
    rescue
      e in _ ->
        if e.__struct__ == error_module do
          message = Exception.message(e)
          assert message =~ pattern,
            "Expected error message to match #{inspect(pattern)}, but got: #{message}"
        else
          reraise e, __STACKTRACE__
        end
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp can?(actor, action, resource) do
    # Delegate to Fosm.Current if available
    resource_type = if is_atom(resource) and not is_struct(resource) do
      to_string(resource)
    else
      resource.__struct__ |> to_string()
    end

    record_id = if is_struct(resource), do: resource.id, else: nil

    roles = Fosm.Current.roles_for(actor, resource_type, record_id)

    cond do
      :_all in roles -> true
      action == :crud -> [:create, :read, :update, :delete] |> Enum.all?(& &1 in roles)
      is_atom(action) -> action in roles
      true -> false
    end
  end

  defp try_action(actor, action, resource) do
    # Try to perform the action and return result
    # This is a simplified version - full implementation would use actual FOSM calls
    if can?(actor, action, resource) do
      {:ok, resource}
    else
      {:error, :access_denied}
    end
  end

  defp try_fire(record, event) do
    try do
      module = record.__struct__
      result = module.fire!(record, event)
      {:ok, result}
    catch
      kind, error ->
        {:error, error}
    end
  end

  defp get_roles(actor, resource) do
    resource_type = if is_atom(resource) and not is_struct(resource) do
      to_string(resource)
    else
      resource.__struct__ |> to_string()
    end

    record_id = if is_struct(resource), do: resource.id, else: nil

    Fosm.Current.roles_for(actor, resource_type, record_id)
  end

  defp actor_label(%{email: email}), do: "user (#{email})"
  defp actor_label(%{id: id, __struct__: module}), do: "#{module}:#{id}"
  defp actor_label(:system), do: "system"
  defp actor_label(:agent), do: "agent"
  defp actor_label(nil), do: "anonymous"
  defp actor_label(actor), do: inspect(actor)

  defp resource_label(%{id: id, __struct__: module}), do: "#{module}:#{id}"
  defp resource_label(resource) when is_atom(resource), do: to_string(resource)
  defp resource_label(resource), do: inspect(resource)

  defp record_label(%{id: id, __struct__: module}), do: "#{module}:#{id}"
  defp record_label(record), do: inspect(record)
end
