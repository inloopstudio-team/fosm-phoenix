defmodule Fosm.Factory do
  @moduledoc """
  ExMachina factories for FOSM testing.

  Provides factories for all FOSM schema modules with sensible defaults.
  Supports both `insert!/1` and `build/1` patterns.

  ## Usage

      # Build a record (in memory only)
      invoice = Fosm.Factory.build(:invoice, state: "draft")

      # Insert into database
      invoice = Fosm.Factory.insert!(:invoice, state: "paid")

  ## Available Factories

  - `:user` - Basic user for RBAC testing
  - `:role_assignment` - RBAC role assignment
  - `:invoice` - Example FOSM model (draft -> sent -> paid)
  - `:workflow` - Example multi-state workflow
  - `:transition_log` - Audit log entry
  - `:webhook_subscription` - Webhook configuration
  - `:snapshot` - State snapshot record
  """

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
    base = user_factory()
    %{base |
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
    %Fosm.Invoice{
      id: System.unique_integer([:positive]),
      state: "draft",
      number: sequence(:invoice_name, &"INV-#{&1}"),
      amount: Decimal.new("100.00"),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Factory for an invoice in sent state.
  """
  def sent_invoice_factory do
    base = invoice_factory()
    %{base | state: "sent"}
  end

  @doc """
  Factory for a paid (terminal state) invoice.
  """
  def paid_invoice_factory do
    base = invoice_factory()
    %{base | state: "paid"}
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
    %Fosm.TransitionLog{
      id: System.unique_integer([:positive]),
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
      inserted_at: DateTime.utc_now()
    }
  end

  @doc """
  Factory for a transition log entry triggered by an agent.
  """
  def agent_transition_log_factory do
    base = transition_log_factory()
    %{base |
      actor_type: "symbol",
      actor_label: "agent",
      actor_id: nil
    }
  end

  @doc """
  Factory for a webhook subscription.
  """
  def webhook_subscription_factory do
    %Fosm.WebhookSubscription{
      id: System.unique_integer([:positive]),
      model_class_name: "Fosm.Invoice",
      event_name: "pay",
      url: "https://example.com/webhooks/invoice-paid",
      secret_token: "secret_#{System.unique_integer()}",
      active: true,
      inserted_at: DateTime.utc_now()
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

      invoice = Fosm.Factory.insert_with_state!(:invoice, "sent")
      assert invoice.state == "sent"
  """
  def insert_with_state!(factory_name, state, attrs \\ %{}) do
    attrs = Map.merge(attrs, %{state: state})
    insert!(factory_name, attrs)
  end

  @doc """
  Creates a role assignment for a user on a specific resource.

  ## Examples

      user = Fosm.Factory.insert!(:user)
      invoice = Fosm.Factory.insert!(:invoice)
      assignment = Fosm.Factory.assign_role!(user, invoice, :owner)
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

      user = Fosm.Factory.insert!(:user)
      assignment = Fosm.Factory.assign_type_role!(user, "Fosm.Invoice", :viewer)
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

  # ============================================================================
  # Core Factory Functions (inspired by ExMachina)
  # ============================================================================

  @doc """
  Builds a factory struct without inserting to database.

  ## Examples

      invoice = Fosm.Factory.build(:invoice)
      invoice = Fosm.Factory.build(:invoice, state: "paid", amount: 500)
  """
  def build(factory_name, attrs \\ %{}) do
    factory_name
    |> build_factory()
    |> merge_attributes(attrs)
    |> evaluate_sequences()
  end

  @doc """
  Builds a list of factory structs.

  ## Examples

      invoices = Fosm.Factory.build_list(3, :invoice)
  """
  def build_list(n, factory_name, attrs \\ %{}) do
    for _ <- 1..n, do: build(factory_name, attrs)
  end

  @doc """
  Inserts a factory into the database (or simulates if no DB available).

  ## Examples

      invoice = Fosm.Factory.insert!(:invoice)
      invoice = Fosm.Factory.insert!(:invoice, state: "paid")
  """
  def insert!(factory_name, attrs \\ %{}) do
    record = build(factory_name, attrs)
    insert_to_storage(record)
  end

  @doc """
  Inserts a list of factories.

  ## Examples

      invoices = Fosm.Factory.insert_list!(3, :invoice)
  """
  def insert_list!(n, factory_name, attrs \\ %{}) do
    for _ <- 1..n, do: insert!(factory_name, attrs)
  end

  @doc """
  Returns a factory function for generating unique values.

  ## Examples

      email = Fosm.Factory.sequence(:email, fn n -> "user\#{n}@example.com" end)
  """
  def sequence(name, fun) do
    # Simple counter-based sequence
    key = {:factory_sequence, name}
    current = Process.get(key, 0)
    Process.put(key, current + 1)
    fun.(current)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp build_factory(factory_name) do
    case factory_name do
      :user -> user_factory()
      :admin_user -> admin_user_factory()
      :role_assignment -> role_assignment_factory()
      :invoice -> invoice_factory()
      :sent_invoice -> sent_invoice_factory()
      :paid_invoice -> paid_invoice_factory()
      :workflow -> workflow_factory()
      :transition_log -> transition_log_factory()
      :agent_transition_log -> agent_transition_log_factory()
      :webhook_subscription -> webhook_subscription_factory()
      :snapshot -> snapshot_factory()
      _ -> raise "Unknown factory: #{inspect(factory_name)}"
    end
  end

  defp merge_attributes(record, attrs) when is_struct(record) do
    Enum.reduce(attrs, record, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  defp merge_attributes(record, attrs) when is_map(record) do
    Map.merge(record, attrs)
  end

  defp evaluate_sequences(record) do
    # Process any lazy sequences in the record
    # For now, sequences are evaluated during build
    record
  end

  defp insert_to_storage(%{__struct__: module} = record) do
    # Try to insert using the module's Repo if available
    try do
      repo = module.__schema__(:repo)
      if repo && Process.whereis(repo) do
        repo.insert!(record)
      else
        # No repo available, simulate with ID
        Map.put(record, :id, System.unique_integer([:positive]))
      end
    rescue
      # Fallback for non-Ecto structs or no Repo
      _ ->
        Map.put(record, :id, System.unique_integer([:positive]))
    end
  end

  defp insert_to_storage(record) when is_map(record) do
    # For plain maps, just add an ID
    Map.put(record, :id, System.unique_integer([:positive]))
  end
end