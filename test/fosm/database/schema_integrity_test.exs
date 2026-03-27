defmodule Fosm.Database.SchemaIntegrityTest do
  @moduledoc """
  Tests that all Ecto schemas work correctly with database operations.

  Covers:
  - All schemas can insert records
  - All schemas can query records
  - All data types work correctly (binary_id, map/json, decimal, datetime)
  - Associations work if defined
  - Changeset validations are enforced
  """

  use Fosm.DataCase, async: true

  alias Fosm.{
    TransitionLog,
    AccessEvent,
    RoleAssignment,
    WebhookSubscription,
    Invoice
  }

  alias Ecto.Adapters.SQL

  describe "TransitionLog schema integrity" do
    test "can insert a transition log with all data types" do
      log =
        TransitionLog.create!(%{
          record_type: "invoices",
          record_id: "123",
          event_name: "pay",
          from_state: "draft",
          to_state: "paid",
          actor_type: "Fosm.User",
          actor_id: "42",
          actor_label: "test_user",
          metadata: %{"ip" => "127.0.0.1", "user_agent" => "test"},
          state_snapshot: %{"id" => 123, "state" => "paid"},
          snapshot_reason: "transition"
        })

      assert log.id != nil
      assert log.record_type == "invoices"
      assert log.metadata == %{"ip" => "127.0.0.1", "user_agent" => "test"}
      assert log.state_snapshot["state"] == "paid"
    end

    test "can query transition logs by record" do
      # Insert multiple logs
      TransitionLog.create!(%{
        record_type: "invoices",
        record_id: "100",
        event_name: "send",
        from_state: "draft",
        to_state: "sent"
      })

      TransitionLog.create!(%{
        record_type: "invoices",
        record_id: "101",
        event_name: "pay",
        from_state: "draft",
        to_state: "paid"
      })

      # Query for specific record
      logs =
        TransitionLog
        |> TransitionLog.for_record("invoices", "100")
        |> Fosm.Repo.all()

      assert length(logs) == 1
      assert hd(logs).record_id == "100"
    end

    test "map/json data type stores and retrieves correctly" do
      complex_metadata = %{
        "nested" => %{"key" => "value"},
        "array" => [1, 2, 3],
        "bool" => true,
        "null" => nil
      }

      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b",
          metadata: complex_metadata
        })

      # Reload from database
      reloaded = Fosm.Repo.get!(TransitionLog, log.id)
      assert reloaded.metadata["nested"]["key"] == "value"
      assert reloaded.metadata["array"] == [1, 2, 3]
      assert reloaded.metadata["bool"] == true
    end

    test "binary_id is auto-generated" do
      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })

      assert log.id != nil
      # UUID can be 16 bytes (binary) or 36 chars (string representation)
      uuid_size = byte_size(log.id)
      assert uuid_size in [16, 36], "UUID should be 16 bytes or 36 chars, got: #{uuid_size}"
    end

    test "timestamps use utc_datetime without updated_at" do
      log =
        TransitionLog.create!(%{
          record_type: "test",
          record_id: "1",
          event_name: "test",
          from_state: "a",
          to_state: "b"
        })

      assert %DateTime{} = log.inserted_at
      assert log.inserted_at.time_zone == "Etc/UTC"
    end
  end

  describe "AccessEvent schema integrity" do
    test "can insert an access event with all data types" do
      event =
        AccessEvent.create!(%{
          action: "grant",
          user_type: "Fosm.User",
          user_id: "42",
          user_label: "test@example.com",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner",
          performed_by_type: "Fosm.User",
          performed_by_id: "1",
          metadata: %{"source" => "admin_panel"},
          result: "allowed"
        })

      assert event.id != nil
      assert event.action == "grant"
      assert event.result == "allowed"
    end

    test "validates action inclusion" do
      changeset =
        AccessEvent.changeset(%AccessEvent{}, %{
          action: "invalid_action",
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          role_name: "owner",
          result: "allowed"
        })

      assert {:action, ["is invalid"]} in errors_on(changeset)
    end

    test "valid actions are accepted" do
      valid_actions = ["grant", "revoke", "auto_grant", "auto_revoke"]

      for action <- valid_actions do
        changeset =
          AccessEvent.changeset(%AccessEvent{}, %{
            action: action,
            user_type: "Fosm.User",
            user_id: "42",
            resource_type: "Fosm.Invoice",
            role_name: "owner",
            result: "allowed"
          })

        assert changeset.valid?
      end
    end

    test "query scopes work correctly" do
      # Create test events
      AccessEvent.create!(%{
        action: "grant",
        user_type: "Fosm.User",
        user_id: "user_1",
        resource_type: "Fosm.Invoice",
        role_name: "owner",
        result: "allowed"
      })

      AccessEvent.create!(%{
        action: "revoke",
        user_type: "Fosm.User",
        user_id: "user_2",
        resource_type: "Fosm.Invoice",
        role_name: "viewer",
        result: "allowed"
      })

      # Test for_user scope
      user1_events =
        AccessEvent
        |> AccessEvent.for_user("Fosm.User", "user_1")
        |> Fosm.Repo.all()

      assert length(user1_events) == 1
      assert hd(user1_events).user_id == "user_1"

      # Test by_action scope
      grants =
        AccessEvent
        |> AccessEvent.by_action("grant")
        |> Fosm.Repo.all()

      assert length(grants) == 1
      assert hd(grants).action == "grant"

      # Test by_action scope for revoke
      revokes =
        AccessEvent
        |> AccessEvent.by_action("revoke")
        |> Fosm.Repo.all()

      assert length(revokes) == 1
      assert hd(revokes).action == "revoke"
    end
  end

  describe "RoleAssignment schema integrity" do
    test "can insert a role assignment" do
      assignment =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner",
          granted_by_type: "Fosm.User",
          granted_by_id: "1"
        })
        |> Fosm.Repo.insert!()

      assert assignment.id != nil
      assert assignment.user_type == "Fosm.User"
      assert assignment.role_name == "owner"
    end

    test "can create type-level role assignment (no resource_id)" do
      assignment =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: nil,
          role_name: "viewer"
        })
        |> Fosm.Repo.insert!()

      assert assignment.resource_id == nil
      assert assignment.role_name == "viewer"
    end

    test "datetime fields work correctly" do
      # Truncate to seconds for consistent comparison
      future_date = DateTime.utc_now() |> DateTime.add(86400, :second) |> DateTime.truncate(:second)

      assignment =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner",
          expires_at: future_date
        })
        |> Fosm.Repo.insert!()

      # Reload and verify - compare with truncated seconds since database may not preserve microseconds
      reloaded = Fosm.Repo.get!(RoleAssignment, assignment.id)
      assert DateTime.compare(
        DateTime.truncate(reloaded.expires_at, :second),
        future_date
      ) == :eq
    end

    test "has_role? helper works" do
      # Create assignment
      %RoleAssignment{}
      |> RoleAssignment.changeset(%{
        user_type: "Fosm.User",
        user_id: "99",
        resource_type: "Fosm.Invoice",
        resource_id: "200",
        role_name: "admin"
      })
      |> Fosm.Repo.insert!()

      assert RoleAssignment.has_role?("Fosm.User", "99", "Fosm.Invoice", "200", "admin")
      refute RoleAssignment.has_role?("Fosm.User", "99", "Fosm.Invoice", "200", "owner")
    end

    test "all_roles_for combines type and record-level roles" do
      # Type-level role
      %RoleAssignment{}
      |> RoleAssignment.changeset(%{
        user_type: "Fosm.User",
        user_id: "88",
        resource_type: "Fosm.Invoice",
        resource_id: nil,
        role_name: "viewer"
      })
      |> Fosm.Repo.insert!()

      # Record-level role
      %RoleAssignment{}
      |> RoleAssignment.changeset(%{
        user_type: "Fosm.User",
        user_id: "88",
        resource_type: "Fosm.Invoice",
        resource_id: "300",
        role_name: "editor"
      })
      |> Fosm.Repo.insert!()

      roles = RoleAssignment.all_roles_for("Fosm.User", "88", "Fosm.Invoice", "300")
      assert :viewer in roles
      assert :editor in roles
    end
  end

  describe "WebhookSubscription schema integrity" do
    test "can insert a webhook subscription" do
      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook",
          events: ["pay", "void"],
          record_type: "Fosm.Invoice",
          secret_token: "secret_token_123"
        })

      assert subscription.id != nil
      assert subscription.url == "https://example.com/webhook"
      assert subscription.events == ["pay", "void"]
      assert subscription.active == true
      assert subscription.delivery_mode == "async"
    end

    test "validates URL format" do
      changeset =
        WebhookSubscription.changeset(%WebhookSubscription{}, %{
          url: "not-a-valid-url"
        })

      assert {:url, ["must be a valid URL"]} in errors_on(changeset)
    end

    test "validates delivery_mode inclusion" do
      changeset =
        WebhookSubscription.changeset(%WebhookSubscription{}, %{
          url: "https://example.com/webhook",
          delivery_mode: "invalid"
        })

      assert {:delivery_mode, ["is invalid"]} in errors_on(changeset)
    end

    test "array data type stores and retrieves correctly" do
      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook",
          events: ["created", "updated", "deleted"]
        })

      # Reload and verify
      reloaded = Fosm.Repo.get!(WebhookSubscription, subscription.id)
      assert "created" in reloaded.events
      assert "updated" in reloaded.events
      assert "deleted" in reloaded.events
    end

    test "integer fields work correctly" do
      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook",
          retry_count: 5
        })

      reloaded = Fosm.Repo.get!(WebhookSubscription, subscription.id)
      assert reloaded.retry_count == 5
    end

    test "boolean fields work correctly" do
      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook",
          active: false
        })

      reloaded = Fosm.Repo.get!(WebhookSubscription, subscription.id)
      assert reloaded.active == false
    end

    test "matching_subscriptions query works" do
      # System-wide webhook
      WebhookSubscription.create!(%{
        url: "https://system.example.com/webhook",
        events: []
      })

      # Per-type webhook
      WebhookSubscription.create!(%{
        url: "https://type.example.com/webhook",
        events: ["pay"],
        record_type: "Fosm.Invoice"
      })

      # Per-record webhook
      WebhookSubscription.create!(%{
        url: "https://record.example.com/webhook",
        events: ["pay"],
        record_type: "Fosm.Invoice",
        record_id: "123"
      })

      matches = WebhookSubscription.matching_subscriptions("pay", "Fosm.Invoice", "123")
      assert length(matches) == 3
    end
  end

  describe "Invoice (FOSM model) schema integrity" do
    test "can insert an invoice with all data types" do
      invoice =
        %Invoice{}
        |> Invoice.changeset(%{
          number: "INV-001",
          amount: Decimal.new("100.50"),
          due_date: ~D[2024-12-31],
          fosm_metadata: %{"customer_id" => "123", "department" => "sales"}
        })
        |> Fosm.Repo.insert!()

      # Reload to get database-persisted values
      invoice = Fosm.Repo.get!(Invoice, invoice.id)

      assert invoice.id != nil
      assert invoice.state == "draft"  # Default state
      assert invoice.number == "INV-001"
      assert Decimal.equal?(invoice.amount, Decimal.new("100.50"))
      assert invoice.fosm_metadata["customer_id"] == "123"
    end

    test "decimal data type stores and retrieves correctly" do
      invoice =
        %Invoice{}
        |> Invoice.changeset(%{
          number: "INV-002",
          amount: Decimal.new("999999.99"),
          due_date: ~D[2024-12-31]
        })
        |> Fosm.Repo.insert!()

      # Reload and verify precision is maintained
      reloaded = Fosm.Repo.get!(Invoice, invoice.id)
      assert Decimal.equal?(reloaded.amount, Decimal.new("999999.99"))
    end

    test "date data type stores and retrieves correctly" do
      invoice =
        %Invoice{}
        |> Invoice.changeset(%{
          number: "INV-003",
          amount: Decimal.new("50.00"),
          due_date: ~D[2025-06-15]
        })
        |> Fosm.Repo.insert!()

      reloaded = Fosm.Repo.get!(Invoice, invoice.id)
      assert reloaded.due_date == ~D[2025-06-15]
    end

    test "map data type (fosm_metadata) stores and retrieves correctly" do
      metadata = %{
        "custom_field_1" => "value1",
        "nested" => %{"deep" => "data"},
        "tags" => ["urgent", "premium"]
      }

      invoice =
        %Invoice{}
        |> Invoice.changeset(%{
          number: "INV-004",
          amount: Decimal.new("75.00"),
          due_date: ~D[2024-12-31],
          fosm_metadata: metadata
        })
        |> Fosm.Repo.insert!()

      reloaded = Fosm.Repo.get!(Invoice, invoice.id)
      assert reloaded.fosm_metadata["custom_field_1"] == "value1"
      assert reloaded.fosm_metadata["nested"]["deep"] == "data"
    end

    test "lifecycle state predicates work" do
      draft_invoice =
        %Invoice{}
        |> Invoice.changeset(%{
          number: "INV-005",
          amount: Decimal.new("100.00"),
          due_date: ~D[2024-12-31]
        })
        |> Fosm.Repo.insert!()

      assert Invoice.draft?(draft_invoice)
      refute Invoice.paid?(draft_invoice)
    end

    test "query helpers work" do
      # Insert invoices in different states using direct Repo insert
      draft =
        %Invoice{}
        |> Invoice.changeset(%{number: "D-001", amount: Decimal.new("100"), due_date: ~D[2024-12-31], state: "draft"})
        |> Fosm.Repo.insert!()

      paid =
        %Invoice{}
        |> Invoice.changeset(%{number: "P-001", amount: Decimal.new("200"), due_date: ~D[2024-12-31], state: "paid"})
        |> Fosm.Repo.insert!()

      void =
        %Invoice{}
        |> Invoice.changeset(%{number: "V-001", amount: Decimal.new("300"), due_date: ~D[2024-12-31], state: "void"})
        |> Fosm.Repo.insert!()

      # Test with_state scope
      drafts = Invoice |> Invoice.with_state("draft") |> Fosm.Repo.all()
      draft_ids = Enum.map(drafts, & &1.id)
      assert draft.id in draft_ids, "Expected draft invoice #{draft.id} to be in drafts list: #{inspect(draft_ids)}"

      # Test terminal_states scope
      terminal = Invoice |> Invoice.terminal_states() |> Fosm.Repo.all()
      terminal_ids = Enum.map(terminal, & &1.id)
      assert paid.id in terminal_ids, "Expected paid invoice to be in terminal list"
      assert void.id in terminal_ids, "Expected void invoice to be in terminal list"
    end
  end

  describe "changeset validations" do
    test "TransitionLog validates required fields" do
      changeset = TransitionLog.changeset(%TransitionLog{}, %{})

      refute changeset.valid?
      assert {:record_type, ["can't be blank"]} in errors_on(changeset)
      assert {:record_id, ["can't be blank"]} in errors_on(changeset)
      assert {:event_name, ["can't be blank"]} in errors_on(changeset)
      assert {:from_state, ["can't be blank"]} in errors_on(changeset)
      assert {:to_state, ["can't be blank"]} in errors_on(changeset)
    end

    test "AccessEvent validates required fields" do
      changeset = AccessEvent.changeset(%AccessEvent{}, %{})

      refute changeset.valid?
      assert {:action, ["can't be blank"]} in errors_on(changeset)
      assert {:user_type, ["can't be blank"]} in errors_on(changeset)
      assert {:resource_type, ["can't be blank"]} in errors_on(changeset)
      assert {:role_name, ["can't be blank"]} in errors_on(changeset)
    end

    test "RoleAssignment validates required fields" do
      changeset = RoleAssignment.changeset(%RoleAssignment{}, %{})

      refute changeset.valid?
      assert {:user_type, ["can't be blank"]} in errors_on(changeset)
      assert {:user_id, ["can't be blank"]} in errors_on(changeset)
      assert {:resource_type, ["can't be blank"]} in errors_on(changeset)
      assert {:role_name, ["can't be blank"]} in errors_on(changeset)
    end

    test "WebhookSubscription validates required fields" do
      changeset = WebhookSubscription.changeset(%WebhookSubscription{}, %{})

      refute changeset.valid?
      assert {:url, ["can't be blank"]} in errors_on(changeset)
    end

    test "Invoice validates required fields" do
      changeset = Invoice.changeset(%Invoice{}, %{})

      refute changeset.valid?
      assert {:number, ["can't be blank"]} in errors_on(changeset)
      assert {:amount, ["can't be blank"]} in errors_on(changeset)
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%\{\w+\}", message, fn _ ->
        to_string(opts[String.to_atom(String.slice(message, 2..-2))])
      end)
    end)
    |> Enum.map(fn {key, val} -> {key, val} end)
  end
end
