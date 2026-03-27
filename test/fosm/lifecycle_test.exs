defmodule Fosm.LifecycleTest do
  @moduledoc """
  Tests for the FOSM Lifecycle DSL macros.

  Verifies that:
  - State predicates are generated (draft?, sent?, etc.)
  - Event methods are generated (send!, can_send?, etc.)
  - Guards compile and evaluate correctly
  - Side effects compile and run correctly
  """
  use Fosm.DataCase, async: true

  alias Fosm.Lifecycle

  # ============================================================================
  # Test Module with Full Lifecycle
  # ============================================================================

  defmodule TestInvoice do
    use Ecto.Schema
    use Fosm.Lifecycle

    schema "test_invoices" do
      field :number, :string
      field :amount, :decimal
      field :state, :string, default: "draft"
      timestamps()
    end

    lifecycle do
      state :draft, initial: true
      state :sent
      state :paid, terminal: true
      state :cancelled, terminal: true

      event :send_invoice, from: :draft, to: :sent
      event :pay, from: :sent, to: :paid
      event :cancel, from: [:draft, :sent], to: :cancelled

      guard :has_positive_amount, on: :send_invoice do
        # Guard implementation returns :ok or {:error, reason}
        :ok
      end

      side_effect :notify_customer, on: :send_invoice do
        # Side effect implementation
        :ok
      end

      access do
        role :owner, default: true do
          can :crud
          can :send_invoice, :cancel
        end

        role :accountant do
          can :read
          can :pay
        end
      end

      snapshot :manual
      snapshot_attributes [:number, :amount]
    end
  end

  # ============================================================================
  # State Predicate Tests
  # ============================================================================

  describe "state predicates" do
    test "generates draft?/1 predicate" do
      record = %{state: "draft"}
      assert TestInvoice.draft?(record)
      refute TestInvoice.sent?(record)
      refute TestInvoice.paid?(record)
    end

    test "generates sent?/1 predicate" do
      record = %{state: "sent"}
      assert TestInvoice.sent?(record)
      refute TestInvoice.draft?(record)
      refute TestInvoice.paid?(record)
    end

    test "generates paid?/1 predicate" do
      record = %{state: "paid"}
      assert TestInvoice.paid?(record)
      refute TestInvoice.draft?(record)
      refute TestInvoice.sent?(record)
    end

    test "generates cancelled?/1 predicate" do
      record = %{state: "cancelled"}
      assert TestInvoice.cancelled?(record)
      refute TestInvoice.draft?(record)
    end
  end

  # ============================================================================
  # Event Method Tests
  # ============================================================================

  describe "event methods" do
    test "generates send_invoice!/2 function" do
      assert is_function(&TestInvoice.send_invoice!/2, 2)
    end

    test "generates pay!/2 function" do
      assert is_function(&TestInvoice.pay!/2, 2)
    end

    test "generates cancel!/2 function" do
      assert is_function(&TestInvoice.cancel!/2, 2)
    end

    test "generates can_send_invoice?/1 function" do
      assert is_function(&TestInvoice.can_send_invoice?/1, 1)
    end

    test "generates can_pay?/1 function" do
      assert is_function(&TestInvoice.can_pay?/1, 1)
    end

    test "generates can_cancel?/1 function" do
      assert is_function(&TestInvoice.can_cancel?/1, 1)
    end
  end

  # ============================================================================
  # Guard Evaluation Tests
  # ============================================================================

  describe "guard evaluation" do
    test "guards can return :ok to allow transition" do
      # The guard :has_positive_amount returns :ok in our test module
      record = insert!(:test_invoice, state: "draft", amount: Decimal.new("100.00"))
      
      # Can fire should check guards
      result = TestInvoice.can_send_invoice?(record)
      assert result == true
    end

    test "guards can return {:error, reason} to block transition" do
      # Create a module with a failing guard for testing
      defmodule TestInvoiceWithFailingGuard do
        use Ecto.Schema
        use Fosm.Lifecycle

        schema "test_invoices_failing" do
          field :amount, :decimal
          field :state, :string, default: "draft"
        end

        lifecycle do
          state :draft, initial: true
          state :sent

          event :send, from: :draft, to: :sent

          guard :must_have_amount, on: :send do
            fn record ->
              if record.amount && Decimal.compare(record.amount, Decimal.new("0")) == :gt do
                :ok
              else
                {:error, "Amount must be positive"}
              end
            end
          end
        end
      end

      # Should block when amount is nil
      record_with_nil = %{state: "draft", amount: nil}
      refute TestInvoiceWithFailingGuard.can_send?(record_with_nil)
    end

    test "guards can return boolean values" do
      # Guards that return true/false should work
      defmodule TestInvoiceWithBoolGuard do
        use Ecto.Schema
        use Fosm.Lifecycle

        schema "test_invoices_bool" do
          field :confirmed, :boolean
          field :state, :string, default: "draft"
        end

        lifecycle do
          state :draft, initial: true
          state :sent

          event :send, from: :draft, to: :sent

          guard :must_be_confirmed, on: :send do
            fn record ->
              record.confirmed == true
            end
          end
        end
      end

      confirmed_record = %{state: "draft", confirmed: true}
      unconfirmed_record = %{state: "draft", confirmed: false}

      assert TestInvoiceWithBoolGuard.can_send?(confirmed_record)
      refute TestInvoiceWithBoolGuard.can_send?(unconfirmed_record)
    end
  end

  # ============================================================================
  # Side Effect Tests
  # ============================================================================

  describe "side effects" do
    test "side effects are defined in lifecycle" do
      lifecycle = TestInvoice.fosm_lifecycle()
      
      # Find the send_invoice event
      send_event = Enum.find(lifecycle.events, &(&1.name == :send_invoice))
      assert send_event != nil
      
      # Should have side effects
      assert length(send_event.side_effects) >= 1
    end

    test "deferred side effects compile correctly" do
      defmodule TestInvoiceWithDeferredEffect do
        use Ecto.Schema
        use Fosm.Lifecycle

        schema "test_invoices_deferred" do
          field :state, :string, default: "draft"
        end

        lifecycle do
          state :draft, initial: true
          state :sent

          event :send, from: :draft, to: :sent

          side_effect :async_notification, on: :send, defer: true do
            fn _record, _transition ->
              # This would run after transaction commits
              :ok
            end
          end
        end
      end

      lifecycle = TestInvoiceWithDeferredEffect.fosm_lifecycle()
      send_event = Enum.find(lifecycle.events, &(&1.name == :send))
      
      effect = Enum.find(send_event.side_effects, &(&1.name == :async_notification))
      assert effect != nil
      assert effect.defer == true
    end
  end

  # ============================================================================
  # Access Control Tests
  # ============================================================================

  describe "access control" do
    test "roles are defined in lifecycle" do
      lifecycle = TestInvoice.fosm_lifecycle()
      
      assert lifecycle.access != nil
      assert length(lifecycle.access.roles) == 2
      
      owner_role = Enum.find(lifecycle.access.roles, &(&1.name == :owner))
      assert owner_role != nil
      assert owner_role.default == true
    end

    test "roles have CRUD permissions" do
      lifecycle = TestInvoice.fosm_lifecycle()
      owner_role = Enum.find(lifecycle.access.roles, &(&1.name == :owner))
      
      assert Fosm.Lifecycle.RoleDefinition.can_crud?(owner_role, :create)
      assert Fosm.Lifecycle.RoleDefinition.can_crud?(owner_role, :read)
      assert Fosm.Lifecycle.RoleDefinition.can_crud?(owner_role, :update)
      assert Fosm.Lifecycle.RoleDefinition.can_crud?(owner_role, :delete)
    end

    test "roles have event permissions" do
      lifecycle = TestInvoice.fosm_lifecycle()
      owner_role = Enum.find(lifecycle.access.roles, &(&1.name == :owner))
      accountant_role = Enum.find(lifecycle.access.roles, &(&1.name == :accountant))
      
      # Owner can send and cancel
      assert Fosm.Lifecycle.RoleDefinition.can_event?(owner_role, :send_invoice)
      assert Fosm.Lifecycle.RoleDefinition.can_event?(owner_role, :cancel)
      
      # Accountant can pay
      assert Fosm.Lifecycle.RoleDefinition.can_event?(accountant_role, :pay)
    end
  end

  # ============================================================================
  // Snapshot Configuration Tests
  // ============================================================================

  describe "snapshot configuration" do
    test "snapshot strategy is configured" do
      lifecycle = TestInvoice.fosm_lifecycle()
      
      assert lifecycle.snapshot != nil
      assert lifecycle.snapshot.strategy == :manual
    end

    test "snapshot attributes are defined" do
      lifecycle = TestInvoice.fosm_lifecycle()
      
      assert lifecycle.snapshot.attributes == [:number, :amount]
    end
  end

  # ============================================================================
  // Lifecycle Introspection Tests
  // ============================================================================

  describe "lifecycle introspection" do
    test "fosm_lifecycle/0 returns definition" do
      lifecycle = TestInvoice.fosm_lifecycle()
      
      assert is_struct(lifecycle)
      assert length(lifecycle.states) == 4
      assert length(lifecycle.events) == 3
    end

    test "available_events/1 returns valid events for state" do
      draft_record = %{state: "draft"}
      events = TestInvoice.available_events(draft_record)
      
      assert :send_invoice in events
      assert :cancel in events
      refute :pay in events
    end

    test "why_cannot_fire?/2 provides diagnostics" do
      paid_record = %{state: "paid"}
      result = TestInvoice.why_cannot_fire?(paid_record, :send_invoice)
      
      assert result.can_fire == false
      assert result.reason =~ "terminal" or result.reason =~ "state"
    end
  end
end
