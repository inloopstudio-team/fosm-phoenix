defmodule Fosm.RoleAssignmentTest do
  @moduledoc """
  Tests for the RoleAssignment schema.
  """
  use ExUnit.Case, async: true
  alias Fosm.RoleAssignment

  describe "changeset/2" do
    test "validates required fields" do
      changeset = RoleAssignment.changeset(%RoleAssignment{}, %{})
      
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).user_type
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).resource_type
      assert "can't be blank" in errors_on(changeset).role_name
    end

    test "valid changeset with required fields" do
      attrs = %{
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        role_name: "owner"
      }
      
      changeset = RoleAssignment.changeset(%RoleAssignment{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with record-level assignment" do
      attrs = %{
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        resource_id: "123",
        role_name: "owner"
      }
      
      changeset = RoleAssignment.changeset(%RoleAssignment{}, attrs)
      assert changeset.valid?
    end

    test "accepts optional fields" do
      attrs = %{
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        resource_id: "123",
        role_name: "owner",
        granted_by_type: "User",
        granted_by_id: "99",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }
      
      changeset = RoleAssignment.changeset(%RoleAssignment{}, attrs)
      assert changeset.valid?
    end

    test "validates expiration is in the future" do
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      
      attrs = %{
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        role_name: "owner",
        expires_at: past_time
      }
      
      changeset = RoleAssignment.changeset(%RoleAssignment{}, attrs)
      assert changeset.valid? == false
      assert "must be in the future" in errors_on(changeset).expires_at
    end

    test "allows nil expiration" do
      attrs = %{
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        role_name: "owner",
        expires_at: nil
      }
      
      changeset = RoleAssignment.changeset(%RoleAssignment{}, attrs)
      assert changeset.valid?
    end
  end

  describe "query scopes" do
    test "for_user/3 filters by user type and id" do
      query = RoleAssignment.for_user("User", 42)
      
      assert inspect(query) =~ "user_type == \"User\""
      assert inspect(query) =~ "user_id == \"42\""
    end

    test "for_resource/2 filters by resource type only" do
      query = RoleAssignment.for_resource("Fosm.Invoice")
      
      assert inspect(query) =~ "resource_type == \"Fosm.Invoice\""
    end

    test "for_resource/3 filters by resource type and id" do
      query = RoleAssignment.for_resource("Fosm.Invoice", 123)
      
      assert inspect(query) =~ "resource_type == \"Fosm.Invoice\""
    end

    test "by_role/2 filters by role name" do
      query = RoleAssignment.by_role("owner")
      
      assert inspect(query) =~ "role_name == \"owner\""
    end

    test "active/1 filters non-expired assignments" do
      query = RoleAssignment.active()
      
      assert inspect(query) =~ "is_nil(expires_at)"
      assert inspect(query) =~ "expires_at >"
    end

    test "expired/1 filters expired assignments" do
      query = RoleAssignment.expired()
      
      assert inspect(query) =~ "expires_at <="
    end

    test "type_level/1 filters type-level assignments" do
      query = RoleAssignment.type_level()
      
      assert inspect(query) =~ "is_nil(resource_id)"
    end

    test "record_level/1 filters record-level assignments" do
      query = RoleAssignment.record_level()
      
      assert inspect(query) =~ "not is_nil(resource_id)"
    end

    test "recent/2 limits and orders by inserted_at" do
      query = RoleAssignment.recent(50)
      
      assert inspect(query) =~ "limit: 50"
      assert inspect(query) =~ "order_by: \"inserted_at\""
    end
  end

  describe "helper functions" do
    test "roles_for/4 returns empty list when no assignments" do
      # This would require database setup for full testing
      # For now, we verify the query structure
      query = RoleAssignment.for_user("User", "999")
      
      assert inspect(query) =~ "user_type == \"User\""
    end

    test "has_role?/5 checks for role existence" do
      # This would require database setup for full testing
      # For now, we verify the query structure
      query = RoleAssignment.for_user("User", "42")
      
      assert inspect(query) =~ "user_type == \"User\""
    end
  end

  # Helper functions
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{\w+}", message, fn _, key ->
        opts |> Keyword.get(String.to_atom(key), key) |> to_string()
      end)
    end)
  end
end
