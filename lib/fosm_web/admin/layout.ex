if Code.ensure_loaded?(Phoenix.LiveView) or Code.ensure_loaded?(Phoenix.Component) do
defmodule FosmWeb.Admin.Layout do
  @moduledoc """
  Admin layout component with sidebar navigation.
  """

  use Phoenix.Component

  @nav_items [
    %{path: "/fosm/admin", icon: "home", label: "Dashboard"},
    %{path: "/fosm/admin/transitions", icon: "activity", label: "Transitions"},
    %{path: "/fosm/admin/roles", icon: "shield", label: "Roles"},
    %{path: "/fosm/admin/webhooks", icon: "webhook", label: "Webhooks"},
    %{path: "/fosm/admin/settings", icon: "settings", label: "Settings"}
  ]

  def admin_layout(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-100 flex">
      <!-- Sidebar -->
      <aside class="w-64 bg-gray-900 text-white flex-shrink-0">
        <div class="p-4 border-b border-gray-800">
          <h1 class="text-lg font-semibold flex items-center gap-2">
            <span class="w-8 h-8 bg-blue-500 rounded flex items-center justify-center text-sm font-bold">
              F
            </span>
            FOSM Admin
          </h1>
        </div>

        <nav class="p-4 space-y-1">
          <%= for item <- @nav_items do %>
            <.nav_link
              path={item.path}
              icon={item.icon}
              label={item.label}
              active={@current_path == item.path}
            />
          <% end %>
        </nav>

        <div class="mt-auto p-4 border-t border-gray-800">
          <div class="text-xs text-gray-400">
            <p>FOSM Phoenix</p>
          </div>
        </div>
      </aside>

      <!-- Main Content -->
      <main class="flex-1 overflow-y-auto">
        <div class="p-6">
          <%= render_slot(@inner_content) %>
        </div>
      </main>
    </div>
    """
  end

  defp nav_link(assigns) do
    ~H"""
    <a
      href={@path}
      class={[
        "flex items-center gap-3 px-3 py-2 rounded text-sm transition-colors",
        if(@active, do: "bg-blue-600 text-white", else: "text-gray-300 hover:bg-gray-800 hover:text-white")
      ]}
    >
      <.icon name={@icon} class="w-4 h-4" />
      <span><%= @label %></span>
    </a>
    """
  end

  defp icon(%{name: name} = assigns) do
    # Simple SVG icons - in a real app you might use Heroicons or similar
    case name do
      "home" ->
        ~H"""
        <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" />
        </svg>
        """

      "activity" ->
        ~H"""
        <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        </svg>
        """

      "shield" ->
        ~H"""
        <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
        </svg>
        """

      "webhook" ->
        ~H"""
        <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
        </svg>
        """

      "settings" ->
        ~H"""
        <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
        </svg>
        """

      _ ->
        ~H"""
        <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        """
    end
  end
end
end
