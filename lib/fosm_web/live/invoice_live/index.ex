defmodule FosmWeb.Live.InvoiceLive.Index do
  @moduledoc """
  LiveView for listing invoices.
  """

  use FosmWeb, :live_view

  require Ecto.Query
  import Ecto.Query

  alias Fosm.Invoice
  alias Fosm.Repo
  import FosmWeb.CoreComponents, only: [btn: 1, simple_form: 1, input: 1]
  import FosmWeb.Admin.Components, only: [table: 1]


  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      page_title: "Invoices",
      invoices: list_invoices(),
      selected_state: nil
    )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    resource = get_resource!(id)

    socket
    |> assign(:page_title, "Edit Invoice")
    |> assign(:resource, resource)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Invoice")
    |> assign(:resource, %Invoice{state: "draft"})
  end

  defp apply_action(socket, :index, params) do
    state_filter = params["state"]
    invoices = if state_filter, do: list_invoices(state: state_filter), else: list_invoices()

    socket
    |> assign(:page_title, "Invoices")
    |> assign(:invoices, invoices)
    |> assign(:selected_state, state_filter)
    |> assign(:resource, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    resource = get_resource!(id)
    {:ok, _} = Repo.delete(resource)

    {:noreply, stream_delete(socket, :invoices, resource)}
  end

  def handle_event("filter_state", %{"state" => state}, socket) do
    {:noreply, push_patch(socket, to: "/invoices?state=#{state}")}
  end

  def handle_event("clear_filter", _params, socket) do
    {:noreply, push_patch(socket, to: "/invoices")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold">Invoices</h1>
        <.link patch="/invoices/new" class="btn-primary">
          New Invoice
        </.link>
      </div>

      <div class="flex gap-2 items-center">
        <span class="text-sm text-gray-600">Filter by state:</span>
        <%= for state <- ["draft", "sent", "paid", "void"] do %>
          <button
            phx-click={if @selected_state == state, do: "clear_filter", else: "filter_state"}
            phx-value-state={state}
            class={[
              "px-3 py-1 rounded text-sm",
              @selected_state == state && "bg-blue-500 text-white",
              @selected_state != state && "bg-gray-200 hover:bg-gray-300"
            ]}
          >
            <%= state %>
          </button>
        <% end %>
      </div>

      <.table id="invoices" rows={@invoices} row_click={fn resource -> JS.navigate("/invoices/#{resource.id}") end}>
        <:col :let={resource} label="ID"><%= resource.id %></:col>
        <:col :let={resource} label="Number"><%= resource.number %></:col>
        <:col :let={resource} label="Amount"><%= resource.amount %></:col>
        <:col :let={resource} label="DueDate"><%= resource.due_date %></:col>

        <:col :let={resource} label="State">
          <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", state_color(resource.state)]}>
            <%= resource.state %>
          </span>
        </:col>
        <:col :let={resource} label="Created"><%= resource.inserted_at %></:col>

        <:action :let={resource}>
          <div class="sr-only">
            <.link navigate={"/invoices/#{resource.id}"}>Show</.link>
          </div>
          <.link patch={"/invoices/#{resource.id}/edit"}>Edit</.link>
        </:action>
        <:action :let={resource}>
          <.link phx-click={JS.push("delete", value: %{id: resource.id})} data-confirm="Are you sure?">
            Delete
          </.link>
        </:action>
      </.table>
    </div>
    """
  end

  defp list_invoices(opts \\ []) do
    query = Invoice

    query = case opts[:state] do
      nil -> query
      state -> from(q in query, where: q.state == ^state)
    end

    query
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  defp get_resource!(id), do: Repo.get!(Invoice, id)

  defp state_color(state) do
    case state do
      "draft" -> "bg-blue-100 text-blue-800"
      "sent" -> "bg-yellow-100 text-yellow-800"
      "paid" -> "bg-green-100 text-green-800"
      "void" -> "bg-gray-100 text-gray-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
