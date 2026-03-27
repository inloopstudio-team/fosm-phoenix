defmodule Fosm.Invoice do
  @moduledoc """
  Invoice FOSM (Finite Object State Machine) model.
  """

  use Ecto.Schema
  use Fosm.Lifecycle

  require Ecto.Query
  import Ecto.Query
  import Ecto.Changeset

  alias Fosm.Repo

  @type t :: %__MODULE__{}


  schema "invoices" do
    field :state, :string, default: "draft"

    field :number, :string
    field :amount, :decimal
    field :due_date, :date


    # FOSM tracking fields
    field :fosm_metadata, :map, default: %{}

    timestamps()
  end

  @doc """
  Changeset for creating or updating a Invoice.
  Note: State should NOT be changed directly through changeset - use fire!/3.
  """
  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [
      :number, :amount, :due_date
    ])
    |> validate_required([:number, :amount])

  end

  @doc """
  Returns a changeset for the given state transition.
  This is called internally by fire!/3.
  """
  def state_changeset(struct, _event, _opts) do
    # Add any automatic field updates on transition here
    change(struct)
  end

  # ============================================================================
  # Lifecycle Definition
  # ============================================================================

  lifecycle do
    # --------------------------------------------------------------------------
    # States
    # --------------------------------------------------------------------------
    state :draft, initial: true
    state :sent
    state :paid, terminal: true
    state :void, terminal: true

    # --------------------------------------------------------------------------
    # Events (Transitions)
    # --------------------------------------------------------------------------
    event :move_to_sent, from: :draft, to: :sent
    event :pay, from: [:draft, :sent], to: :paid
    event :void, from: [:draft, :sent], to: :void

    # TODO: Add more events as needed
    # Example:
    # event :send, from: :draft, to: :sent
    # event :pay, from: :sent, to: :paid

    # --------------------------------------------------------------------------
    # Guards (Validation)
    # --------------------------------------------------------------------------
    # Guards prevent invalid transitions. They run before the transition and must
    # return :ok or {:error, reason}.
    #
    # Example:
    # guard :has_required_fields, on: :complete do
    #   if record.name && record.amount do
    #     :ok
    #   else
    #     {:error, "Name and amount are required"}
    #   end
    # end

    # guard :can_move_to_sent, on: :move_to_sent do
    #   # Add validation logic here
    #   :ok
    # end

    # guard :can_paid, on: :paid do
    #   # Add validation logic here
    #   :ok
    # end

    # guard :can_paid, on: :paid do
    #   # Add validation logic here
    #   :ok
    # end

    # guard :can_void, on: :void do
    #   # Add validation logic here
    #   :ok
    # end

    # guard :can_void, on: :void do
    #   # Add validation logic here
    #   :ok
    # end


    # --------------------------------------------------------------------------
    # Access Control Guards
    # --------------------------------------------------------------------------
    # Uncomment to enable RBAC guards:
    #
    # guard :check_access, on: :all do
    #   required_roles = [:admin, :accountant]
    #   if Fosm.Current.has_any_role?(actor, required_roles) do
    #     :ok
    #   else
    #     {:error, :access_denied}
    #   end
    # end

    # --------------------------------------------------------------------------
    # Side Effects (Actions)
    # --------------------------------------------------------------------------
    # Side effects run after the transition commits. They can be deferred
    # (async via Oban) or immediate.
    #
    # Example:
    # effect :send_notification, on: :send do
    #   # Runs immediately after commit
    #   MyApp.Notifier.send_email(record)
    # end
    #
    # effect :sync_to_crm, on: :pay, defer: true do
    #   # Queued as Oban job
    #   MyApp.CRM.sync(record)
    # end

  end

  # ============================================================================
  # State Predicates
  # ============================================================================

  @doc "Returns true if the record is in draft state."
  def draft?(record), do: record.state == "draft"
  @doc "Returns true if the record is in draft state."
  def sent?(record), do: record.state == "sent"
  @doc "Returns true if the record is in draft state."
  def paid?(record), do: record.state == "paid"
  @doc "Returns true if the record is in draft state."
  def void?(record), do: record.state == "void"

  # ============================================================================
  # Query Helpers
  # ============================================================================

  def with_state(query \\ __MODULE__, state) do
    from(q in query, where: q.state == ^state)
  end

  def initial_state(query \\ __MODULE__) do
    with_state(query, "draft")
  end

  def terminal_states(query \\ __MODULE__) do
    states = [:paid, :void]
    from(q in query, where: q.state in ^states)
  end

  def non_terminal_states(query \\ __MODULE__) do
    states = [:draft, :sent]
    from(q in query, where: q.state in ^states)
  end

  # ============================================================================
  # Snapshot Configuration
  # ============================================================================

  # Define what fields to capture in transition snapshots
  # def snapshot_configuration do
  #   %Fosm.Lifecycle.SnapshotConfiguration{
  #     attributes: [:name, :amount, :state],
  #     include_associations: [:line_items],
  #     include_metadata: true
  #   }
  # end
end
