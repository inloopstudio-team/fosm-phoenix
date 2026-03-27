defmodule FosmWeb.Admin.TransitionsLive do
  @moduledoc """
  Transitions LiveView with filtering and pagination.
  
  Features:
  - Filter by model, event, actor type
  - Search by record ID
  - URL-based filters (persistable)
  - Scrivener pagination
  """

  use FosmWeb, :live_view
  import FosmWeb.Admin.Components
  alias Fosm.{Repo, TransitionLog}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Transition Log")
      |> assign(:current_path, "/fosm/admin/transitions")
      |> assign(:available_models, available_models())
    
    {:ok, socket, layout: {FosmWeb.Admin.Layout, :admin_layout}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = String.to_integer(params["page"] || "1")
    filters = parse_filters(params)
    
    transitions = fetch_transitions(filters, page)
    
    socket =
      socket
      |> assign(:page, page)
      |> assign(:filters, filters)
      |> assign(:transitions, transitions)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_filters", params, socket) do
    # Merge with existing filters, excluding empty values
    new_filters =
      params
      |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" end)
      |> Map.new()
    
    # Reset to page 1 when filters change
    query_params = Map.merge(new_filters, %{"page" => "1"})
    
    {:noreply, push_patch(socket, to: ~p"/fosm/admin/transitions?#{query_params}")}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/fosm/admin/transitions")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-gray-900">Transition Log</h1>
        <.badge variant="info"><%= @transitions.total_entries %> entries</.badge>
      </div>

      <!-- Filters -->
      <.card class="bg-gray-50">
        <form phx-change="apply_filters" class="grid grid-cols-1 md:grid-cols-5 gap-4">
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Model</label>
            <select name="model" class="w-full rounded border-gray-300 text-sm">
              <option value="">All Models</option>
              <%= for {slug, module} <- @available_models do %>
                <option 
                  value={module.__schema__(:source)} 
                  selected={@filters["model"] == module.__schema__(:source)}
                >
                  <%= module.__schema__(:source) %>
                </option>
              <% end %>
            </select>
          </div>
          
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Event</label>
            <input
              type="text"
              name="event"
              value={@filters["event"]}
              placeholder="Event name..."
              class="w-full rounded border-gray-300 text-sm"
            />
          </div>
          
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Actor Type</label>
            <select name="actor" class="w-full rounded border-gray-300 text-sm">
              <option value="">All Actors</option>
              <option value="human" selected={@filters["actor"] == "human"}>Human</option>
              <option value="agent" selected={@filters["actor"] == "agent"}>AI Agent</option>
              <option value="system" selected={@filters["actor"] == "system"}>System</option>
            </select>
          </div>
          
          <div>
            <label class="block text-xs font-medium text-gray-700 mb-1">Record ID</label>
            <input
              type="text"
              name="record_id"
              value={@filters["record_id"]}
              placeholder="ID..."
              class="w-full rounded border-gray-300 text-sm"
            />
          </div>
          
          <div class="flex items-end">
            <button
              type="button"
              phx-click="clear_filters"
              class="text-sm text-gray-500 hover:text-gray-700"
            >
              Clear All
            </button>
          </div>
        </form>
      </.card>

      <!-- Transitions Table -->
      <.card>
        <%= if @transitions.entries == [] do %>
          <.alert type="info">
            <p>No transitions found matching the current filters.</p>
          </.alert>
        <% else %>
          <.table>
            <.table_header>
              <.table_header_cell>Time</.table_header_cell>
              <.table_header_cell>Model</.table_header_cell>
              <.table_header_cell>Record</.table_header_cell>
              <.table_header_cell>Event</.table_header_cell>
              <.table_header_cell>Transition</.table_header_cell>
              <.table_header_cell>Actor</.table_header_cell>
              <.table_header_cell>Duration</.table_header_cell>
            </.table_header>
            <.table_body>
              <%= for t <- @transitions.entries do %>
                <.table_row>
                  <.table_cell>
                    <span class="text-xs" title={format_datetime(t.created_at)}>
                      <%= format_relative(t.created_at) %>
                    </span>
                  </.table_cell>
                  <.table_cell>
                    <span class="text-xs font-medium"><%= t.record_type %></span>
                  </.table_cell>
                  <.table_cell>
                    <span class="text-xs font-mono"><%= t.record_id %></span>
                  </.table_cell>
                  <.table_cell>
                    <span class="text-sm font-medium text-blue-600"><%= t.event_name %></span>
                  </.table_cell>
                  <.table_cell>
                    <div class="flex items-center gap-1 text-xs">
                      <.badge variant="default"><%= t.from_state %></.badge>
                      <span class="text-gray-400">→</span>
                      <.badge variant={if t.terminal_state, do: "terminal", else: "success"}>
                        <%= t.to_state %>
                      </.badge>
                    </div>
                  </.table_cell>
                  <.table_cell>
                    <%= render_actor(t) %>
                  </.table_cell>
                  <.table_cell>
                    <%= if t.duration_ms do %>
                      <span class="text-xs text-gray-500"><%= t.duration_ms %>ms</span>
                    <% else %>
                      <span class="text-xs text-gray-400">-</span>
                    <% end %>
                  </.table_cell>
                </.table_row>
              <% end %>
            </.table_body>
          </.table>

          <.pagination
            page={@transitions}
            path={~p"/fosm/admin/transitions"}
            params={@filters}
          />
        <% end %>
      </.card>
    </div>
    """
  end

  # Private functions

  defp available_models do
    Fosm.Registry.all()
  end

  defp parse_filters(params) do
    %{
      "model" => params["model"] || "",
      "event" => params["event"] || "",
      "actor" => params["actor"] || "",
      "record_id" => params["record_id"] || ""
    }
  end

  defp fetch_transitions(filters, page) do
    import Ecto.Query
    
    query = from(t in TransitionLog)
    
    query = maybe_filter_by_model(query, filters["model"])
    query = maybe_filter_by_event(query, filters["event"])
    query = maybe_filter_by_actor(query, filters["actor"])
    query = maybe_filter_by_record_id(query, filters["record_id"])
    
    query
    |> order_by([t], desc: t.created_at)
    |> Repo.paginate(page: page, page_size: 50)
  end

  defp maybe_filter_by_model(query, ""), do: query
  defp maybe_filter_by_model(query, nil), do: query
  defp maybe_filter_by_model(query, model) do
    import Ecto.Query
    where(query, record_type: ^model)
  end

  defp maybe_filter_by_event(query, ""), do: query
  defp maybe_filter_by_event(query, nil), do: query
  defp maybe_filter_by_event(query, event) do
    import Ecto.Query
    where(query, event_name: ^event)
  end

  defp maybe_filter_by_actor(query, ""), do: query
  defp maybe_filter_by_actor(query, nil), do: query
  defp maybe_filter_by_actor(query, "human") do
    import Ecto.Query
    where(query, [t], t.actor_type != "symbol" and not is_nil(t.actor_id))
  end
  defp maybe_filter_by_actor(query, "agent") do
    import Ecto.Query
    where(query, [t], t.actor_type == "symbol" and t.actor_label == "agent")
  end
  defp maybe_filter_by_actor(query, "system") do
    import Ecto.Query
    where(query, [t], t.actor_type == "symbol" and t.actor_label != "agent")
  end
  defp maybe_filter_by_actor(query, _), do: query

  defp maybe_filter_by_record_id(query, ""), do: query
  defp maybe_filter_by_record_id(query, nil), do: query
  defp maybe_filter_by_record_id(query, record_id) do
    import Ecto.Query
    where(query, record_id: ^to_string(record_id))
  end

  defp render_actor(transition) do
    assigns = %{transition: transition}
    
    cond do
      TransitionLog.by_agent?(transition) ->
        ~H"""
        <span class="inline-flex items-center gap-1">
          <svg class="w-3 h-3 text-purple-500" fill="currentColor" viewBox="0 0 20 20"><path d="M10 12a2 2 0 100-4 2 2 0 000 4z"/><path fill-rule="evenodd" d="M.458 10C1.732 5.943 5.522 3 10 3s8.268 2.943 9.542 7c-1.274 4.057-5.064 7-9.542 7S1.732 14.057.458 10zM14 10a4 4 0 11-8 0 4 4 0 018 0z" clip-rule="evenodd"/></svg>
          <span class="text-xs text-purple-600">Agent</span>
        </span>
        """
        
      TransitionLog.by_system?(transition) ->
        ~H"""
        <span class="inline-flex items-center gap-1">
          <svg class="w-3 h-3 text-gray-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M11.3 1.046A1 1 0 0112 2v5h4a1 1 0 01.82 1.573l-7 10A1 1 0 018 18v-5H4a1 1 0 01-.82-1.573l7-10a1 1 0 011.12-.38z" clip-rule="evenodd"/></svg>
          <span class="text-xs text-gray-500">System</span>
        </span>
        """
        
      true ->
        ~H"""
        <span class="inline-flex items-center gap-1">
          <svg class="w-3 h-3 text-blue-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 9a3 3 0 100-6 3 3 0 000 6zm-7 9a7 7 0 1114 0H3z" clip-rule="evenodd"/></svg>
          <span class="text-xs text-blue-600"><%= @transition.actor_type %>:<%= @transition.actor_id %></span>
        </span>
        """
    end
  end

  defp format_datetime(nil), do: "N/A"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  defp format_relative(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604800 -> "#{div(diff, 86400)}d ago"
      true -> format_datetime(datetime)
    end
  end
end
