defmodule Fosm.Database.ConstraintTest do
  @moduledoc """
  Tests database constraints including immutability constraints.

  Covers:
  - Immutability of transition logs (no updates/deletes)
  - Immutability of access events (no updates/deletes)
  - Unique constraints on role assignments
  - Unique constraints on webhook subscriptions
  - Foreign key constraints where applicable
  - NOT NULL constraints
  """

  use Fosm.DataCase, async: true

  alias Fosm.{
    TransitionLog,
    AccessEvent,
    RoleAssignment,
    WebhookSubscription
  }

  alias Ecto.Adapters.SQL

  describe "transition_logs immutability constraints" do
    test "cannot update transition_log records" do
      log =
        TransitionLog.create!(%{
          record_type: "invoices",
          record_id: "123",
          event_name: "pay",
          from_state: "draft",
          to_state: "paid"
        })

      # Attempt to update should fail
      assert_raise Postgrex.Error, fn ->
        Fosm.Repo.update_all(
          from(l in TransitionLog, where: l.id == ^log.id),
          set: [event_name: "tampered"]
        )
      end
    end

    test "cannot delete transition_log records via SQL" do
      log =
        TransitionLog.create!(%{
          record_type: "invoices",
          record_id: "456",
          event_name: "send",
          from_state: "draft",
          to_state: "sent"
        })

      # Attempt to delete should fail
      assert_raise Postgrex.Error, fn ->
        Fosm.Repo.delete_all(from(l in TransitionLog, where: l.id == ^log.id))
      end
    end
  end

  describe "access_events immutability constraints" do
    test "cannot update access_event records" do
      event =
        AccessEvent.create!(%{
          action: "grant",
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          role_name: "owner",
          result: "allowed"
        })

      # Attempt to update should fail
      assert_raise Postgrex.Error, fn ->
        Fosm.Repo.update_all(
          from(e in AccessEvent, where: e.id == ^event.id),
          set: [action: "revoke"]
        )
      end
    end

    test "cannot delete access_event records via SQL" do
      event =
        AccessEvent.create!(%{
          action: "grant",
          user_type: "Fosm.User",
          user_id: "99",
          resource_type: "Fosm.Invoice",
          role_name: "viewer",
          result: "allowed"
        })

      # Attempt to delete should fail
      assert_raise Postgrex.Error, fn ->
        Fosm.Repo.delete_all(from(e in AccessEvent, where: e.id == ^event.id))
      end
    end
  end

  describe "role_assignments unique constraints" do
    test "cannot create duplicate role assignment at resource level" do
      # Create first assignment
      {:ok, _} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner"
        })
        |> Fosm.Repo.insert()

      # Attempt duplicate should fail
      {:error, changeset} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner"
        })
        |> Fosm.Repo.insert()

      refute changeset.valid?
      assert {:user_type, ["has already been taken"]} in errors_on(changeset)
    end

    test "cannot create duplicate role assignment at type level" do
      # Create first type-level assignment
      {:ok, _} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: nil,
          role_name: "viewer"
        })
        |> Fosm.Repo.insert()

      # Attempt duplicate should fail
      {:error, changeset} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: nil,
          role_name: "viewer"
        })
        |> Fosm.Repo.insert()

      refute changeset.valid?
      # Check that we got a unique constraint error
      errors = errors_on(changeset)
      has_unique_error =
        Enum.any?(errors, fn {field, msgs} ->
          field in [:user_type] && "has already been taken" in msgs
        end)
      assert has_unique_error, "Expected unique constraint error, got: #{inspect(errors)}"
    end

    test "same user can have different roles on same resource" do
      # First role
      {:ok, _} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner"
        })
        |> Fosm.Repo.insert()

      # Different role should succeed
      {:ok, assignment2} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "viewer"
        })
        |> Fosm.Repo.insert()

      assert assignment2.role_name == "viewer"
    end

    test "same role can be assigned to different users" do
      # First user
      {:ok, _} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "1",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner"
        })
        |> Fosm.Repo.insert()

      # Second user should succeed
      {:ok, assignment2} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "2",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner"
        })
        |> Fosm.Repo.insert()

      assert assignment2.user_id == "2"
    end

    test "same role can be assigned on different resources" do
      # First resource
      {:ok, _} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner"
        })
        |> Fosm.Repo.insert()

      # Different resource should succeed
      {:ok, assignment2} =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "200",
          role_name: "owner"
        })
        |> Fosm.Repo.insert()

      assert assignment2.resource_id == "200"
    end
  end

  describe "webhook_subscriptions unique constraints" do
    test "cannot create duplicate webhook for same target" do
      # Create first subscription
      {:ok, _} =
        %WebhookSubscription{}
        |> WebhookSubscription.changeset(%{
          url: "https://example.com/webhook",
          record_type: "Fosm.Invoice",
          record_id: "100"
        })
        |> Fosm.Repo.insert()

      # Attempt duplicate should fail
      {:error, changeset} =
        %WebhookSubscription{}
        |> WebhookSubscription.changeset(%{
          url: "https://example.com/webhook",
          record_type: "Fosm.Invoice",
          record_id: "100"
        })
        |> Fosm.Repo.insert()

      refute changeset.valid?
      assert {:url, ["Webhook already registered for this target"]} in errors_on(changeset)
    end

    test "different URLs can subscribe to same record" do
      # First subscription
      {:ok, _} =
        %WebhookSubscription{}
        |> WebhookSubscription.changeset(%{
          url: "https://first.com/webhook",
          record_type: "Fosm.Invoice",
          record_id: "100"
        })
        |> Fosm.Repo.insert()

      # Different URL should succeed
      {:ok, subscription2} =
        %WebhookSubscription{}
        |> WebhookSubscription.changeset(%{
          url: "https://second.com/webhook",
          record_type: "Fosm.Invoice",
          record_id: "100"
        })
        |> Fosm.Repo.insert()

      assert subscription2.url == "https://second.com/webhook"
    end

    test "same URL can subscribe to different records" do
      # First subscription
      {:ok, _} =
        %WebhookSubscription{}
        |> WebhookSubscription.changeset(%{
          url: "https://example.com/webhook",
          record_type: "Fosm.Invoice",
          record_id: "100"
        })
        |> Fosm.Repo.insert()

      # Different record should succeed
      {:ok, subscription2} =
        %WebhookSubscription{}
        |> WebhookSubscription.changeset(%{
          url: "https://example.com/webhook",
          record_type: "Fosm.Invoice",
          record_id: "200"
        })
        |> Fosm.Repo.insert()

      assert subscription2.record_id == "200"
    end
  end

  describe "NOT NULL constraints" do
    test "transition_logs enforces NOT NULL on required columns" do
      adapter = Fosm.Repo.__adapter__()

      # PostgreSQL enforces NOT NULL at the database level
      case adapter do
        Ecto.Adapters.Postgres ->
          assert_raise Postgrex.Error, fn ->
            SQL.query!(Fosm.Repo, """
            INSERT INTO fosm_transition_logs (id, record_type, record_id, event_name, from_state, to_state, inserted_at)
            VALUES (gen_random_uuid(), NULL, '123', 'test', 'a', 'b', NOW())
            """)
          end

        _ ->
          # SQLite may be less strict depending on configuration
          :ok
      end
    end

    test "access_events enforces NOT NULL on required columns" do
      adapter = Fosm.Repo.__adapter__()

      case adapter do
        Ecto.Adapters.Postgres ->
          assert_raise Postgrex.Error, fn ->
            SQL.query!(Fosm.Repo, """
            INSERT INTO fosm_access_events (id, action, user_type, user_id, resource_type, role_name, result, inserted_at)
            VALUES (gen_random_uuid(), NULL, 'User', '1', 'Invoice', 'owner', 'allowed', NOW())
            """)
          end

        _ ->
          :ok
      end
    end

    test "role_assignments enforces NOT NULL on required columns" do
      adapter = Fosm.Repo.__adapter__()

      case adapter do
        Ecto.Adapters.Postgres ->
          assert_raise Postgrex.Error, fn ->
            SQL.query!(Fosm.Repo, """
            INSERT INTO fosm_role_assignments (id, user_type, user_id, resource_type, role_name, inserted_at, updated_at)
            VALUES (gen_random_uuid(), NULL, '1', 'Invoice', 'owner', NOW(), NOW())
            """)
          end

        _ ->
          :ok
      end
    end
  end

  describe "webhook_subscriptions update/delete behavior" do
    test "can update webhook subscription" do
      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook",
          active: true
        })

      {:ok, updated} =
        subscription
        |> WebhookSubscription.changeset(%{active: false})
        |> Fosm.Repo.update()

      assert updated.active == false
    end

    test "can delete webhook subscription" do
      subscription =
        WebhookSubscription.create!(%{
          url: "https://example.com/webhook"
        })

      {:ok, _} = Fosm.Repo.delete(subscription)

      refute Fosm.Repo.get(WebhookSubscription, subscription.id)
    end
  end

  describe "role_assignments update/delete behavior" do
    test "can update role assignment expiration" do
      assignment =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner"
        })
        |> Fosm.Repo.insert!()

      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, updated} =
        assignment
        |> RoleAssignment.changeset(%{expires_at: future})
        |> Fosm.Repo.update()

      # Compare with truncated seconds since database may not preserve microsecond precision
      assert DateTime.compare(
        DateTime.truncate(updated.expires_at, :second),
        future
      ) == :eq
    end

    test "can delete role assignment" do
      assignment =
        %RoleAssignment{}
        |> RoleAssignment.changeset(%{
          user_type: "Fosm.User",
          user_id: "42",
          resource_type: "Fosm.Invoice",
          resource_id: "100",
          role_name: "owner"
        })
        |> Fosm.Repo.insert!()

      {:ok, _} = Fosm.Repo.delete(assignment)

      refute Fosm.Repo.get(RoleAssignment, assignment.id)
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
