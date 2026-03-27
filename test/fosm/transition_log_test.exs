defmodule Fosm.TransitionLogTest do
  @moduledoc """
  Tests for the TransitionLog schema.
  """
  use ExUnit.Case, async: true
  alias Fosm.TransitionLog

  describe "changeset/2" do
    test "validates required fields" do
      changeset = TransitionLog.changeset(%TransitionLog{}, %{})
      
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).record_type
      assert "can't be blank" in errors_on(changeset).record_id
      assert "can't be blank" in errors_on(changeset).event_name
      assert "can't be blank" in errors_on(changeset).from_state
      assert "can't be blank" in errors_on(changeset).to_state
    end

    test "valid changeset with all required fields" do
      attrs = %{
        record_type: "Fosm.Invoice",
        record_id: "123",
        event_name: "pay",
        from_state: "sent",
        to_state: "paid"
      }
      
      changeset = TransitionLog.changeset(%TransitionLog{}, attrs)
      assert changeset.valid?
    end

    test "validates field lengths" do
      attrs = %{
        record_type: String.duplicate("a", 256),
        record_id: "123",
        event_name: "pay",
        from_state: "sent",
        to_state: "paid"
      }
      
      changeset = TransitionLog.changeset(%TransitionLog{}, attrs)
      assert changeset.valid? == false
      assert "should be at most 255 character(s)" in errors_on(changeset).record_type
    end

    test "accepts optional fields" do
      attrs = %{
        record_type: "Fosm.Invoice",
        record_id: "123",
        event_name: "pay",
        from_state: "sent",
        to_state: "paid",
        actor_type: "User",
        actor_id: "42",
        actor_label: "john@example.com",
        metadata: %{"ip_address" => "192.168.1.1"},
        state_snapshot: %{"amount" => 100.00},
        snapshot_reason: "count",
        triggered_by: %{"record_type" => "Fosm.Contract", "record_id" => "456"}
      }
      
      changeset = TransitionLog.changeset(%TransitionLog{}, attrs)
      assert changeset.valid?
      
      # Verify all optional fields are cast
      assert get_change(changeset, :actor_type) == "User"
      assert get_change(changeset, :actor_id) == "42"
      assert get_change(changeset, :metadata) == %{"ip_address" => "192.168.1.1"}
    end
  end

  describe "query scopes" do
    test "for_record/3 filters by record type and id" do
      query = TransitionLog.for_record("Fosm.Invoice", 123)
      
      assert inspect(query) =~ "record_type == \"Fosm.Invoice\""
      assert inspect(query) =~ "record_id == \"123\""
    end

    test "by_event/2 filters by event name" do
      query = TransitionLog.by_event("pay")
      
      assert inspect(query) =~ "event_name == \"pay\""
    end

    test "by_actor/3 filters by actor type and id" do
      query = TransitionLog.by_actor("User", 42)
      
      assert inspect(query) =~ "actor_type == \"User\""
      assert inspect(query) =~ "actor_id == \"42\""
    end

    test "with_snapshot/1 filters entries with snapshots" do
      query = TransitionLog.with_snapshot()
      
      assert inspect(query) =~ "not(is_nil(state_snapshot))"
    end

    test "without_snapshot/1 filters entries without snapshots" do
      query = TransitionLog.without_snapshot()
      
      assert inspect(query) =~ "is_nil(state_snapshot)"
    end

    test "by_snapshot_reason/2 filters by snapshot reason" do
      query = TransitionLog.by_snapshot_reason("terminal")
      
      assert inspect(query) =~ "snapshot_reason == \"terminal\""
    end

    test "recent/1 orders by inserted_at desc" do
      query = TransitionLog.recent()
      
      assert inspect(query) =~ "order_by: \"inserted_at\""
    end

    test "chronological/1 orders by inserted_at asc" do
      query = TransitionLog.chronological()
      
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

  defp get_change(changeset, field) do
    Ecto.Changeset.get_change(changeset, field)
  end
end
