defmodule Fosm.TestHelpersTest do
  @moduledoc """
  Tests for test helper functions.

  Verifies concurrency helpers, state management, and mock creation.
  """
  use Fosm.DataCase, async: true

  import Fosm.TestHelpers
  import Fosm.Factory

  describe "mock_user/1" do
    test "creates user with defaults" do
      user = mock_user()

      assert user.__struct__ == Fosm.User
      assert user.id != nil
      assert user.email =~ ~r/@example\.com$/
      assert user.superadmin == false
    end

    test "creates user with custom options" do
      user = mock_user(id: 42, email: "custom@test.com", superadmin: true)

      assert user.id == 42
      assert user.email == "custom@test.com"
      assert user.superadmin == true
    end
  end

  describe "mock_admin/1" do
    test "creates admin user" do
      admin = mock_admin()

      assert admin.superadmin == true
      assert admin.email =~ ~r/admin/
    end

    test "accepts custom options" do
      admin = mock_admin(id: 1, email: "super@admin.com")

      assert admin.id == 1
      assert admin.email == "super@admin.com"
    end
  end

  describe "mock_system_actor/1" do
    test "returns system by default" do
      assert mock_system_actor() == :system
    end

    test "returns specified actor type" do
      assert mock_system_actor(:agent) == :agent
    end
  end

  describe "mock_resource/2" do
    test "creates resource with defaults" do
      resource = mock_resource(Fosm.Invoice)

      assert resource.__struct__ == Fosm.Invoice
      assert resource.id != nil
      assert resource.state == "draft"
    end

    test "accepts custom options" do
      resource = mock_resource(Fosm.Invoice, id: 100, state: "sent")

      assert resource.id == 100
      assert resource.state == "sent"
    end
  end

  describe "cleanup_fosm_state/0" do
    test "clears process dictionary" do
      # Set some FOSM-related keys
      Process.put(:fosm_deferred_effects_1, :test)
      Process.put(:fosm_trigger_context, %{test: true})
      Process.put(:fosm_test_key, "value")

      # Verify they're set
      assert Process.get(:fosm_deferred_effects_1) == :test
      assert Process.get(:fosm_trigger_context) == %{test: true}

      # Clean up
      :ok = cleanup_fosm_state()

      # Verify cleared
      assert Process.get(:fosm_deferred_effects_1) == nil
      assert Process.get(:fosm_trigger_context) == nil
      assert Process.get(:fosm_test_key) == nil
    end
  end

  describe "capture_fosm_state/0 and restore_fosm_state/1" do
    test "captures and restores state" do
      # Set initial state
      Process.put(:fosm_test_key, "original")

      # Capture
      state = capture_fosm_state()
      assert state[:fosm_test_key] == "original"

      # Modify
      Process.put(:fosm_test_key, "modified")

      # Restore
      restore_fosm_state(state)

      # Verify restored
      assert Process.get(:fosm_test_key) == "original"
    end
  end

  describe "concurrent_operations/2" do
    test "executes functions concurrently" do
      funs = [
        fn -> :result1 end,
        fn -> :result2 end,
        fn -> :result3 end
      ]

      results = concurrent_operations(funs)

      assert {:ok, :result1} in results
      assert {:ok, :result2} in results
      assert {:ok, :result3} in results
    end

    test "handles errors gracefully" do
      funs = [
        fn -> :ok end,
        fn -> raise "error" end
      ]

      results = concurrent_operations(funs, timeout: 1000)

      # At least one should succeed, one should error
      assert Enum.any?(results, fn
        {:ok, :ok} -> true
        _ -> false
      end)
    end
  end

  describe "configurable_guard/1" do
    test "cycles through return values" do
      guard = configurable_guard([true, false, {:error, "reason"}])

      assert guard.() == true
      assert guard.() == false
      assert guard.() == {:error, "reason"}
      assert guard.() == true  # cycles back
    end
  end

  describe "assert_snapshot_contains/2" do
    test "verifies keys exist in snapshot" do
      snapshot = %{"id" => 1, "state" => "paid", "amount" => "100.00"}

      assert assert_snapshot_contains(snapshot, ["id", "state"]) == :ok

      assert_raise RuntimeError, ~r/foo/, fn ->
        assert_snapshot_contains(snapshot, ["foo"])
      end
    end

    test "verifies key-value pairs" do
      snapshot = %{"id" => 1, "state" => "paid"}

      assert assert_snapshot_contains(snapshot, %{"id" => 1, "state" => "paid"}) == :ok

      assert_raise RuntimeError, ~r/wrong/, fn ->
        assert_snapshot_contains(snapshot, %{"state" => "wrong"})
      end
    end
  end

  describe "wait_for_async_jobs/1" do
    test "returns :ok even when Oban not configured" do
      # Should not raise even if Oban isn't running
      assert wait_for_async_jobs() == :ok
      assert wait_for_async_jobs(timeout: 100) == :ok
    end
  end
end
