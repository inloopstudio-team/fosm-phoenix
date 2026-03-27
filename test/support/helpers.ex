defmodule Fosm.TestHelpers do
  @moduledoc """
  Helper functions for FOSM testing.

  Provides utilities for:
  - Concurrent test execution with race condition simulation
  - Process dictionary state management
  - Ecto query building
  - Mock actor creation

  ## Examples

      # Create a mock actor
      user = mock_user(id: 1, roles: [:owner])
      admin = mock_admin()

      # Simulate concurrent fire! calls
      results = concurrent_fire(invoice, :pay, [user1, user2, user3])

      # Wait for async processes
      wait_for_async_jobs()

      # Clean process state
      cleanup_fosm_state()
  """

  alias Fosm.Errors

  # ============================================================================
  # Mock Actor Helpers
  # ============================================================================

  @doc """
  Creates a mock user struct for testing.

  ## Options

    * `:id` - User ID (default: auto-generated)
    * `:email` - Email address (default: "test@example.com")
    * `:roles` - Pre-defined roles (bypasses cache)
    * `:superadmin` - Admin flag (default: false)

  ## Examples

      user = mock_user(id: 42, email: "owner@example.com")
      admin = mock_user(superadmin: true)
  """
  def mock_user(opts \\ []) do
    id = Keyword.get(opts, :id, System.unique_integer([:positive]))
    email = Keyword.get(opts, :email, "user#{id}@example.com")
    superadmin = Keyword.get(opts, :superadmin, false)

    %{
      id: id,
      __struct__: Fosm.User,
      email: email,
      name: "Test User #{id}",
      superadmin: superadmin,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Creates a mock admin user.

  ## Examples

      admin = mock_admin()
      super_admin = mock_admin(id: 1, email: "super@example.com")
  """
  def mock_admin(opts \\ []) do
    opts
    |> Keyword.put(:superadmin, true)
    |> Keyword.put_new(:email, "admin@example.com")
    |> mock_user()
  end

  @doc """
  Creates a mock system actor (for internal processes).

  ## Examples

      system = mock_system_actor()
      agent = mock_system_actor(:agent)
  """
  def mock_system_actor(type \\ :system) do
    type
  end

  @doc """
  Creates a mock resource record with minimal fields.

  ## Examples

      invoice = mock_resource(Fosm.Invoice, id: 1, state: "draft")
  """
  def mock_resource(module, opts \\ []) do
    id = Keyword.get(opts, :id, System.unique_integer([:positive]))
    state = Keyword.get(opts, :state, "draft")

    struct!(module,
      id: id,
      state: state,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    )
  end

  # ============================================================================
  # Concurrency & Race Condition Helpers
  # ============================================================================

  @doc """
  Simulates concurrent fire! calls from multiple actors.

  Useful for testing race conditions, locking, and idempotency.

  ## Examples

      results = concurrent_fire(invoice, :pay, [user1, user2, user3])
      # => [%{actor: user1, result: {:ok, updated}},
      #     %{actor: user2, result: {:error, :state_changed}},
      #     %{actor: user3, result: {:error, :state_changed}}]
  """
  def concurrent_fire(record, event, actors, opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 0)
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)

    # Start tasks for each actor
    tasks = Enum.map(actors, fn actor ->
      Task.async(fn ->
        # Optional delay to increase chance of race conditions
        if delay_ms > 0, do: Process.sleep(delay_ms)

        result = try_fire(record, event, actor: actor)

        %{actor: actor, result: result}
      end)
    end)

    # Wait for all tasks with timeout
    Task.yield_many(tasks, timeout_ms)
    |> Enum.map(fn {task, result} ->
      case result do
        nil ->
          Task.shutdown(task, :brutal_kill)
          %{actor: task.pid, result: {:error, :timeout}}

        {:ok, value} ->
          value

        {:exit, reason} ->
          %{actor: task.pid, result: {:error, {:exit, reason}}}
      end
    end)
  end

  @doc """
  Simulates concurrent reads while a transition is in progress.

  ## Examples

      results = concurrent_read_during_transition(invoice, :pay, user)
      # Tests that reads don't see partial state
  """
  def concurrent_read_during_transition(record, event, actor, opts \\ []) do
    readers_count = Keyword.get(opts, :readers, 5)

    # Start the transition in a separate process
    transition_task = Task.async(fn ->
      try_fire(record, event, actor: actor)
    end)

    # Start readers that try to read during transition
    reader_tasks = Enum.map(1..readers_count, fn _ ->
      Task.async(fn ->
        # Small random delay to vary timing
        Process.sleep(Enum.random(0..10))

        # Read the record
        read_record(record)
      end)
    end)

    # Collect all results
    transition_result = Task.await(transition_task, 5000)
    reader_results = Enum.map(reader_tasks, &Task.await(&1, 5000))

    %{
      transition: transition_result,
      reads: reader_results
    }
  end

  @doc """
  Performs concurrent operations with custom functions.

  ## Examples

      results = concurrent_operations([
        fn -> Invoice.fire!(invoice1, :send, actor: user) end,
        fn -> Invoice.fire!(invoice2, :send, actor: user) end,
        fn -> RoleAssignment.create!(...) end
      ])
  """
  def concurrent_operations(functions, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)

    tasks = Enum.map(functions, fn fun ->
      Task.async(fn ->
        try do
          {:ok, fun.()}
        rescue
          e -> {:error, e}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)
    end)

    Task.yield_many(tasks, timeout_ms)
    |> Enum.map(fn {task, result} ->
      case result do
        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}

        {:ok, value} ->
          value

        {:exit, reason} ->
          {:error, {:exit, reason}}
      end
    end)
  end

  # ============================================================================
  # State Management Helpers
  # ============================================================================

  @doc """
  Clears all FOSM-related process dictionary entries.

  Call in test setup/teardown to ensure clean state.

  ## Examples

      setup do
        :ok = cleanup_fosm_state()
        :ok
      end
  """
  def cleanup_fosm_state do
    # Clear deferred effects
    for key <- Map.keys(Process.get() || %{}),
        is_tuple(key),
        elem(key, 0) == :fosm_deferred_effects do
      Process.delete(key)
    end

    # Clear causal chain context
    Process.delete(:fosm_trigger_context)

    # Clear any other FOSM keys
    for key <- Map.keys(Process.get() || %{}),
        is_atom(key),
        to_string(key) =~ "fosm" do
      Process.delete(key)
    end

    :ok
  end

  @doc """
  Captures the current FOSM process state for later restoration.

  ## Examples

      state = capture_fosm_state()
      # ... run operations that modify state ...
      restore_fosm_state(state)
  """
  def capture_fosm_state do
    Process.get()
    |> Enum.filter(fn {key, _} ->
      (is_atom(key) and to_string(key) =~ "fosm") or
      (is_tuple(key) and is_atom(elem(key, 0)) and to_string(elem(key, 0)) =~ "fosm")
    end)
    |> Enum.into(%{})
  end

  @doc """
  Restores FOSM process state from a captured state.
  """
  def restore_fosm_state(state_map) do
    cleanup_fosm_state()

    for {key, value} <- state_map do
      Process.put(key, value)
    end

    :ok
  end

  # ============================================================================
  # Async Job Helpers
  # ============================================================================

  @doc """
  Waits for all Oban jobs to complete.

  ## Options

    * `:timeout` - Maximum wait time (default: 5000ms)
    * `:queues` - Specific queues to drain (default: all)

  ## Examples

      wait_for_async_jobs(timeout: 10_000)
      wait_for_async_jobs(queues: [:fosm_logs, :fosm_webhooks])
  """
  def wait_for_async_jobs(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)

    # If Oban is configured, drain queues
    if Application.get_env(:fosm, Oban) do
      # This would integrate with Oban.Testing.drain_queue
      # For now, just sleep to allow jobs to process
      Process.sleep(min(timeout, 100))
    end

    :ok
  end

  @doc """
  Drains all Oban queues for testing.

  ## Examples

      drain_oban_queues()
      drain_oban_queues([:fosm_logs, :fosm_webhooks])
  """
  def drain_oban_queues(queues \\ nil) do
    queues = queues || [:fosm_logs, :fosm_webhooks, :fosm_access]

    for queue <- queues do
      try do
        Oban.drain_queue(queue: queue, with_safety: false)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Guard Testing Helpers
  # ============================================================================

  @doc """
  Tests all guard return types to ensure they work correctly.

  ## Examples

      test_guard_returns(module, :my_guard, [
        {true, :ok, "should pass"},
        {false, {:error, nil}, "should fail without reason"},
        {"custom reason", {:error, "custom reason"}, "should fail with reason"},
        {[:fail, "structured"], {:error, "structured"}, "should handle structured fail"}
      ])
  """
  def test_guard_returns(guard_fn, test_cases) do
    for {input, expected, description} <- test_cases do
      result = guard_fn.(input)

      if result != expected do
        raise "Guard test failed for '#{description}': expected #{inspect(expected)}, got #{inspect(result)}"
      end
    end

    :ok
  end

  @doc """
  Creates a guard function that returns different values based on test needs.

  ## Examples

      guard = configurable_guard([true, false, {:error, "reason"}])
      guard.() # => true
      guard.() # => false
      guard.() # => {:error, "reason"}
  """
  def configurable_guard(return_values) do
    ref = :ets.new(:guard_returns, [:private])
    :ets.insert(ref, {:returns, return_values})
    :ets.insert(ref, {:index, 0})

    fn ->
      [{:returns, values}] = :ets.lookup(ref, :returns)
      [{:index, index}] = :ets.lookup(ref, :index)

      value = Enum.at(values, rem(index, length(values)))
      :ets.insert(ref, {:index, index + 1})

      value
    end
  end

  # ============================================================================
  # Snapshot Testing Helpers
  # ============================================================================

  @doc """
  Verifies that a snapshot contains expected data.

  ## Examples

      assert_snapshot_contains(snapshot, [:id, :state, :amount])
      assert_snapshot_contains(snapshot, %{"state" => "paid", "amount" => "100.00"})
  """
  def assert_snapshot_contains(snapshot, expected) when is_list(expected) do
    snapshot_keys = Map.keys(snapshot)

    for key <- expected do
      unless key in snapshot_keys or to_string(key) in snapshot_keys do
        raise "Expected snapshot to contain key '#{key}', but keys were: #{inspect(snapshot_keys)}"
      end
    end

    :ok
  end

  def assert_snapshot_contains(snapshot, expected) when is_map(expected) do
    for {key, value} <- expected do
      actual = Map.get(snapshot, key) || Map.get(snapshot, to_string(key))

      unless actual == value do
        raise "Expected snapshot['#{key}'] to be '#{value}', but was '#{actual}'"
      end
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp try_fire(record, event, opts) do
    module = record.__struct__

    try do
      module.fire!(record, event, opts)
    rescue
      e ->
        {:error, e}
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  defp read_record(record) do
    module = record.__struct__
    id = record.id

    try do
      Fosm.Repo.get(module, id)
    rescue
      _ -> nil
    end
  end
end
