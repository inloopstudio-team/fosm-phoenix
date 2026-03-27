if Code.ensure_loaded?(Phoenix.LiveView) or Code.ensure_loaded?(Phoenix.Component) do
defmodule FosmWeb.Admin.AppLive do
  @moduledoc """
  App detail LiveView for viewing and managing a specific FOSM application.
  
  Shows:
  - State machine lifecycle visualization
  - Records list with state filters
  - Recent transitions
  - Statistics
  """

  use FosmWeb, :live_view
  import FosmWeb.Admin.Components
  alias Fosm.Repo

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Fosm.Registry.lookup(slug) do
      {:ok, module} ->
        lifecycle = module.fosm_lifecycle()
        
        socket =
          socket
          |> assign(:slug, slug)
          |> assign(:module, module)
          |> assign(:lifecycle, lifecycle)
          |> assign(:page_title, "#{module_name(module)} - App Details")
          |> assign(:current_path, "/fosm/admin/apps/#{slug}")
          |> assign(:filters, %{"state" => "", "search" => ""})
        
        {:ok, socket, layout: {FosmWeb.Admin.Layout, :admin_layout}}
        
      :error ->
        {:ok, push_navigate(socket, to: ~p"/fosm/admin")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = String.to_integer(params["page"] || "1")
    state_filter = params["state"] || ""
    search = params["search"] || ""
    
    filters = %{"state" => state_filter, "search" => search}
    
    records = fetch_records(socket.assigns.module, filters, page)
    recent_transitions = fetch_recent_transitions(socket.assigns.module, 10)
    stats = compute_stats(socket.assigns.module)
    
    socket =
      socket
      |> assign(:page, page)
      |> assign(:filters, filters)
      |> assign(:records, records)
      |> assign(:recent_transitions, recent_transitions)
      |> assign(:stats, stats)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", %{"state" => state, "search" => search}, socket) do
    params = %{"state" => state, "search" => search, "page" => "1"}
    
    {:noreply, push_patch(socket, to: ~p"/fosm/admin/apps/#{socket.assigns.slug}?#{params}")}
  end

  @impl true
  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/fosm/admin/apps/#{socket.assigns.slug}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div>
          <.link navigate={~p"/fosm/admin"} class="text-sm text-blue-600 hover:underline">
            ← Back to Dashboard
          </.link>
          <h1 class="text-2xl font-bold text-gray-900 mt-2"><%= module_name(@module) %></h1>
          <p class="text-sm text-gray-500"><%= @module.__schema__(:source) %></p>
        </div>
        <.badge variant="info"><%= @stats.total %> records</.badge>
      </div>

      <!-- Stats Cards -->
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <.card>
          <p class="text-sm text-gray-500">Total Records</p>
          <p class="text-2xl font-bold text-gray-900"><%= @stats.total %></p>
        </.card>
        
        <.card>
          <p class="text-sm text-gray-500">Terminal States</p>
          <p class="text-2xl font-bold text-purple-600"><%= @stats.terminal_count %></p>
        </.card>
        
        <.card>
          <p class="text-sm text-gray-500">In Progress</p>
          <p class="text-2xl font-bold text-blue-600"><%= @stats.in_progress %></p>
        </.card>
        
        <.card>
          <p class="text-sm text-gray-500">Transitions (24h)</p>
          <p class="text-2xl font-bold text-green-600"><%= @stats.transitions_24h %></p>
        </.card>
      </div>

      <!-- State Machine Diagram Placeholder -->
      <.card>
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Lifecycle States</h3>
        <div class="flex flex-wrap gap-2">
          <%= for state <- @lifecycle.states do %>
            <.badge variant={if state.terminal, do: "terminal", else: "default"}>
              <%= state.name %>
              <%= if state.initial do %>
                <span class="ml-1 text-xs">(initial)</span>
              <% end %>
            </.badge>
          <% end %>
        </div>
        
        <div class="mt-4 pt-4 border-t border-gray-200">
          <h4 class="text-sm font-medium text-gray-700 mb-2">Available Events</h4>
          <div class="space-y-2">
            <%= for event <- @lifecycle.events do %>
              <div class="flex items-center gap-2 text-sm">
                <span class="font-medium text-blue-600"><%= event.name %></span>
                <span class="text-gray-400">→</span>
                <span class="text-gray-600">
                  <%= event.from_states |> Enum.map(&to_string/1) |> Enum.join(", ") %>
                  → <%= event.to_state %>
                </span>
              </div>
            <% end %>
          </div>
        </div>
      </.card>

      <!-- Records Filter -->
      <.card>
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900">Records</h3>
          
          <form phx-change="filter" class="flex gap-2">
            <select name="state" class="rounded border-gray-300 text-sm">
              <option value="">All States</option>
              <%= for state <- @lifecycle.states do %>
                <option value={state.name} selected={@filters["state"] == to_string(state.name)}>
                  <%= state.name %>
                </option>
              <% end %>
            </select>
            
            <input
              type="text"
              name="search"
              value={@filters["search"]}
              placeholder="Search..."
              class="rounded border-gray-300 text-sm"
            />
            
            <button type="button" phx-click="clear_filters" class="text-sm text-gray-500 hover:text-gray-700">
              Clear
            </button>
          </form>
        </div>

        <.table>
          <.table_header>
            <.table_header_cell>ID</.table_header_cell>
            <.table_header_cell>State</.table_header_cell>
            <.table_header_cell>Created</.table_header_cell>
            <.table_header_cell>Updated</.table_header_cell>
            <.table_header_cell>Actions</.table_header_cell>
          </.table_header>
          <.table_body>
            <%= for record <- @records.entries do %>
              <.table_row>
                <.table_cell><%= record.id %></.table_cell>
                <.table_cell>
                  <.badge variant={state_variant(record.state, @lifecycle)}>
                    <%= record.state %>
                  </.badge>
                </.table_cell>
                <.table_cell><%= format_datetime(record.inserted_at) %></.table_cell>
                <.table_cell><%= format_datetime(record.updated_at) %></.table_cell>
                <.table_cell>
                  <.link
                    navigate={~p"/fosm/admin/transitions?model=#{@module.__schema__(:source)}&record_id=#{record.id}"}
                    class="text-sm text-blue-600 hover:underline"
                  >
                    View Transitions
                  </.link>
                </.table_cell>
              </.table_row>
            <% end %>
          </.table_body>
        </.table>

        <.pagination
          page={@records}
          path={~p"/fosm/admin/apps/#{@slug}"}
          params={@filters}
        />
      </.card>

      <!-- Recent Transitions -->
      <.card>
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-semibold text-gray-900">Recent Transitions</h3>
          <.link navigate={~p"/fosm/admin/transitions?model=#{@module.__schema__(:source)}"} class="text-sm text-blue-600 hover:underline">
            View All
          </.link>
        </div>
        
        <%= if @recent_transitions == [] do %>
          <p class="text-sm text-gray-500">No transitions yet.</p>
        <% else %>
          <div class="space-y-2">
            <%= for t <- @recent_transitions do %>
              <div class="flex items-center justify-between py-2 border-b border-gray-100 last:border-0">
                <div class="flex items-center gap-2 text-sm">
                  <span class="font-medium"><%= t.event_name %></span>
                  <span class="text-gray-400">on record #<%= t.record_id %></span>
                  <span class="text-xs bg-gray-100 px-2 py-0.5 rounded"><%= t.from_state %> → <%= t.to_state %></span>
                </div>
                <span class="text-xs text-gray-400"><%= format_relative(t.created_at) %></span>
              </div>
            <% end %>
          </div>
        <% end %>
      </.card>
    </div>
    """
  end

  # Private functions

  defp module_name(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp fetch_records(module, filters, page) do
    import Ecto.Query
    
    query = from(r in module)
    
    query = 
      case filters["state"] do
        "" -> query
        nil -> query
        state -> where(query, state: ^state)
      end
    
    query = 
      case filters["search"] do
        "" -> query
        nil -> query
        search -> 
          # Generic search - can be customized per module
          if :name in module.__schema__(:fields) do
            where(query, [r], ilike(r.name, ^"%#{search}%"))
          else
            query
          end
      end
    
    query
    |> order_by([r], desc: r.inserted_at)
    |> Repo.paginate(page: page, page_size: 25)
  end

  defp fetch_recent_transitions(module, limit) do
    import Ecto.Query
    
    from(t in Fosm.TransitionLog,
      where: t.record_type == ^module.__schema__(:source),
      order_by: [desc: t.created_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  defp compute_stats(module) do
    import Ecto.Query
    
    total = Repo.aggregate(from(r in module), :count, :id)
    
    lifecycle = module.fosm_lifecycle()
    terminal_states = Enum.map(lifecycle.terminal_states(), &to_string/1)
    
    terminal_count =
      from(r in module, where: r.state in ^terminal_states)
      |> Repo.aggregate(:count, :id)
    
    transitions_24h =
      from(t in Fosm.TransitionLog,
        where: t.record_type == ^module.__schema__(:source),
        where: t.created_at > ago(1, "day")
      )
      |> Repo.aggregate(:count, :id)
    
    %{
      total: total,
      terminal_count: terminal_count,
      in_progress: total - terminal_count,
      transitions_24h: transitions_24h || 0
    }
  end

  defp state_variant(state, lifecycle) do
    cond do
      lifecycle.terminal_states() |> Enum.map(&to_string/1) |> Enum.member?(state) ->
        "terminal"
      lifecycle.initial_state() == state ->
        "info"
      true ->
        "default"
    end
  end

  defp format_datetime(nil), do: "N/A"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
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
end
