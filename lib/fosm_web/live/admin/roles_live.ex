defmodule FosmWeb.Admin.RolesLive do
  @moduledoc """
  Roles management LiveView.
  
  Features:
  - List all role assignments with filtering
  - Grant roles with async user search (phx-change)
  - Revoke roles with cache invalidation
  - Per-resource role management
  """

  use FosmWeb, :live_view
  import FosmWeb.Admin.Components
  alias Fosm.{Repo, RoleAssignment}
  import Ecto.Query

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Role Management")
      |> assign(:current_path, "/fosm/admin/roles")
      |> assign(:available_models, available_models())
      |> assign(:search_results, [])
      |> assign(:search_loading, false)
      |> assign(:search_query, nil)
    
    {:ok, socket, layout: {FosmWeb.Admin.Layout, :admin_layout}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = String.to_integer(params["page"] || "1")
    resource_type = params["resource_type"]
    resource_id = params["resource_id"]
    
    filters = parse_filters(params)
    
    # Load assignments with filtering
    assignments = fetch_assignments(filters, page)
    
    # Get available roles for the selected resource type
    available_roles = 
      if resource_type && resource_type != "" do
        get_available_roles(resource_type)
      else
        []
      end
    
    # Load resource if viewing specific resource
    resource = 
      if resource_type && resource_id do
        load_resource(resource_type, resource_id)
      else
        nil
      end
    
    socket =
      socket
      |> assign(:page, page)
      |> assign(:filters, filters)
      |> assign(:assignments, assignments)
      |> assign(:available_roles, available_roles)
      |> assign(:selected_resource_type, resource_type)
      |> assign(:selected_resource_id, resource_id)
      |> assign(:resource, resource)
      |> assign(:grant_form, %{"user_type" => "", "user_id" => "", "role" => ""})
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("search_users", %{"user_query" => query}, socket) do
    if String.length(query) >= 2 do
      socket = assign(socket, :search_loading, true)
      
      # Perform async search
      results = search_users(query, socket.assigns.selected_user_type)
      
      socket =
        socket
        |> assign(:search_results, results)
        |> assign(:search_loading, false)
        |> assign(:search_query, query)
      
      {:noreply, socket}
    else
      {:noreply, assign(socket, :search_results, [])}
    end
  end

  @impl true
  def handle_event("select_user", %{"user-id" => user_id, "user-type" => user_type}, socket) do
    socket =
      socket
      |> assign(:grant_form, Map.merge(socket.assigns.grant_form, %{"user_id" => user_id, "user_type" => user_type}))
      |> assign(:search_results, [])
      |> assign(:search_query, nil)
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("grant_role", %{"role" => role} = params, socket) do
    user_id = socket.assigns.grant_form["user_id"]
    user_type = socket.assigns.grant_form["user_type"]
    
    resource_type = socket.assigns.selected_resource_type || params["resource_type"]
    resource_id = socket.assigns.selected_resource_id || params["resource_id"]
    
    if user_id && user_id != "" && resource_type do
      # Create assignment
      attrs = %{
        user_type: user_type,
        user_id: user_id,
        resource_type: resource_type,
        resource_id: resource_id,
        role_name: role
      }
      
      case %RoleAssignment{}
           |> RoleAssignment.changeset(attrs)
           |> Repo.insert() do
        {:ok, _assignment} ->
          # Invalidate cache for the affected user
          invalidate_user_cache(user_type, user_id)
          
          # Reload assignments
          assignments = fetch_assignments(socket.assigns.filters, 1)
          
          socket =
            socket
            |> put_flash(:info, "Role granted successfully")
            |> assign(:assignments, assignments)
            |> assign(:grant_form, %{"user_type" => "", "user_id" => "", "role" => ""})
          
          {:noreply, socket}
          
        {:error, changeset} ->
          errors = 
            changeset.errors
            |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
            |> Enum.join(", ")
          
          {:noreply, put_flash(socket, :error, "Failed to grant role: #{errors}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a user and role")}
    end
  end

  @impl true
  def handle_event("revoke_role", %{"assignment_id" => assignment_id}, socket) do
    assignment = Repo.get(RoleAssignment, assignment_id)
    
    if assignment do
      # Store user info before deletion for cache invalidation
      user_type = assignment.user_type
      user_id = assignment.user_id
      
      Repo.delete!(assignment)
      
      # Invalidate cache
      invalidate_user_cache(user_type, user_id)
      
      # Reload assignments
      assignments = fetch_assignments(socket.assigns.filters, socket.assigns.page)
      
      {:noreply, 
        socket
        |> put_flash(:info, "Role revoked successfully")
        |> assign(:assignments, assignments)}
    else
      {:noreply, put_flash(socket, :error, "Assignment not found")}
    end
  end

  @impl true
  def handle_event("filter", %{"resource_type" => resource_type} = params, socket) do
    resource_id = params["resource_id"] || ""
    
    # Build query params
    query_params = %{}
    query_params = if resource_type != "", do: Map.put(query_params, "resource_type", resource_type), else: query_params
    query_params = if resource_id != "", do: Map.put(query_params, "resource_id", resource_id), else: query_params
    
    if resource_id != "" do
      {:noreply, push_patch(socket, to: ~p"/fosm/admin/roles/#{resource_type}/#{resource_id}")}
    else
      {:noreply, push_patch(socket, to: ~p"/fosm/admin/roles?#{query_params}")}
    end
  end

  @impl true
  def handle_event("set_user_type", %{"user_type" => user_type}, socket) do
    socket = 
      socket
      |> assign(:selected_user_type, user_type)
      |> assign(:grant_form, Map.put(socket.assigns.grant_form, "user_type", user_type))
    
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-gray-900">Role Management</h1>
        <.badge variant="info"><%= @assignments.total_entries %> assignments</.badge>
      </div>

      <!-- Filter by Resource -->
      <.card>
        <form phx-change="filter" class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 mb-1">Resource Type</label>
            <select name="resource_type" class="w-full rounded border-gray-300 text-sm">
              <option value="">All Types</option>
              <%= for {slug, module} <- @available_models do %>
                <option 
                  value={module.__schema__(:source)} 
                  selected={@selected_resource_type == module.__schema__(:source)}
                >
                  <%= module.__schema__(:source) %>
                </option>
              <% end %>
            </select>
          </div>
          
          <%= if @selected_resource_type do %>
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Resource ID (optional)</label>
              <input
                type="text"
                name="resource_id"
                value={@selected_resource_id}
                placeholder="Specific record ID..."
                class="w-full rounded border-gray-300 text-sm"
              />
            </div>
          <% end %>
        </form>
      </.card>

      <!-- Grant Role Form -->
      <.card>
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Grant Role</h3>
        
        <%= if !@selected_resource_type do %>
          <.alert type="warning">
            <p>Please select a resource type above before granting roles.</p>
          </.alert>
        <% else %>
          <form phx-submit="grant_role" class="space-y-4">
            <!-- User Type Selection -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">User Type</label>
              <div class="flex gap-4">
                <label class="flex items-center">
                  <input
                    type="radio"
                    name="user_type"
                    value="User"
                    checked={@grant_form["user_type"] == "User"}
                    phx-click="set_user_type"
                    phx-value-user_type="User"
                    class="mr-2"
                  />
                  User
                </label>
                <label class="flex items-center">
                  <input
                    type="radio"
                    name="user_type"
                    value="Admin"
                    checked={@grant_form["user_type"] == "Admin"}
                    phx-click="set_user_type"
                    phx-value-user_type="Admin"
                    class="mr-2"
                  />
                  Admin
                </label>
              </div>
            </div>
            
            <!-- Async User Search -->
            <%= if @grant_form["user_type"] not in [nil, ""] do %>
              <div>
                <.user_search
                  id="user-search"
                  label="Search User"
                  placeholder="Type at least 2 characters..."
                  results={@search_results}
                  loading={@search_loading}
                  value={@search_query}
                />
                
                <%= if @grant_form["user_id"] != "" do %>
                  <p class="mt-2 text-sm text-green-600">
                    Selected: <%= @grant_form["user_type"] %> #<%= @grant_form["user_id"] %>
                  </p>
                <% end %>
              </div>
            <% end %>
            
            <!-- Role Selection -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Role</label>
              <select name="role" class="w-full rounded border-gray-300 text-sm">
                <option value="">Select a role...</option>
                <%= for role <- @available_roles do %>
                  <option value={role}><%= role %></option>
                <% end %>
              </select>
            </div>
            
            <.button type="submit" disabled={@grant_form["user_id"] == ""}>
              Grant Role
            </.button>
          </form>
        <% end %>
      </.card>

      <!-- Assignments List -->
      <.card>
        <h3 class="text-lg font-semibold text-gray-900 mb-4">Current Assignments</h3>
        
        <%= if @assignments.entries == [] do %>
          <.alert type="info">
            <p>No role assignments found.</p>
          </.alert>
        <% else %>
          <.table>
            <.table_header>
              <.table_header_cell>User</.table_header_cell>
              <.table_header_cell>Resource</.table_header_cell>
              <.table_header_cell>Role</.table_header_cell>
              <.table_header_cell>Granted</.table_header_cell>
              <.table_header_cell>Actions</.table_header_cell>
            </.table_header>
            <.table_body>
              <%= for assignment <- @assignments.entries do %>
                <.table_row>
                  <.table_cell>
                    <div class="flex items-center gap-2">
                      <span class="text-xs bg-gray-100 px-2 py-0.5 rounded"><%= assignment.user_type %></span>
                      <span class="font-medium">#<%= assignment.user_id %></span>
                    </div>
                  </.table_cell>
                  <.table_cell>
                    <%= if assignment.resource_id do %>
                      <%= assignment.resource_type %> #<%= assignment.resource_id %>
                    <% else %>
                      <span class="text-gray-500">All <%= assignment.resource_type %></span>
                    <% end %>
                  </.table_cell>
                  <.table_cell>
                    <.badge variant="info"><%= assignment.role_name %></.badge>
                  </.table_cell>
                  <.table_cell>
                    <span class="text-xs text-gray-500"><%= format_relative(assignment.inserted_at) %></span>
                  </.table_cell>
                  <.table_cell>
                    <button
                      phx-click="revoke_role"
                      phx-value-assignment_id={assignment.id}
                      data-confirm="Are you sure you want to revoke this role?"
                      class="text-sm text-red-600 hover:text-red-800"
                    >
                      Revoke
                    </button>
                  </.table_cell>
                </.table_row>
              <% end %>
            </.table_body>
          </.table>

          <.pagination
            page={@assignments}
            path={~p"/fosm/admin/roles"}
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
      "resource_type" => params["resource_type"] || "",
      "resource_id" => params["resource_id"] || ""
    }
  end

  defp fetch_assignments(filters, page) do
    query = from(a in RoleAssignment)
    
    query = 
      case filters["resource_type"] do
        "" -> query
        nil -> query
        type -> where(query, resource_type: ^type)
      end
    
    query = 
      case filters["resource_id"] do
        "" -> query
        nil -> query
        id -> where(query, resource_id: ^id)
      end
    
    query
    |> order_by([a], desc: a.inserted_at)
    |> Repo.paginate(page: page, page_size: 25)
  end

  defp search_users(query, user_type) do
    # Default to User if not specified
    user_type = user_type || "User"
    
    try do
      module = Module.concat([user_type])
      
      # Get searchable fields
      schema_fields = module.__schema__(:fields)
      searchable = Enum.filter([:email, :name, :username], & &1 in schema_fields)
      
      if searchable == [] do
        []
      else
        term = "%#{String.downcase(query)}%"
        
        # Build OR conditions for each searchable field
        conditions = 
          Enum.map(searchable, fn field ->
            dynamic([u], ilike(field(u, ^field), ^term))
          end)
          |> Enum.reduce(fn cond1, cond2 -> dynamic([u], ^cond1 or ^cond2) end)
        
        from(u in module)
        |> where(^conditions)
        |> limit(10)
        |> Repo.all()
        |> Enum.map(fn user ->
          %{
            id: user.id,
            type: user_type,
            label: format_user_label(user, searchable)
          }
        end)
      end
    rescue
      _ -> []
    end
  end

  defp format_user_label(user, fields) do
    parts = 
      Enum.map(fields, fn field ->
        case Map.get(user, field) do
          nil -> nil
          val -> to_string(val)
        end
      end)
      |> Enum.reject(&is_nil/1)
    
    if parts == [] do
      "User ##{user.id}"
    else
      Enum.join(parts, " — ")
    end
  end

  defp load_resource(type, id) do
    try do
      module = Module.concat([type])
      Repo.get(module, id)
    rescue
      _ -> nil
    end
  end

  defp get_available_roles(resource_type) do
    # Try to get roles from the module's lifecycle if it's a FOSM model
    try do
      modules = Fosm.Registry.all() |> Enum.map(fn {_, m} -> m end)
      
      module = Enum.find(modules, fn m -> m.__schema__(:source) == resource_type end)
      
      if module && function_exported?(module, :fosm_lifecycle, 0) do
        lifecycle = module.fosm_lifecycle()
        
        # Extract unique role names from access rules
        lifecycle.access_rules
        |> Enum.map(& &1.role_name)
        |> Enum.uniq()
        |> Enum.map(&to_string/1)
      else
        # Default roles
        ["owner", "editor", "viewer", "admin"]
      end
    rescue
      _ -> ["owner", "editor", "viewer", "admin"]
    end
  end

  defp invalidate_user_cache(user_type, user_id) do
    # Use Fosm.Current.invalidate_for if available
    if Code.ensure_loaded?(Fosm.Current) and function_exported?(Fosm.Current, :invalidate_for, 1) do
      # Try to construct a simple actor struct
      actor = %{__struct__: String.to_atom("Elixir.#{user_type}"), id: user_id}
      Fosm.Current.invalidate_for(actor)
    end
  end

  defp format_relative(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%Y-%m-%d")
    end
  end
end
