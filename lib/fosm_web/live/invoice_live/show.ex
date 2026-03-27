defmodule FosmWeb.Live.InvoiceLive.Show do
  @moduledoc """
  LiveView for showing Invoice details.
  """

  use FosmWeb, :live_view

  alias Fosm.Invoice
  alias Fosm.Repo


  @impl true
  def mount(%{"id" => id}, _session, socket) do
    resource = get_resource!(id)

    {:ok, assign(socket,
      page_title: "Invoice #{resource.id}",
      resource: resource,
      available_events: Invoice.available_events(resource),
      transition_history: get_transition_history(resource),
      firing_event: nil,
      event_result: nil
    )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, _params) do
    assign(socket, :page_title, "Edit Invoice")
  end

  defp apply_action(socket, :show, _params) do
    assign(socket, :page_title, "Invoice")
  end

  @impl true
  def handle_event("fire_event", %{"event" => event_name}, socket) do
    resource = socket.assigns.resource
    event = String.to_atom(event_name)
    actor = socket.assigns[:current_user] || :system

    socket = assign(socket, firing_event: event_name)

    case Invoice.fire!(resource, event, actor: actor) do
      {:ok, updated} ->
        {:noreply, assign(socket,
          resource: updated,
          available_events: Invoice.available_events(updated),
          transition_history: get_transition_history(updated),
          firing_event: nil,
          event_result: %{success: true, event: event_name}
        )}

      {:error, reason} ->
        {:noreply, assign(socket,
          firing_event: nil,
          event_result: %{success: false, error: format_error(reason)}
        )}
    end
  end

  def handle_event("dismiss_result", _params, socket) do
    {:noreply, assign(socket, event_result: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-start">
        <div>
          <.link navigate="/invoices" class="text-sm text-gray-600 hover:underline">
            ← Back to invoices
          </.link>
          <h1 class="text-2xl font-bold mt-2">
            Invoice <%= @resource.id %>
          </h1>
          <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", state_color(@resource.state)]}>
            <%= @resource.state %>
          </span>
        </div>
        <.link patch={"/invoices/#{@resource.id}/edit"} class="btn-secondary">
          Edit
        </.link>
      </div>

      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Details</h2>
        <dl class="grid grid-cols-2 gap-4">
          <div>
            <dt class="text-sm text-gray-600">ID</dt>
            <dd class="font-medium"><%= @resource.id %></dd>
          </div>

          <div>
            <dt class="text-sm text-gray-600">Number</dt>
            <dd class="font-medium"><%= @resource.number %></dd>
          </div>

          <div>
            <dt class="text-sm text-gray-600">Amount</dt>
            <dd class="font-medium"><%= @resource.amount %></dd>
          </div>

          <div>
            <dt class="text-sm text-gray-600">DueDate</dt>
            <dd class="font-medium"><%= @resource.due_date %></dd>
          </div>
          <div>
            <dt class="text-sm text-gray-600">Created</dt>
            <dd class="font-medium"><%= @resource.inserted_at %></dd>
          </div>
          <div>
            <dt class="text-sm text-gray-600">Updated</dt>
            <dd class="font-medium"><%= @resource.updated_at %></dd>
          </div>
        </dl>
      </div>

      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Available Actions</h2>
        <%= if @available_events == [] do %>
          <p class="text-gray-600 italic">No events available from <%= @resource.state %> state.</p>
        <% else %>
          <div class="flex gap-2">
            <%= for event <- @available_events do %>
              <button
                phx-click="fire_event"
                phx-value-event={event}
                class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
              >
                <%= event %>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Transition History</h2>
        <%= if @transition_history == [] do %>
          <p class="text-gray-600 italic">No transitions recorded yet.</p>
        <% else %>
          <ul class="space-y-2">
            <%= for transition <- @transition_history do %>
              <li class="border-b pb-2">
                <%= transition.event_name %>: <%= transition.from_state %> → <%= transition.to_state %>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>

      <%= if @event_result do %>
        <div class={["p-4 rounded", if(@event_result.success, do: "bg-green-100", else: "bg-red-100")]}>
          <%= if @event_result.success do %>
            Event <%= @event_result.event %> completed successfully
          <% else %>
            Error: <%= @event_result.error %>
          <% end %>
          <button phx-click="dismiss_result" class="ml-2 text-sm underline">Dismiss</button>
        </div>
      <% end %>
    </div>
    """
  end

  defp get_resource!(id), do: Repo.get!(Invoice, id)

  defp get_transition_history(resource) do
    Fosm.TransitionLog
    |> Fosm.TransitionLog.for_record("invoices", resource.id)
    |> Fosm.TransitionLog.recent()
    |> Repo.all()
  end

  defp format_error(%Fosm.Errors.GuardFailed{guard: guard, reason: reason}) do
    "Guard '#{guard}' failed" <> if(reason, do: ": #{reason}", else: "")
  end

  defp format_error(%Fosm.Errors.TerminalState{}), do: "Terminal state - cannot transition"
  defp format_error(%Fosm.Errors.InvalidTransition{} = e), do: "Cannot #{e.event} from #{e.from}"
  defp format_error(%Fosm.Errors.AccessDenied{}), do: "Access denied"
  defp format_error(e), do: Exception.message(e)

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
