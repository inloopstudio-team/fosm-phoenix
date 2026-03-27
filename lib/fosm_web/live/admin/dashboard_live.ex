defmodule FosmWeb.Admin.DashboardLive do
  @moduledoc """
  Main dashboard LiveView for FOSM Admin.
  
  Displays all registered FOSM applications with statistics
  and quick navigation to app details.
  """

  use FosmWeb, :live_view
  import FosmWeb.Admin.Components

  @impl true
  def mount(_params, _session, socket) do
    apps = Fosm.Registry.all()
    
    apps_with_stats = Enum.map(apps, fn {slug, module} ->
      stats = compute_stats(module)
      {slug, module, stats}
    end)

    socket = 
      socket
      |> assign(:apps, apps_with_stats)
      |> assign(:page_title, "FOSM Dashboard")
      |> assign(:current_path, "/fosm/admin")

    {:ok, socket, layout: {FosmWeb.Admin.Layout, :admin_layout}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-gray-900">FOSM Dashboard</h1>
        <.badge variant="info"><%= length(@apps) %> Applications</.badge>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for {slug, module, stats} <- @apps do %>
          <.link navigate={~p"/fosm/admin/apps/#{slug}"} class="block group">
            <.card class="h-full group-hover:shadow-md transition-shadow">
              <div class="flex items-start justify-between mb-4">
                <div>
                  <h3 class="text-lg font-semibold text-gray-900"><%= module_name(module) %></h3>
                  <p class="text-sm text-gray-500 mt-1"><%= stats.total %> total records</p>
                </div>
                <.badge variant={if stats.terminal > 0, do: "terminal", else: "default"}>
                  <%= length(module.fosm_lifecycle().states) %> states
                </.badge>
              </div>
              
              <div class="space-y-2">
                <%= for {state, count} <- Enum.take(stats.state_distribution, 4) do %>
                  <div class="flex items-center justify-between text-sm">
                    <span class="text-gray-600"><%= state %></span>
                    <span class="font-medium text-gray-900"><%= count %></span>
                  </div>
                <% end %>
                <%= if map_size(stats.state_distribution) > 4 do %>
                  <p class="text-xs text-gray-400 mt-2">
                    +<%= map_size(stats.state_distribution) - 4 %> more states
                  </p>
                <% end %>
              </div>
              
              <%= if stats.stuck_count > 0 do %>
                <div class="mt-4 pt-4 border-t border-gray-100">
                  <.badge variant="warning"><%= stats.stuck_count %> potentially stuck</.badge>
                </div>
              <% end %>
            </.card>
          </.link>
        <% end %>
      </div>

      <%= if @apps == [] do %>
        <.card>
          <.alert type="info">
            <p class="text-sm">No FOSM applications registered yet.</p>
            <p class="text-xs mt-1">Use <code>Fosm.Registry.register/2</code> to register your state machine models.</p>
          </.alert>
        </.card>
      <% end %>
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

  defp compute_stats(module) do
    total = count_records(module)
    
    lifecycle = module.fosm_lifecycle()
    non_terminal_states = 
      lifecycle.states
      |> Enum.reject(& &1.terminal)
      |> Enum.map(&to_string(&1.name))
    
    stuck_count = count_stuck_records(module, non_terminal_states)
    
    %{
      total: total,
      state_distribution: state_distribution(module),
      terminal: count_in_states(module, lifecycle.terminal_states()),
      stuck_count: stuck_count
    }
  end

  defp count_records(module) do
    import Ecto.Query
    Fosm.Repo.aggregate(from(r in module), :count, :id)
  end

  defp count_in_states(module, states) do
    import Ecto.Query
    
    state_strings = Enum.map(states, &to_string/1)
    
    from(r in module, where: r.state in ^state_strings)
    |> Fosm.Repo.aggregate(:count, :id)
  end

  defp state_distribution(module) do
    import Ecto.Query
    
    from(r in module,
      group_by: r.state,
      select: {r.state, count(r.id)},
      order_by: [desc: count(r.id)]
    )
    |> Fosm.Repo.all()
    |> Map.new()
  end

  defp count_stuck_records(module, non_terminal_states, stale_days \\ 7) do
    import Ecto.Query
    
    candidates = 
      from(r in module, where: r.state in ^non_terminal_states)
      |> Fosm.Repo.all()
    
    return unless candidates != []
    
    candidate_ids = Enum.map(candidates, &to_string(&1.id))
    table_name = module.__schema__(:source)
    
    recently_active =
      from(t in Fosm.TransitionLog,
        where: t.record_type == ^table_name,
        where: t.record_id in ^candidate_ids,
        where: t.created_at > ago(^stale_days, "day"),
        select: t.record_id,
        distinct: true
      )
      |> Fosm.Repo.all()
      |> MapSet.new()
    
    candidates
    |> Enum.reject(fn r -> to_string(r.id) in recently_active end)
    |> length()
  end
end
