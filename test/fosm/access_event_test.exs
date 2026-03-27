defmodule Fosm.AccessEventTest do
  @moduledoc """
  Tests for the AccessEvent schema.
  """
  use ExUnit.Case, async: true
  alias Fosm.AccessEvent

  describe "changeset/2" do
    test "validates required fields" do
      changeset = AccessEvent.changeset(%AccessEvent{}, %{})
      
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).action
      assert "can't be blank" in errors_on(changeset).user_type
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).resource_type
      assert "can't be blank" in errors_on(changeset).result
    end

    test "valid changeset with required fields" do
      attrs = %{
        action: "check",
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        result: "allowed"
      }
      
      changeset = AccessEvent.changeset(%AccessEvent{}, attrs)
      assert changeset.valid?
    end

    test "validates action inclusion" do
      attrs = %{
        action: "invalid_action",
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        result: "allowed"
      }
      
      changeset = AccessEvent.changeset(%AccessEvent{}, attrs)
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).action
    end

    test "validates result inclusion" do
      attrs = %{
        action: "check",
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        result: "invalid_result"
      }
      
      changeset = AccessEvent.changeset(%AccessEvent{}, attrs)
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).result
    end

    test "accepts valid actions" do
      valid_actions = ["grant", "revoke", "check", "deny"]
      
      for action <- valid_actions do
        attrs = %{
          action: action,
          user_type: "User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          result: "allowed"
        }
        
        changeset = AccessEvent.changeset(%AccessEvent{}, attrs)
        assert changeset.valid?, "Expected #{action} to be valid"
      end
    end

    test "accepts optional fields" do
      attrs = %{
        action: "check",
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        resource_id: "123",
        role_name: "owner",
        event_name: "pay",
        result: "allowed",
        reason: "User has owner role",
        metadata: %{"ip_address" => "192.168.1.1"}
      }
      
      changeset = AccessEvent.changeset(%AccessEvent{}, attrs)
      assert changeset.valid?
    end
  end

  describe "query scopes" do
    test "for_user/3 filters by user type and id" do
      query = AccessEvent.for_user("User", 42)
      
      assert inspect(query) =~ "user_type == \"User\""
      assert inspect(query) =~ "user_id == \"42\""
    end

    test "for_resource/2 filters by resource type" do
      query = AccessEvent.for_resource("Fosm.Invoice")
      
      assert inspect(query) =~ "resource_type == \"Fosm.Invoice\""
    end

    test "for_resource/3 filters by resource type and id" do
      query = AccessEvent.for_resource("Fosm.Invoice", 123)
      
      assert inspect(query) =~ "resource_type == \"Fosm.Invoice\""
      assert inspect(query) =~ "resource_id == \"123\""
    end

    test "by_action/2 filters by action" do
      query = AccessEvent.by_action("grant")
      
      assert inspect(query) =~ "action == \"grant\""
    end

    test "by_result/2 filters by result" do
      query = AccessEvent.by_result("denied")
      
      assert inspect(query) =~ "result == \"denied\""
    end

    test "by_role/2 filters by role name" do
      query = AccessEvent.by_role("owner")
      
      assert inspect(query) =~ "role_name == \"owner\""
    end

    test "recent/1 orders by inserted_at desc" do
      query = AccessEvent.recent()
      
      assert inspect(query) =~ "order_by: \"inserted_at\""
    end

    test "chronological/1 orders by inserted_at asc" do
      query = AccessEvent.chronological()
      
      assert inspect(query) =~ "order_by: \"inserted_at\""
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
