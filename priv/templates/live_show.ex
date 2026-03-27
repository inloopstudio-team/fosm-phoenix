defmodule <%= @module %> do
  @moduledoc """
  LiveView for showing <%= @resource_name %> details.
  """

  use <%= @web_module %>, :live_view

  alias <%= @schema_module %>
  alias <%= @app_module %>.Repo

  import FosmWeb.CoreComponents

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    resource = get_resource!(id)

    {:ok, assign(socket,
      page_title: "<%= @resource_name %> \#{resource.id}",
      resource: resource,
      available_events: <%= @schema_module %>.available_events(resource),
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
    assign(socket, :page_title, "Edit <%= @resource_name %>")
  end

  defp apply_action(socket, :show, _params) do
    assign(socket, :page_title, "<%= @resource_name %>")
  end

  @impl true
  def handle_event("fire_event", %{"event" => event_name}, socket) do
    resource = socket.assigns.resource
    event = String.to_atom(event_name)
    actor = socket.assigns[:current_user] || :system

    socket = assign(socket, firing_event: event_name)

    case <%= @schema_module %>.fire!(resource, event, actor: actor) do
      {:ok, updated} ->
        {:noreply, assign(socket,
          resource: updated,
          available_events: <%= @schema_module %>.available_events(updated),
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
      <%!-- Header --%>
      <div class="flex justify-between items-start">
        <div>
          <.link navigate={~p"/<%= @plural %>"} class="text-sm text-gray-600 hover:underline">
            ← Back to <%= @plural %>
          </.link>
          <h1 class="text-2xl font-bold mt-2">
            <%= @resource_name %> \#{@resource.id}
          </h1>
          <.badge color={state_color(@resource.state)} class="mt-2">
            \#{@resource.state}
          </.badge>
        </div>
        <.link patch={~p"/<%= @plural %>/\#{@resource.id}/edit"} class="btn-secondary">
          Edit
        </.link>
      </div>

      <%!-- Event Result --%>
      <%= if @event_result do %>
        <div class={[
          "p-4 rounded-lg",
          @event_result.success && "bg-green-100 text-green-800",
          !@event_result.success && "bg-red-100 text-red-800"
        ]}>
          <div class="flex justify-between items-start">
            <div>
              <%= if @event_result.success do %>
                <p>✅ Event <strong><%= @event_result.event %></strong> fired successfully!</p>
                <p class="text-sm mt-1">New state: <strong>\#{@resource.state}</strong></p>
              <% else %>
                <p>❌ Event failed: <%= @event_result.error %></p>
              <% end %>
            </div>
            <button phx-click="dismiss_result" class="text-sm underline">Dismiss</button>
          </div>
        </div>
      <% end %>

      <%!-- Details --%>
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Details</h2>
        <dl class="grid grid-cols-2 gap-4">
          <div>
            <dt class="text-sm text-gray-600">ID</dt>
            <dd class="font-medium">\#{@resource.id}</dd>
          </div>
<%= for {name, _type} <- @fields do %>
          <div>
            <dt class="text-sm text-gray-600"><%= name |> to_string() |> Macro.camelize() %></dt>
            <dd class="font-medium">\#{@resource.<%= name %>}</dd>
          </div>
<% end %>          <div>
            <dt class="text-sm text-gray-600">Created</dt>
            <dd class="font-medium">\#{@resource.inserted_at}</dd>
          </div>
          <div>
            <dt class="text-sm text-gray-600">Updated</dt>
            <dd class="font-medium">\#{@resource.updated_at}</dd>
          </div>
        </dl>
      </div>

      <%!-- Available Events --%>
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Available Actions</h2>
        <%= if @available_events == [] do %>
          <p class="text-gray-600 italic">No events available from \#{@resource.state} state.</p>
        <% else %>
          <div class="flex flex-wrap gap-2">
            <%= for event <- @available_events do %>
              <button
                phx-click="fire_event"
                phx-value-event={event}
                disabled={@firing_event == event}
                class="btn-primary"
              >
                <%= if @firing_event == event do %>
                  Firing...
                <% else %>
                  <%= event |> to_string() |> String.capitalize() %>
                <% end %>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Transition History --%>
      <div class="bg-white rounded-lg shadow p-6">
        <h2 class="text-lg font-semibold mb-4">Transition History</h2>
        <%= if @transition_history == [] do %>
          <p class="text-gray-600 italic">No transitions recorded yet.</p>
        <% else %>
          <.table id="transitions" rows={@transition_history}>
            <:col :let={t} label="Event">\#{t.event_name}</:col>
            <:col :let={t} label="From">\#{t.from_state}</:col>
            <:col :let={t} label="To">\#{t.to_state}</:col>
            <:col :let={t} label="Actor">\#{t.actor_label || t.actor_type}</:col>
            <:col :let={t} label="Time">\#{t.created_at}</:col>
          </.table>
        <% end %>
      </div>
    </div>

    <%!-- Edit Modal --%>
    <.modal :if={@live_action == :edit} id="<%= @resource_path %>-modal" show on_cancel={JS.patch(~p"/<%= @plural %>/\#{@resource.id}")}>
      <.live_component
        module={<%= @live_form_module %>}
        id={@resource.id}
        title={@page_title}
        action={@live_action}
        resource={@resource}
        patch={~p"/<%= @plural %>/\#{@resource.id}"}
      />
    </.modal>
    """
  end

  defp get_resource!(id), do: Repo.get!(<%= @schema_module %>, id)

  defp get_transition_history(resource) do
    Fosm.TransitionLog
    |> Fosm.TransitionLog.for_record("<%= @plural %>", resource.id)
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
<%= for state <- @states do %>      "<%= state.name %>" -> <%= if state.type == :initial, do: ":info", else: if(state.type == :terminal, do: ":success", else: ":warning") %>
<% end %>      _ -> :gray
    end
  end
end
