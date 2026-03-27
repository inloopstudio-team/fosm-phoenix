defmodule Fosm.FactoryTest do
  @moduledoc """
  Tests for ExMachina factories.

  Litmus test: Verifies all factories create valid records.
  """
  use Fosm.DataCase, async: true

  import Fosm.Factory

  describe "user factories" do
    test "user_factory/0 creates valid user" do
      user = build(:user)

      assert user.id != nil
      assert user.__struct__ == Fosm.User
      assert user.email =~ ~r/@example\.com$/
      assert user.superadmin == false
    end

    test "admin_user_factory/0 creates admin user" do
      admin = build(:admin_user)

      assert admin.superadmin == true
      assert admin.email =~ ~r/admin/
    end

    test "insert! creates unique users" do
      user1 = insert!(:user)
      user2 = insert!(:user)

      assert user1.id != user2.id
      assert user1.email != user2.email
    end
  end

  describe "role_assignment factories" do
    test "role_assignment_factory/0 creates valid assignment" do
      assignment = build(:role_assignment)

      assert assignment.__struct__ == Fosm.RoleAssignment
      assert assignment.role_name == "owner"
      assert assignment.resource_type == "Fosm.Invoice"
    end

    test "assign_role! creates record-level assignment" do
      user = build(:user)
      invoice = build(:invoice)

      assignment = assign_role!(user, invoice, :approver)

      assert assignment.user_id == to_string(user.id)
      assert assignment.resource_id == to_string(invoice.id)
      assert assignment.role_name == "approver"
    end

    test "assign_type_role! creates type-level assignment" do
      user = build(:user)

      assignment = assign_type_role!(user, "Fosm.Invoice", :viewer)

      assert assignment.user_id == to_string(user.id)
      assert assignment.resource_id == nil
      assert assignment.role_name == "viewer"
    end
  end

  describe "model factories" do
    test "invoice_factory/0 creates draft invoice" do
      invoice = build(:invoice)

      assert invoice.__struct__ == Fosm.Invoice
      assert invoice.state == "draft"
      assert invoice.amount != nil
    end

    test "sent_invoice_factory creates sent invoice" do
      invoice = build(:sent_invoice)
      assert invoice.state == "sent"
    end

    test "paid_invoice_factory creates paid invoice" do
      invoice = build(:paid_invoice)
      assert invoice.state == "paid"
    end

    test "workflow_factory/0 creates workflow" do
      workflow = build(:workflow)

      assert workflow.__struct__ == Fosm.Workflow
      assert workflow.state == "pending"
    end

    test "insert_with_state! creates with specified state" do
      invoice = insert_with_state!(:invoice, "archived")
      assert invoice.state == "archived"
    end
  end

  describe "audit factories" do
    test "transition_log_factory/0 creates valid log" do
      log = build(:transition_log)

      assert log.__struct__ == Fosm.TransitionLog
      assert log.event_name == "send"
      assert log.from_state == "draft"
      assert log.to_state == "sent"
    end

    test "agent_transition_log_factory marks actor as agent" do
      log = build(:agent_transition_log)

      assert log.actor_type == "symbol"
      assert log.actor_label == "agent"
      assert log.actor_id == nil
    end

    test "webhook_subscription_factory creates valid webhook" do
      webhook = build(:webhook_subscription)

      assert webhook.__struct__ == Fosm.WebhookSubscription
      assert webhook.active == true
      assert webhook.url =~ ~r/^https:/
    end

    test "snapshot_factory creates valid snapshot" do
      snapshot = build(:snapshot)

      assert snapshot.__struct__ == Fosm.Snapshot
      assert snapshot.state == "paid"
      assert is_map(snapshot.data)
    end
  end
end
