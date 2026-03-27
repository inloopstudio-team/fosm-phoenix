defmodule Fosm.Factory do
  @moduledoc """
  ExMachina factories for FOSM testing.

  Provides factories for all FOSM schema modules with sensible defaults.
  Supports both `insert!/1` and `build/1` patterns.

  ## Usage

      # Build a record (in memory only)
      invoice = build(:invoice, state: "draft")

      # Insert into database
      invoice = insert!(:invoice, state: "paid")

      # Create with associations
      user = insert!(:user)
      invoice = insert!(:invoice, created_by: user)

  ## Available Factories

  - `:user` - Basic user for RBAC testing
  - `:role_assignment` - RBAC role assignment
  - `:invoice` - Example FOSM model (draft -> sent -> paid)
  - `:workflow` - Example multi-state workflow
  - `:transition_log` - Audit log entry
  - `:webhook_subscription` - Webhook configuration
  - `:snapshot` - State snapshot record
  """

  use ExMachina.Ecto, repo: Fosm.Repo

  # ============================================================================
  # User & RBAC Factories
  # ============================================================================

  @doc """
  Factory for a basic user.
  """
  def user_factory do
    %{
      id: System.unique_integer([:positive]),
      __struct__: Fosm.User,
      email: sequence(:email, &"user#{&1}@example.com"),
      name: sequence(:name, &"Test User #{&1}"),
      superadmin: false,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Factory for an admin user.
  """
  def admin_user_factory do
    %{user_factory() |
      email: sequence(:admin_email, &"admin#{&1}@example.com"),
      superadmin: true
    }
  end

  @doc """
  Factory for a role assignment.
  """
  def role_assignment_factory do
    user = build(:user)

    %{
      id: System.unique_integer([:positive]),
      __struct__: Fosm.RoleAssignment,
      user_type: "Fosm.User",
      user_id: to_string(user.id),
      resource_type: "Fosm.Invoice",
      resource_id: nil,  # nil for type-level, string ID for record-level
      role_name: "owner",
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  # ============================================================================
  # FOSM Model Factories
  # ============================================================================

  @doc """
  Factory for a simple invoice with lifecycle.
  """
  def invoice_factory do
    %{
      id: System.unique_integer([:positive]),
      __struct__: Fosm.Invoice,
      name: sequence(:invoice_name, &"Invoice #{&1}"),
      amount: Decimal.new("100.00"),
      state: "draft",
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Factory for an invoice in sent state.
  """
  def sent_invoice_factory do
    %{invoice_factory() | state: "sent"}
  end

  @doc """
  Factory for a paid (terminal state) invoice.
  """
  def paid_invoice_factory do
    %{invoice_factory() | state: "paid"}
  end

  @doc """
  Factory for a workflow with multiple states.
  """
  def workflow_factory do
    %{
      id: System.unique_integer([:positive]),
      __struct__: Fosm.Workflow,
      title: sequence(:workflow_title, &"Workflow #{&1}"),
      state: "pending",
      priority: "medium",
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  # ============================================================================
  # Audit & Webhook Factories
  # ============================================================================

  @doc """
  Factory for a transition log entry.
  """
  def transition_log_factory do
    %{
      id: System.unique_integer([:positive]),
      __struct__: Fosm.TransitionLog,
      record_type: "invoices",
      record_id: "1",
      event_name: "send",
      from_state: "draft",
      to_state: "sent",
      actor_type: "Fosm.User",
      actor_id: "1",
      actor_label: nil,
      metadata: %{},
      state_snapshot: nil,
      snapshot_reason: nil,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Factory for a transition log entry triggered by an agent.
  """
  def agent_transition_log_factory do
    %{transition_log_factory() |
      actor_type: "symbol",
      actor_label: "agent",
      actor_id: nil
    }
  end

  @doc """
  Factory for a webhook subscription.
  """
  def webhook_subscription_factory do
    %{
      id: System.unique_integer([:positive]),
      __struct__: Fosm.WebhookSubscription,
      model_class_name: "Fosm.Invoice",
      event_name: "pay",
      url: "https://example.com/webhooks/invoice-paid",
      secret_token: "secret_#{System.unique_integer()}",
      active: true,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Factory for a state snapshot.
  """
  def snapshot_factory do
    %{
      id: System.unique_integer([:positive]),
      __struct__: Fosm.Snapshot,
      record_type: "invoices",
      record_id: "1",
      state: "paid",
      data: %{
        "id" => 1,
        "name" => "Test Invoice",
        "amount" => "100.00",
        "state" => "paid"
      },
      reason: :transition,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Creates a record with the specified state for a FOSM model.

  ## Examples

      invoice = insert_with_state!(:invoice, "sent")
      assert invoice.state == "sent"
  """
  def insert_with_state!(factory_name, state, attrs \\ %{}) do
    attrs
    |> Map.put(:state, state)
    |> insert!(factory_name)
  end

  @doc """
  Creates a role assignment for a user on a specific resource.

  ## Examples

      user = insert!(:user)
      invoice = insert!(:invoice)
      assignment = assign_role!(user, invoice, :owner)
  """
  def assign_role!(user, resource, role_name, resource_type \\ nil) do
    resource_type = resource_type || resource.__struct__.__schema__(:source)

    insert!(:role_assignment,
      user_type: to_string(user.__struct__),
      user_id: to_string(user.id),
      resource_type: resource_type,
      resource_id: to_string(resource.id),
      role_name: to_string(role_name)
    )
  end

  @doc """
  Creates a type-level role assignment (applies to all records of a type).

  ## Examples

      user = insert!(:user)
      assignment = assign_type_role!(user, "Fosm.Invoice", :viewer)
  """
  def assign_type_role!(user, resource_type, role_name) do
    insert!(:role_assignment,
      user_type: to_string(user.__struct__),
      user_id: to_string(user.id),
      resource_type: resource_type,
      resource_id: nil,
      role_name: to_string(role_name)
    )
  end
end
