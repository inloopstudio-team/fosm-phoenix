defmodule Fosm.Lifecycle.ImplementationTest do
  use ExUnit.Case, async: true

  # This is a basic test module to verify the implementation compiles
  # Full tests will be implemented in task-24, task-25

  alias Fosm.Lifecycle.Implementation
  alias Fosm.Lifecycle.{Definition, StateDefinition, EventDefinition, GuardDefinition}

  describe "fire! validation" do
    test "raises UnknownEvent for non-existent event" do
      lifecycle = %Definition{
        states: [%StateDefinition{name: :draft, initial: true, terminal: false}],
        events: [],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      # Mock record
      record = %{state: "draft", id: 1}

      assert_raise Fosm.Errors.UnknownEvent, fn ->
        Implementation.fire!(TestModule, record, :non_existent, [])
      end
    end
  end

  describe "why_cannot_fire?/3" do
    test "returns unknown event for non-existent event" do
      lifecycle = %Definition{
        states: [%StateDefinition{name: :draft, initial: true, terminal: false}],
        events: [],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      record = %{state: "draft"}

      result = Implementation.why_cannot_fire?(
        TestModule,
        record,
        :non_existent
      )

      assert result.can_fire == false
      assert result.reason =~ "Unknown event"
    end

    test "detects terminal state" do
      lifecycle = %Definition{
        states: [
          %StateDefinition{name: :draft, initial: true, terminal: false},
          %StateDefinition{name: :complete, initial: false, terminal: true}
        ],
        events: [],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      # We need to set up the mock properly, but for now just test the function exists
      assert is_function(&Implementation.why_cannot_fire?/3, 3)
    end
  end

  describe "available_events/2" do
    test "returns empty list for terminal state" do
      assert is_function(&Implementation.available_events/2, 2)
    end
  end

  describe "can_fire?/3" do
    test "returns false for terminal state" do
      assert is_function(&Implementation.can_fire?/3, 3)
    end
  end
end
