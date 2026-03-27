defmodule Examples.InvoiceWorkflow do
  @moduledoc """
  Example: Invoice workflow with guards, side effects, and access control.

  This example demonstrates:
  - Multi-state workflow (draft -> sent -> paid/cancelled)
  - Guards for validation
  - Side effects for email notifications
  - Access control with roles
  - Webhook integration

  ## Usage

  ```elixir
  # Create an invoice
  {:ok, invoice} = Examples.InvoiceWorkflow.create_invoice(%{
    amount: 100.00,
    customer_email: "customer@example.com"
  })

  # Send it
  {:ok, invoice} = Examples.InvoiceWorkflow.send_invoice(invoice, current_user)

  # Customer pays via external system
  {:ok, invoice} = Examples.InvoiceWorkflow.record_payment(invoice, payment_processor)
  ```
  """

  alias Fosm.Errors

  # ============================================================================
  # Schema Definition (would normally be in lib/my_app/invoice.ex)
  # ============================================================================

  defmodule Invoice do
    @moduledoc """
    Invoice schema with complete FOSM lifecycle.
    """
    use Ecto.Schema
    use Fosm.Lifecycle

    schema "invoices" do
      field :state, :string, default: "draft"
      field :amount, :decimal
      field :customer_email, :string
      field :sent_at, :utc_datetime
      field :paid_at, :utc_datetime
      timestamps()
    end

    # Snapshot configuration - save state every 5 transitions
    snapshot every: 5, on_terminate: true

    lifecycle do
      # ------------------------------------------------------------------------
      # States
      # ------------------------------------------------------------------------

      state :draft, initial: true do
        description "Invoice created but not yet sent"
      end

      state :sent do
        description "Invoice sent to customer, awaiting payment"
      end

      state :paid, terminal: true do
        description "Payment received in full"
      end

      state :cancelled, terminal: true do
        description "Invoice cancelled, no payment due"
      end

      state :overdue do
        description "Payment deadline passed"
      end

      # ------------------------------------------------------------------------
      # Events & Transitions
      # ------------------------------------------------------------------------

      event :send do
        transition from: :draft, to: :sent

        # Validate before sending
        guard :has_customer_email do
          if is_nil(record.customer_email) or record.customer_email == "" do
            {:error, "Customer email required to send invoice"}
          else
            :ok
          end
        end

        guard :positive_amount do
          if Decimal.compare(record.amount, Decimal.new("0")) == :gt do
            :ok
          else
            {:error, "Invoice amount must be positive"}
          end
        end

        # Record send time
        side_effect :record_sent_at do
          {:ok, %{record | sent_at: DateTime.utc_now()}}
        end

        # Send email notification
        side_effect :notify_customer do
          Examples.InvoiceWorkflow.send_invoice_email(record)
          :ok
        end
      end

      event :pay do
        transition from: [:sent, :overdue], to: :paid

        guard :not_already_paid do
          if record.paid_at do
            {:error, "Invoice already marked as paid"}
          else
            :ok
          end
        end

        side_effect :record_payment_time do
          {:ok, %{record | paid_at: DateTime.utc_now()}}
        end

        side_effect :send_receipt do
          Examples.InvoiceWorkflow.send_payment_receipt(record)
          :ok
        end
      end

      event :cancel do
        transition from: [:draft, :sent], to: :cancelled

        guard :not_paid do
          if record.paid_at do
            {:error, "Cannot cancel already-paid invoice"}
          else
            :ok
          end
        end
      end

      event :mark_overdue do
        transition from: :sent, to: :overdue
        # Called by scheduled job, no guards needed
      end

      # ------------------------------------------------------------------------
      # Access Control
      # ------------------------------------------------------------------------

      access do
        # Sales staff can create and manage invoices
        role :sales, default: true do
          can :crud
          can :send, :cancel
        end

        # Managers have full access
        role :manager do
          can :manage
        end

        # Customers can only view their own invoices
        # This is handled at the query level, not lifecycle level
      end
    end

    # Webhook for payment notifications
    webhook :payment_received,
      url: "https://api.example.com/webhooks/payment",
      on: [:pay],
      secret: fn -> System.get_env("PAYMENT_WEBHOOK_SECRET") end
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Creates a new invoice in draft state.

  ## Examples

      iex> create_invoice(%{amount: 100.00, customer_email: "test@example.com"})
      {:ok, %Invoice{state: "draft"}}

      iex> create_invoice(%{amount: -10.00})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_invoice(map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def create_invoice(attrs) do
    %Invoice{}
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Sends an invoice to the customer.

  ## Examples

      iex> send_invoice(invoice, current_user)
      {:ok, %Invoice{state: "sent", sent_at: %DateTime{}}}

      iex> send_invoice(invoice_without_email, current_user)
      {:error, "Guard 'has_customer_email' failed: Customer email required to send invoice"}
  """
  @spec send_invoice(Invoice.t(), struct()) :: {:ok, Invoice.t()} | {:error, term()}
  def send_invoice(invoice, actor) do
    Invoice.fire!(invoice, :send, actor: actor)
  end

  @doc """
  Records payment for an invoice.

  ## Examples

      iex> record_payment(invoice, payment_processor)
      {:ok, %Invoice{state: "paid", paid_at: %DateTime{}}}
  """
  @spec record_payment(Invoice.t(), struct()) :: {:ok, Invoice.t()} | {:error, term()}
  def record_payment(invoice, actor) do
    Invoice.fire!(invoice, :pay, actor: actor)
  end

  @doc """
  Cancels an invoice (if not yet paid).

  ## Examples

      iex> cancel_invoice(invoice, manager)
      {:ok, %Invoice{state: "cancelled"}}

      iex> cancel_invoice(paid_invoice, manager)
      {:error, "Guard 'not_paid' failed: Cannot cancel already-paid invoice"}
  """
  @spec cancel_invoice(Invoice.t(), struct()) :: {:ok, Invoice.t()} | {:error, term()}
  def cancel_invoice(invoice, actor) do
    Invoice.fire!(invoice, :cancel, actor: actor)
  end

  @doc """
  Lists available actions for an actor on an invoice.

  ## Examples

      iex> available_actions(invoice, sales_person)
      [:pay, :cancel]  # when state is "sent"

      iex> available_actions(invoice, customer)
      []  # customers can't fire lifecycle events
  """
  @spec available_actions(Invoice.t(), struct()) :: [atom()]
  def available_actions(invoice, actor) do
    Fosm.Access.available_events(actor, invoice)
  end

  @doc """
  Gets full transition history for an invoice.
  """
  @spec transition_history(Invoice.t()) :: [Fosm.TransitionLog.t()]
  def transition_history(invoice) do
    Fosm.TransitionLog
    |> Fosm.TransitionLog.for_record("invoices", invoice.id)
    |> Fosm.TransitionLog.with_snapshots()
    |> Fosm.Repo.all()
  end

  # ============================================================================
  # Side Effect Implementations
  # ============================================================================

  @doc false
  @spec send_invoice_email(Invoice.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def send_invoice_email(invoice) do
    %{
      to: invoice.customer_email,
      subject: "Invoice ##{invoice.id} - Payment Due",
      template: "invoice_sent",
      invoice_id: invoice.id
    }
    |> Examples.Emails.InvoiceEmail.new()
    |> Oban.insert()
  end

  @doc false
  @spec send_payment_receipt(Invoice.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def send_payment_receipt(invoice) do
    %{
      to: invoice.customer_email,
      subject: "Payment Received - Invoice ##{invoice.id}",
      template: "payment_receipt",
      invoice_id: invoice.id
    }
    |> Examples.Emails.PaymentReceiptEmail.new()
    |> Oban.insert()
  end

  # ============================================================================
  # Changesets
  # ============================================================================

  def changeset(invoice, attrs) do
    invoice
    |> Ecto.Changeset.cast(attrs, [:amount, :customer_email])
    |> Ecto.Changeset.validate_required([:amount, :customer_email])
    |> Ecto.Changeset.validate_number(:amount, greater_than: 0)
    |> Ecto.Changeset.validate_format(:customer_email, ~r/@/)
  end
end
