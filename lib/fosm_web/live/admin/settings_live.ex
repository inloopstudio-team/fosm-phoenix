defmodule FosmWeb.Admin.SettingsLive do
  @moduledoc """
  Settings page LiveView for FOSM configuration.
  
  Features:
  - Display LLM provider configuration status
  - Show current FOSM configuration
  - Display system health metrics
  """

  use FosmWeb, :live_view
  import FosmWeb.Admin.Components

  @llm_providers [
    %{name: "Anthropic (Claude)", env_key: "ANTHROPIC_API_KEY", prefix: "anthropic/"},
    %{name: "OpenAI", env_key: "OPENAI_API_KEY", prefix: "openai/"},
    %{name: "Google (Gemini)", env_key: "GEMINI_API_KEY", prefix: "gemini/"},
    %{name: "Cohere", env_key: "COHERE_API_KEY", prefix: "cohere/"},
    %{name: "Mistral", env_key: "MISTRAL_API_KEY", prefix: "mistral/"}
  ]

  @refresh_interval 30_000  # 30 seconds

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      schedule_refresh()
    end

    socket =
      socket
      |> assign(:page_title, "FOSM Settings")
      |> assign(:current_path, "/fosm/admin/settings")
      |> load_settings()

    {:ok, socket, layout: {FosmWeb.Admin.Layout, :admin_layout}}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_settings(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-gray-900">FOSM Settings</h1>
        <.badge variant="info">v<%= @config.version %></.badge>
      </div>

      <!-- LLM Providers -->
      <.card>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-gray-900">LLM Providers</h2>
          <span class="text-xs text-gray-400">Auto-refreshes every 30s</span>
        </div>
        
        <div class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 sm:rounded-lg">
          <table class="min-w-full divide-y divide-gray-300">
            <thead class="bg-gray-50">
              <tr>
                <th scope="col" class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-6">Provider</th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Environment Variable</th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Status</th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Prefix</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 bg-white">
              <%= for provider <- @providers do %>
                <tr>
                  <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-6">
                    <%= provider.name %>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500 font-mono">
                    <%= provider.env_key %>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm">
                    <%= if provider.configured do %>
                      <span class="inline-flex items-center rounded-full bg-green-100 px-2 py-1 text-xs font-medium text-green-700">
                        <svg class="mr-1.5 h-2 w-2 text-green-600" fill="currentColor" viewBox="0 0 8 8">
                          <circle cx="4" cy="4" r="3" />
                        </svg>
                        Configured
                      </span>
                    <% else %>
                      <span class="inline-flex items-center rounded-full bg-gray-100 px-2 py-1 text-xs font-medium text-gray-600">
                        <svg class="mr-1.5 h-2 w-2 text-gray-500" fill="currentColor" viewBox="0 0 8 8">
                          <circle cx="4" cy="4" r="3" />
                        </svg>
                        Not Configured
                      </span>
                    <% end %>
                  </td>
                  <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                    <code class="bg-gray-100 px-1 py-0.5 rounded text-xs"><%= provider.prefix %></code>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </.card>

      <!-- Configuration -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <.card>
          <h2 class="text-lg font-semibold text-gray-900 mb-4">FOSM Configuration</h2>
          <dl class="space-y-3">
            <div>
              <dt class="text-sm font-medium text-gray-500">Transition Log Strategy</dt>
              <dd class="mt-1 text-sm text-gray-900">
                <.badge variant={if @config.log_strategy == :async, do: "success", else: "default"}>
                  <%= @config.log_strategy %>
                </.badge>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Buffer Enabled</dt>
              <dd class="mt-1 text-sm text-gray-900">
                <%= if @config.buffer_enabled do %>
                  <span class="text-green-600">Yes</span>
                <% else %>
                  <span class="text-gray-500">No</span>
                <% end %>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Agent Sessions</dt>
              <dd class="mt-1 text-sm text-gray-900">
                <%= if @config.agent_sessions do %>
                  <span class="text-green-600">Enabled</span>
                <% else %>
                  <span class="text-gray-500">Disabled</span>
                <% end %>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Default Model</dt>
              <dd class="mt-1 text-sm text-gray-900 font-mono"><%= @config.default_model %></dd>
            </div>
          </dl>
        </.card>

        <.card>
          <h2 class="text-lg font-semibold text-gray-900 mb-4">System Health</h2>
          <dl class="space-y-3">
            <div>
              <dt class="text-sm font-medium text-gray-500">Registered Applications</dt>
              <dd class="mt-1 text-sm text-gray-900"><%= @health.app_count %> FOSM models</dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Total Transitions (24h)</dt>
              <dd class="mt-1 text-sm text-gray-900"><%= @health.transitions_24h %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Active Webhooks</dt>
              <dd class="mt-1 text-sm text-gray-900"><%= @health.active_webhooks %> / <%= @health.total_webhooks %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Role Assignments</dt>
              <dd class="mt-1 text-sm text-gray-900"><%= @health.role_assignments %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500">Pending Oban Jobs</dt>
              <dd class="mt-1 text-sm text-gray-900">
                <%= if @health.oban_available do %>
                  <%= @health.pending_jobs %> jobs
                <% else %>
                  <span class="text-gray-400">Oban not available</span>
                <% end %>
              </dd>
            </div>
          </dl>
        </.card>
      </div>

      <!-- Environment Variables -->
      <.card>
        <h2 class="text-lg font-semibold text-gray-900 mb-4">Environment Configuration</h2>
        <div class="bg-gray-900 rounded-lg p-4 overflow-x-auto">
          <pre class="text-sm text-green-400 font-mono"><code># Required for FOSM operation
DATABASE_URL=${DATABASE_URL:-"not set"}

# LLM Provider (at least one required for AI features)
<%= for provider <- @providers do %><%= provider.env_key %>=<%= if provider.configured, do: "[SET]", else: "[NOT SET]" %>
<% end %>

# Optional features
FOSM_LOG_STRATEGY=<%= System.get_env("FOSM_LOG_STRATEGY") || "async" %>
FOSM_ENABLE_AGENT=<%= System.get_env("FOSM_ENABLE_AGENT") || "true" %></code></pre>
        </div>
      </.card>
    </div>
    """
  end

  # Private functions

  defp load_settings(socket) do
    providers = 
      Enum.map(@llm_providers, fn p ->
        value = System.get_env(p.env_key)
        hint = 
          if value && String.length(value) > 8 do
            "#{String.length(value)} chars, starts with #{String.slice(value, 0, 4)}..."
          else
            nil
          end
        
        Map.merge(p, %{
          configured: value != nil and value != "",
          hint: hint
        })
      end)

    config = %{
      version: Application.spec(:fosm, :vsn) || "0.1.0",
      log_strategy: Application.get_env(:fosm, :transition_log_strategy, :async),
      buffer_enabled: Application.get_env(:fosm, :transition_log_strategy) == :buffered,
      agent_sessions: Application.get_env(:fosm, :enable_agent, true),
      default_model: Application.get_env(:fosm, :default_model, "anthropic/claude-sonnet-4-20250514")
    }

    health = compute_health_metrics()

    socket
    |> assign(:providers, providers)
    |> assign(:config, config)
    |> assign(:health, health)
  end

  defp compute_health_metrics do
    import Ecto.Query
    
    apps = length(Fosm.Registry.all())
    
    transitions_24h =
      if Code.ensure_loaded?(Fosm.TransitionLog) do
        from(t in Fosm.TransitionLog, where: t.created_at > ago(1, "day"))
        |> Fosm.Repo.aggregate(:count, :id) || 0
      else
        0
      end
    
    webhooks = 
      if Code.ensure_loaded?(Fosm.WebhookSubscription) do
        {
          Fosm.Repo.aggregate(from(w in Fosm.WebhookSubscription, where: w.active == true), :count, :id) || 0,
          Fosm.Repo.aggregate(Fosm.WebhookSubscription, :count, :id) || 0
        }
      else
        {0, 0}
      end
    
    role_assignments =
      if Code.ensure_loaded?(Fosm.RoleAssignment) do
        Fosm.Repo.aggregate(Fosm.RoleAssignment, :count, :id) || 0
      else
        0
      end

    oban_available = Code.ensure_loaded?(Oban)
    
    pending_jobs =
      if oban_available do
        try do
          Oban.Job
          |> where([j], j.state in ["available", "scheduled", "executing"])
          |> Fosm.Repo.aggregate(:count, :id) || 0
        rescue
          _ -> 0
        end
      else
        0
      end

    %{
      app_count: apps,
      transitions_24h: transitions_24h,
      active_webhooks: elem(webhooks, 0),
      total_webhooks: elem(webhooks, 1),
      role_assignments: role_assignments,
      oban_available: oban_available,
      pending_jobs: pending_jobs
    }
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
