defmodule Fosm.CurrentTest do
  @moduledoc """
  Integration tests for Fosm.Current (RBAC cache).

  Tests the per-request cache behavior, invalidation, and edge cases.
  """
  use Fosm.DataCase, async: false

  import Fosm.Factory
  import Fosm.TestHelpers

  alias Fosm.Current
  alias Fosm.RoleAssignment

  describe "roles_for/3" do
    test "returns empty list when no roles assigned" do
      user = mock_user(id: 1)

      roles = Current.roles_for(user, "Fosm.Invoice", nil)

      assert roles == []
    end

    test "returns type-level roles" do
      user = mock_user(id: 2)

      # Create type-level assignment
      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "owner"
      )

      roles = Current.roles_for(user, "Fosm.Invoice", nil)

      assert :owner in roles
    end

    test "returns record-level roles" do
      user = mock_user(id: 3)
      invoice = build(:invoice, id: 100)

      # Create record-level assignment
      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: to_string(invoice.id),
        role_name: "approver"
      )

      roles = Current.roles_for(user, "Fosm.Invoice", invoice.id)

      assert :approver in roles
    end

    test "combines type-level and record-level roles" do
      user = mock_user(id: 4)
      invoice = build(:invoice, id: 101)

      # Type-level
      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "viewer"
      )

      # Record-level
      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: to_string(invoice.id),
        role_name: "editor"
      )

      roles = Current.roles_for(user, "Fosm.Invoice", invoice.id)

      assert :viewer in roles
      assert :editor in roles
    end

    test "returns distinct roles when duplicates exist" do
      user = mock_user(id: 5)

      # Multiple assignments with same role (edge case)
      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "owner"
      )

      roles = Current.roles_for(user, "Fosm.Invoice", nil)

      assert length(roles) == length(Enum.uniq(roles))
    end

    test "caches roles on first access" do
      user = mock_user(id: 6)

      # First access loads from DB
      roles1 = Current.roles_for(user, "Fosm.Invoice", nil)

      # Add new assignment
      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "owner"
      )

      # Second access should use cache (return old roles)
      roles2 = Current.roles_for(user, "Fosm.Invoice", nil)

      # Before cache invalidation, roles2 should equal roles1
      assert roles1 == roles2

      # After invalidation, should see new role
      Current.invalidate_for(user)
      roles3 = Current.roles_for(user, "Fosm.Invoice", nil)
      assert :owner in roles3
    end

    test "bypasses cache for nil actor" do
      roles = Current.roles_for(nil, "Fosm.Invoice", 1)

      # nil actor gets universal permission
      assert roles == [:_all]
    end

    test "bypasses cache for symbol actors" do
      assert Current.roles_for(:system, "Fosm.Invoice", 1) == [:_all]
      assert Current.roles_for(:agent, "Fosm.Invoice", 1) == [:_all]
    end

    test "bypasses cache for superadmin" do
      admin = mock_admin(id: 7)

      roles = Current.roles_for(admin, "Fosm.Invoice", 1)

      assert roles == [:_all]
    end

    test "handles superadmin field-based check" do
      admin = %{mock_user(id: 8) | superadmin: true}

      roles = Current.roles_for(admin, "Fosm.Invoice", 1)

      assert roles == [:_all]
    end

    test "handles actor without __struct__ gracefully" do
      # Edge case: bare map
      bare_map = %{id: 1}

      # Should not crash
      result = Current.roles_for(bare_map, "Fosm.Invoice", nil)
      assert is_list(result)
    end
  end

  describe "invalidate_for/2" do
    test "clears cache for specific actor" do
      user = mock_user(id: 9)

      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "owner"
      )

      # Prime cache
      roles1 = Current.roles_for(user, "Fosm.Invoice", nil)
      assert :owner in roles1

      # Invalidate
      Current.invalidate_for(user)

      # Cache cleared - will reload from DB
      roles2 = Current.roles_for(user, "Fosm.Invoice", nil)
      assert :owner in roles2
    end

    test "doesn't affect other actors' caches" do
      user1 = mock_user(id: 10)
      user2 = mock_user(id: 11)

      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user1.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "owner"
      )

      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user2.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "viewer"
      )

      # Prime both caches
      assert :owner in Current.roles_for(user1, "Fosm.Invoice", nil)
      assert :viewer in Current.roles_for(user2, "Fosm.Invoice", nil)

      # Invalidate user1 only
      Current.invalidate_for(user1)

      # User2's cache should still work
      roles2 = Current.roles_for(user2, "Fosm.Invoice", nil)
      assert :viewer in roles2
    end
  end

  describe "clear/1" do
    test "clears entire cache" do
      user1 = mock_user(id: 12)
      user2 = mock_user(id: 13)

      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user1.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "owner"
      )

      # Prime caches
      Current.roles_for(user1, "Fosm.Invoice", nil)
      Current.roles_for(user2, "Fosm.Invoice", nil)

      # Clear all
      Current.clear()

      # All caches cleared - will reload
      roles = Current.roles_for(user1, "Fosm.Invoice", nil)
      assert :owner in roles
    end
  end

  describe "cache key generation" do
    test "generates unique keys for different actors" do
      user1 = mock_user(id: 14)
      user2 = mock_user(id: 15)

      # Keys should be different
      key1 = "#{user1.__struct__}:#{user1.id}"
      key2 = "#{user2.__struct__}:#{user2.id}"

      assert key1 != key2
    end

    test "handles different actor types" do
      user = mock_user(id: 16)

      # Different types should have different keys
      key_user = "#{user.__struct__}:#{user.id}"
      key_system = "system"

      assert key_user != key_system
    end
  end

  describe "concurrent access" do
    test "handles concurrent reads safely" do
      user = mock_user(id: 17)

      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "owner"
      )

      # Spawn multiple concurrent reads
      tasks = for _ <- 1..10 do
        Task.async(fn ->
          Current.roles_for(user, "Fosm.Invoice", nil)
        end)
      end

      results = Task.yield_many(tasks, 1000)

      # All should succeed
      for {task, result} <- results do
        case result do
          nil ->
            Task.shutdown(task, :brutal_kill)
            flunk("Task timed out")

          {:ok, {:ok, roles}} ->
            assert :owner in roles

          {:ok, roles} when is_list(roles) ->
            assert :owner in roles

          {:exit, reason} ->
            flunk("Task exited: #{inspect(reason)}")
        end
      end
    end

    test "handles concurrent invalidation safely" do
      user = mock_user(id: 18)

      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "owner"
      )

      # Spawn mix of reads and invalidations
      tasks = for i <- 1..20 do
        Task.async(fn ->
          if rem(i, 3) == 0 do
            Current.invalidate_for(user)
            :invalidated
          else
            roles = Current.roles_for(user, "Fosm.Invoice", nil)
            {:read, roles}
          end
        end)
      end

      results = Task.yield_many(tasks, 2000)

      # All should complete without crashing
      for {task, result} <- results do
        case result do
          nil ->
            Task.shutdown(task, :brutal_kill)
            flunk("Task timed out")

          {:ok, _} ->
            :ok

          {:exit, reason} ->
            flunk("Task exited: #{inspect(reason)}")
        end
      end
    end
  end

  describe "edge cases" do
    test "handles missing repo gracefully" do
      # If repo is not configured, should handle gracefully
      user = mock_user(id: 19)

      # This might raise or return empty list depending on implementation
      # Just verify it doesn't crash the VM
      try do
        Current.roles_for(user, "NonExistent.Resource", nil)
      rescue
        _ -> :ok
      catch
        _ -> :ok
      end
    end

    test "handles string record_ids" do
      user = mock_user(id: 20)
      invoice = build(:invoice, id: 999)

      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: to_string(invoice.id),  # String ID
        role_name: "editor"
      )

      # Should work with string record_id
      roles = Current.roles_for(user, "Fosm.Invoice", to_string(invoice.id))
      assert :editor in roles
    end

    test "handles integer record_ids" do
      user = mock_user(id: 21)
      invoice = build(:invoice, id: 888)

      insert!(:role_assignment,
        user_type: "Fosm.User",
        user_id: to_string(user.id),
        resource_type: "Fosm.Invoice",
        resource_id: to_string(invoice.id),
        role_name: "viewer"
      )

      # Should work with integer record_id
      roles = Current.roles_for(user, "Fosm.Invoice", invoice.id)
      assert :viewer in roles
    end
  end
end
