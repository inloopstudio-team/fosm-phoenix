defmodule FosmWeb.Controllers.InvoiceController do
  @moduledoc """
  Controller for Invoice FOSM resource.
  """

  use FosmWeb, :controller

  require Ecto.Query
  import Ecto.Query

  alias Fosm.Invoice
  alias Fosm.Repo

  def index(conn, params) do
    invoices = list_invoices(params)
    render(conn, :index, invoices: invoices)
  end

  def show(conn, %{"id" => id}) do
    invoice = Repo.get!(Invoice, id)
    render(conn, :show, invoice: invoice)
  end

  def create(conn, %{"invoice" => invoice_params}) do
    with {:ok, invoice} <- create_invoice(invoice_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", "/invoices/#{invoice.id}")
      |> render(:show, invoice: invoice)
    end
  end

  def update(conn, %{"id" => id, "invoice" => invoice_params}) do
    invoice = Repo.get!(Invoice, id)

    with {:ok, invoice} <- update_invoice(invoice, invoice_params) do
      render(conn, :show, invoice: invoice)
    end
  end

  def fire_event(conn, %{"id" => id, "event" => event_name} = params) do
    invoice = Repo.get!(Invoice, id)
    actor = params["actor"] || :system

    event = String.to_atom(event_name)

    case Invoice.fire!(invoice, event, actor: actor) do
      {:ok, updated} ->
        render(conn, :show, invoice: updated)

      {:error, error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_error(error)})
    end
  end

  def available_events(conn, %{"id" => id}) do
    invoice = Repo.get!(Invoice, id)
    events = Invoice.available_events(invoice)

    conn
    |> put_status(:ok)
    |> json(%{events: events, current_state: invoice.state})
  end

  def transitions(conn, %{"id" => id}) do
    history =
      Fosm.TransitionLog
      |> Fosm.TransitionLog.for_record("invoices", id)
      |> Fosm.TransitionLog.recent()
      |> Repo.all()

    conn
    |> put_status(:ok)
    |> json(%{transitions: history})
  end

  def delete(conn, %{"id" => id}) do
    invoice = Repo.get!(Invoice, id)

    with {:ok, _} <- Repo.delete(invoice) do
      send_resp(conn, :no_content, "")
    end
  end

  defp list_invoices(params) do
    query = Invoice

    query = case params["state"] do
      nil -> query
      state -> from(q in query, where: q.state == ^state)
    end

    query
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  defp create_invoice(attrs) do
    %Invoice{}
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  defp update_invoice(invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.update()
  end

  defp format_error(%Fosm.Errors.GuardFailed{guard: guard, reason: reason}) do
    "Guard '#{guard}' failed" <> if(reason, do: ": #{reason}", else: "")
  end
  defp format_error(%Fosm.Errors.TerminalState{}), do: "Terminal state - cannot transition"
  defp format_error(%Fosm.Errors.InvalidTransition{} = e), do: "Cannot #{e.event} from #{e.from}"
  defp format_error(%Fosm.Errors.AccessDenied{}), do: "Access denied"
  defp format_error(e), do: Exception.message(e)
end
