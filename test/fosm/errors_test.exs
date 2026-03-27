defmodule Fosm.ErrorsTest do
  @moduledoc """
  Tests for FOSM error types.

  Litmus test: Verifies all error modules raise correctly and produce
  meaningful messages.
  """
  use Fosm.DataCase, async: true

  alias Fosm.Errors

  describe "Fosm.Errors" do
    test "raises with custom message" do
      error = Errors.exception(message: "Something went wrong")
      assert Exception.message(error) == "Something went wrong"
    end
  end

  describe "Fosm.Errors.UnknownEvent" do
    test "raises with event and module info" do
      error = %Errors.UnknownEvent{event: :invalid, module: Fosm.Invoice}
      message = Exception.message(error)

      assert message =~ "invalid"
      assert message =~ "Fosm.Invoice"
    end

    test "can be raised" do
      assert_raise Errors.UnknownEvent, ~r/invalid/, fn ->
        raise Errors.UnknownEvent, event: :invalid, module: Fosm.Invoice
      end
    end
  end

  describe "Fosm.Errors.UnknownState" do
    test "raises with state and module info" do
      error = %Errors.UnknownState{state: :archived, module: Fosm.Invoice}
      message = Exception.message(error)

      assert message =~ "archived"
      assert message =~ "Fosm.Invoice"
    end

    test "can be raised" do
      assert_raise Errors.UnknownState, ~r/archived/, fn ->
        raise Errors.UnknownState, state: :archived, module: Fosm.Invoice
      end
    end
  end

  describe "Fosm.Errors.InvalidTransition" do
    test "raises with event and from state" do
      error = %Errors.InvalidTransition{
        event: :pay,
        from: "draft",
        module: Fosm.Invoice
      }
      message = Exception.message(error)

      assert message =~ "pay"
      assert message =~ "draft"
      assert message =~ "Fosm.Invoice"
    end

    test "can be raised" do
      assert_raise Errors.InvalidTransition, ~r/pay.*draft/, fn ->
        raise Errors.InvalidTransition,
          event: :pay,
          from: "draft",
          module: Fosm.Invoice
      end
    end
  end

  describe "Fosm.Errors.GuardFailed" do
    test "raises with guard name and event" do
      error = %Errors.GuardFailed{
        guard: :has_line_items,
        event: :send,
        reason: nil,
        module: Fosm.Invoice
      }
      message = Exception.message(error)

      assert message =~ "has_line_items"
      assert message =~ "send"
      assert message =~ "Fosm.Invoice"
    end

    test "includes reason when provided" do
      error = %Errors.GuardFailed{
        guard: :valid_amount,
        event: :pay,
        reason: "Amount must be positive",
        module: Fosm.Invoice
      }
      message = Exception.message(error)

      assert message =~ "Amount must be positive"
    end

    test "works without reason" do
      error = %Errors.GuardFailed{
        guard: :is_owner,
        event: :cancel,
        reason: nil,
        module: Fosm.Invoice
      }
      message = Exception.message(error)

      assert message =~ "is_owner"
      refute message =~ "nil"
    end

    test "can be raised" do
      assert_raise Errors.GuardFailed, ~r/has_line_items/, fn ->
        raise Errors.GuardFailed,
          guard: :has_line_items,
          event: :send,
          reason: "Invoice has no line items",
          module: Fosm.Invoice
      end
    end
  end

  describe "Fosm.Errors.TerminalState" do
    test "raises with state name" do
      error = %Errors.TerminalState{
        state: "completed",
        module: Fosm.Workflow
      }
      message = Exception.message(error)

      assert message =~ "completed"
      assert message =~ "terminal"
      assert message =~ "Fosm.Workflow"
    end

    test "can be raised" do
      assert_raise Errors.TerminalState, ~r/completed.*terminal/, fn ->
        raise Errors.TerminalState,
          state: "completed",
          module: Fosm.Workflow
      end
    end
  end

  describe "Fosm.Errors.AccessDenied" do
    test "raises with action and actor info" do
      user = mock_user(email: "test@example.com")

      error = %Errors.AccessDenied{
        action: :delete,
        actor: user,
        resource: %{id: 1, __struct__: Fosm.Invoice},
        module: Fosm.Invoice
      }
      message = Exception.message(error)

      assert message =~ "delete"
      assert message =~ "test@example.com"
      assert message =~ "Fosm.Invoice"
    end

    test "handles nil actor (anonymous)" do
      error = %Errors.AccessDenied{
        action: :read,
        actor: nil,
        resource: %{id: 1},
        module: Fosm.Invoice
      }
      message = Exception.message(error)

      assert message =~ "anonymous"
      assert message =~ "read"
    end

    test "handles symbol actors (system/agent)" don      error = %Errors.AccessDenied{
        action: :modify,
        actor: :system,
        resource: %{id: 1},
        module: Fosm.Invoice
      }
      message = Exception.message(error)

      assert message =~ "modify"
    end

    test "can be raised" do
      user = mock_user()

      assert_raise Errors.AccessDenied, ~r/access denied/i, fn ->
        raise Errors.AccessDenied,
          action: :delete,
          actor: user,
          resource: %{id: 1, __struct__: Fosm.Invoice},
          module: Fosm.Invoice
      end
    end
  end

  # ============================================================================
  # Error Helper Functions
  # ============================================================================

  defp mock_user(opts \\ []) do
    id = Keyword.get(opts, :id, System.unique_integer([:positive]))
    email = Keyword.get(opts, :email, "user#{id}@example.com")

    %{
      id: id,
      __struct__: Fosm.User,
      email: email,
      superadmin: false
    }
  end
end
