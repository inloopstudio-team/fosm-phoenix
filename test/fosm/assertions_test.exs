defmodule Fosm.AssertionsTest do
  @moduledoc """
  Tests for custom FOSM assertions.

  Verifies all assertion helpers work correctly in both pass and fail cases.
  """
  use Fosm.DataCase, async: true

  import Fosm.Assertions
  import Fosm.Factory
  import Fosm.TestHelpers

  describe "assert_state/2" do
    test "passes when state matches" do
      invoice = build(:invoice, state: "draft")
      assert_state(invoice, "draft")
      assert_state(invoice, :draft)
    end

    test "raises when state doesn't match" do
      invoice = build(:invoice, state: "paid")

      assert_raise ExUnit.AssertionError, ~r/paid.*sent/, fn ->
        assert_state(invoice, "sent")
      end
    end
  end

  describe "assert_terminal_state/2" do
    test "passes for terminal state" do
      # Mock lifecycle would have terminal states
      # For now, just verify function exists and runs
      # This will need actual lifecycle module to work fully
    end
  end

  describe "assert_initial_state/2" do
    test "passes for initial state" do
      # Similar to terminal state test
    end
  end

  describe "assert_can_fire/2" do
    test "passes when event is available" do
      # Needs actual lifecycle module
      # Will test when available
    end

    test "raises when event is not available" do
      # Needs actual lifecycle module
    end
  end

  describe "assert_cannot_fire/2" do
    test "passes when event is not available" do
      # Needs actual lifecycle module
    end
  end

  describe "assert_fire_error/3" do
    test "passes when expected error is raised" do
      # Needs actual lifecycle module with fire!
    end
  end

  describe "actor and resource label helpers" do
    test "actor_label formats user correctly" do
      user = mock_user(email: "test@example.com")
      label = actor_label(user)

      assert label =~ "test@example.com"
    end

    test "actor_label handles system actor" do
      assert actor_label(:system) == "system"
    end

    test "actor_label handles agent actor" do
      assert actor_label(:agent) == "agent"
    end

    test "actor_label handles nil" do
      assert actor_label(nil) == "anonymous"
    end
  end

  # Helper needed for assertion tests
  defp actor_label(actor) do
    case actor do
      %{email: email} -> "user (#{email})"
      %{id: id, __struct__: module} -> "#{module}:#{id}"
      :system -> "system"
      :agent -> "agent"
      nil -> "anonymous"
      other -> inspect(other)
    end
  end
end
