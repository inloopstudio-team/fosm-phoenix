defmodule FosmWeb.Admin.Components do
  @moduledoc """
  Reusable UI components for the FOSM Admin interface.
  """

  use Phoenix.Component
  import Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  # Pagination component using Scrivener
  attr :page, :any, required: true
  attr :path, :string, required: true
  attr :params, :map, default: %{}

  def pagination(assigns) do
    ~H"""
    <div class="flex items-center justify-between border-t border-gray-200 bg-white px-4 py-3 sm:px-6 mt-4">
      <div class="flex flex-1 justify-between sm:hidden">
        <.link
          :if={@page.page_number > 1}
          navigate={pagination_path(@path, @page.page_number - 1, @params)}
          class="relative inline-flex items-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          Previous
        </.link>
        <.link
          :if={@page.page_number < @page.total_pages}
          navigate={pagination_path(@path, @page.page_number + 1, @params)}
          class="relative ml-3 inline-flex items-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50"
        >
          Next
        </.link>
      </div>
      
      <div class="hidden sm:flex sm:flex-1 sm:items-center sm:justify-between">
        <div>
          <p class="text-sm text-gray-700">
            Showing <span class="font-medium"><%= (@page.page_number - 1) * @page.page_size + 1 %></span>
            to <span class="font-medium"><%= min(@page.page_number * @page.page_size, @page.total_entries) %></span>
            of <span class="font-medium"><%= @page.total_entries %></span> results
          </p>
        </div>
        
        <div>
          <nav class="isolate inline-flex -space-x-px rounded-md shadow-sm" aria-label="Pagination">
            <.link
              :if={@page.page_number > 1}
              navigate={pagination_path(@path, @page.page_number - 1, @params)}
              class="relative inline-flex items-center rounded-l-md px-2 py-2 text-gray-400 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:z-20 focus:outline-offset-0"
            >
              <span class="sr-only">Previous</span>
              <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fill-rule="evenodd" d="M12.79 5.23a.75.75 0 01-.02 1.06L8.832 10l3.938 3.71a.75.75 0 11-1.04 1.08l-4.5-4.25a.75.75 0 010-1.08l4.5-4.25a.75.75 0 011.06.02z" clip-rule="evenodd" />
              </svg>
            </.link>
            
            <%= for page_num <- page_numbers(@page) do %>
              <%= if page_num == :ellipsis do %>
                <span class="relative inline-flex items-center px-4 py-2 text-sm font-semibold text-gray-700 ring-1 ring-inset ring-gray-300 focus:outline-offset-0">
                  ...
                </span>
              <% else %>
                <.link
                  navigate={pagination_path(@path, page_num, @params)}
                  class={[
                    "relative inline-flex items-center px-4 py-2 text-sm font-semibold focus:z-20 focus:outline-offset-0",
                    if(page_num == @page.page_number,
                      do: "z-10 bg-blue-600 text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600",
                      else: "text-gray-900 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:outline-offset-0"
                    )
                  ]}
                >
                  <%= page_num %>
                </.link>
              <% end %>
            <% end %>
            
            <.link
              :if={@page.page_number < @page.total_pages}
              navigate={pagination_path(@path, @page.page_number + 1, @params)}
              class="relative inline-flex items-center rounded-r-md px-2 py-2 text-gray-400 ring-1 ring-inset ring-gray-300 hover:bg-gray-50 focus:z-20 focus:outline-offset-0"
            >
              <span class="sr-only">Next</span>
              <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
              </svg>
            </.link>
          </nav>
        </div>
      </div>
    </div>
    """
  end

  defp pagination_path(base_path, page, params) do
    params = Map.merge(params, %{"page" => page})
    query = URI.encode_query(params)
    "#{base_path}?#{query}"
  end

  defp page_numbers(page) do
    total = page.total_pages
    current = page.page_number
    
    cond do
      total <= 7 ->
        Enum.to_list(1..total)
        
      current <= 4 ->
        [1, 2, 3, 4, 5, :ellipsis, total]
        
      current >= total - 3 ->
        [1, :ellipsis, total - 4, total - 3, total - 2, total - 1, total]
        
      true ->
        [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
    end
  end

  # Filter component for transitions
  attr :filters, :map, required: true
  attr :target, :any, required: true

  def filter_form(assigns) do
    ~H"""
    <form phx-change="apply_filters" phx-target={@target} class="bg-white p-4 rounded border mb-4">
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Model</label>
          <select name="model" class="w-full rounded border-gray-300 text-sm">
            <option value="">All Models</option>
            <%= for {slug, module} <- Fosm.Registry.all() do %>
              <option value={module.__schema__(:source)} selected={@filters["model"] == module.__schema__(:source)}>
                <%= module.__schema__(:source) %>
              </option>
            <% end %>
          </select>
        </div>
        
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Event</label>
          <input
            type="text"
            name="event"
            value={@filters["event"]}
            placeholder="Event name..."
            class="w-full rounded border-gray-300 text-sm"
          />
        </div>
        
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Actor</label>
          <select name="actor" class="w-full rounded border-gray-300 text-sm">
            <option value="">All Actors</option>
            <option value="human" selected={@filters["actor"] == "human"}>Human</option>
            <option value="agent" selected={@filters["actor"] == "agent"}>AI Agent</option>
            <option value="system" selected={@filters["actor"] == "system"}>System</option>
          </select>
        </div>
        
        <div class="flex items-end">
          <button
            type="button"
            phx-click="clear_filters"
            phx-target={@target}
            class="text-sm text-gray-500 hover:text-gray-700"
          >
            Clear Filters
          </button>
        </div>
      </div>
    </form>
    """
  end

  # Async user search component
  attr :id, :string, required: true
  attr :label, :string, default: "Search Users"
  attr :placeholder, :string, default: "Type to search..."
  attr :results, :list, default: []
  attr :loading, :boolean, default: false
  attr :value, :any, default: nil

  def user_search(assigns) do
    ~H"""
    <div class="relative" id={@id}>
      <label class="block text-sm font-medium text-gray-700 mb-1"><%= @label %></label>
      <input
        type="text"
        phx-change="search_users"
        phx-debounce="300"
        name="user_query"
        value={@value}
        placeholder={@placeholder}
        class="w-full rounded border-gray-300 text-sm"
        autocomplete="off"
      />
      
      <%= if @loading do %>
        <div class="absolute right-3 top-8">
          <svg class="animate-spin h-4 w-4 text-gray-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
        </div>
      <% end %>
      
      <%= if @results != [] do %>
        <div class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base overflow-auto focus:outline-none sm:text-sm">
          <%= for result <- @results do %>
            <div
              phx-click="select_user"
              phx-value-user-id={result.id}
              phx-value-user-type={result.type}
              class="cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-gray-100"
            >
              <span class="font-normal block truncate"><%= result.label %></span>
              <span class="text-gray-400 text-xs"><%= result.type %></span>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Card component
  slot :inner_block, required: true
  attr :class, :string, default: ""
  attr :rest, :global

  def card(assigns) do
    ~H"""
    <div class={["bg-white rounded-lg shadow p-6", @class]} {@rest}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  # Badge component
  attr :variant, :string, default: "default"
  slot :inner_block, required: true

  def badge(assigns) do
    colors = %{
      "default" => "bg-gray-100 text-gray-800",
      "success" => "bg-green-100 text-green-800",
      "warning" => "bg-yellow-100 text-yellow-800",
      "danger" => "bg-red-100 text-red-800",
      "info" => "bg-blue-100 text-blue-800",
      "terminal" => "bg-purple-100 text-purple-800"
    }
    
    assigns = assign(assigns, :color_class, Map.get(colors, assigns.variant, colors["default"]))
    
    ~H"""
    <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", @color_class]}>
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  # Table components
  slot :inner_block, required: true

  def table(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="min-w-full divide-y divide-gray-200">
        <%= render_slot(@inner_block) %>
      </table>
    </div>
    """
  end

  slot :inner_block, required: true

  def table_header(assigns) do
    ~H"""
    <thead class="bg-gray-50">
      <tr>
        <%= render_slot(@inner_block) %>
      </tr>
    </thead>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def table_header_cell(assigns) do
    ~H"""
    <th scope="col" class={["px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider", @class]}>
      <%= render_slot(@inner_block) %>
    </th>
    """
  end

  slot :inner_block, required: true

  def table_body(assigns) do
    ~H"""
    <tbody class="bg-white divide-y divide-gray-200">
      <%= render_slot(@inner_block) %>
    </tbody>
    """
  end

  slot :inner_block, required: true

  def table_row(assigns) do
    ~H"""
    <tr class="hover:bg-gray-50">
      <%= render_slot(@inner_block) %>
    </tr>
    """
  end

  slot :inner_block, required: true

  def table_cell(assigns) do
    ~H"""
    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
      <%= render_slot(@inner_block) %>
    </td>
    """
  end

  # Alert component
  attr :type, :string, default: "info"
  slot :inner_block, required: true

  def alert(assigns) do
    colors = %{
      "info" => "bg-blue-50 border-blue-400 text-blue-800",
      "success" => "bg-green-50 border-green-400 text-green-800",
      "warning" => "bg-yellow-50 border-yellow-400 text-yellow-800",
      "error" => "bg-red-50 border-red-400 text-red-800"
    }
    
    assigns = assign(assigns, :color_class, Map.get(colors, assigns.type, colors["info"]))
    
    ~H"""
    <div class={["border-l-4 p-4", @color_class]} role="alert">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  # Button component
  attr :type, :string, default: "button"
  attr :variant, :string, default: "primary"
  attr :size, :string, default: "md"
  attr :disabled, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def button(assigns) do
    variant_classes = %{
      "primary" => "bg-blue-600 text-white hover:bg-blue-700 focus:ring-blue-500",
      "secondary" => "bg-white text-gray-700 border border-gray-300 hover:bg-gray-50 focus:ring-gray-500",
      "danger" => "bg-red-600 text-white hover:bg-red-700 focus:ring-red-500",
      "ghost" => "bg-transparent text-gray-600 hover:bg-gray-100 hover:text-gray-900"
    }
    
    size_classes = %{
      "sm" => "px-3 py-1.5 text-sm",
      "md" => "px-4 py-2 text-sm",
      "lg" => "px-6 py-3 text-base"
    }
    
    assigns = 
      assigns
      |> assign(:variant_class, Map.get(variant_classes, assigns.variant, variant_classes["primary"]))
      |> assign(:size_class, Map.get(size_classes, assigns.size, size_classes["md"]))
    
    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      class={[
        "inline-flex items-center justify-center font-medium rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-offset-2 transition-colors",
        @variant_class,
        @size_class,
        if(@disabled, do: "opacity-50 cursor-not-allowed", else: "")
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end
end
