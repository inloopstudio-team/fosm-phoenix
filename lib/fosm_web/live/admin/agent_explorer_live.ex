defmodule FosmWeb.Admin.AgentExplorerLive do
  @moduledoc """
  LiveView for direct tool testing and exploration.

  The Agent Explorer allows developers to:
  - View all auto-generated tools from a FOSM lifecycle
  - Test tools directly without LLM interaction
  - Understand the tool interface and parameters
  - Debug tool behavior in isolation

  This is useful for:
  - Validating tool implementations
  - Understanding available operations
  - Debugging why an agent might fail
  - Testing edge cases

  ## Routes

      live "/fosm/admin/agent-explorer/:slug", AgentExplorerLive, :show

  """
  use FosmWeb, :live_view
  import FosmWeb.Admin.Components

  alias Fosm.Lifecycle.Definition

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Fosm.Registry.lookup(slug) do
      {:ok, module} ->
        lifecycle = module.fosm_lifecycle()
        tools = derive_tool_definitions(module, lifecycle)

        socket =
          socket
          |> assign(:slug, slug)
          |> assign(:module, module)
          |> assign(:lifecycle, lifecycle)
          |> assign(:tools, tools)
          |> assign(:selected_tool, nil)
          |> assign(:tool_params, %{})          |> assign(:tool_result, nil)
          |> assign(:tool_error, nil)
          |> assign(:executing, false)
          |> assign(:page_title, "Agent Explorer: #{slug}")
          |> assign(:current_path, "/fosm/admin/agent-explorer/#{slug}")

        {:ok, socket, layout: {FosmWeb.Admin.Layout, :admin_layout}}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Unknown FOSM application: #{slug}")
         |> push_navigate(to: ~p"/fosm/admin"),
         layout: {FosmWeb.Admin.Layout, :admin_layout}}
    end
  end

  @impl true
  def handle_event("select_tool", %{"tool" => tool_name}, socket) do
    tool = Enum.find(socket.assigns.tools, & &1.name == tool_name)
    
    # Initialize params with empty strings
    params = 
      tool.params
      |> Enum.map(fn {k, v} -> {k, default_value_for_type(v)} end)
      |> Enum.into(%{})

    socket =
      socket
      |> assign(:selected_tool, tool)
      |> assign(:tool_params, params)
      |> assign(:tool_result, nil)
      |> assign(:tool_error, nil)

    {:noreply, socket}
  end

  def handle_event("update_param", %{"field" => field, "value" => value}, socket) do
    params = Map.put(socket.assigns.tool_params, field, value)
    {:noreply, assign(socket, :tool_params, params)}
  end

  def handle_event("execute_tool", _params, socket) do
    tool = socket.assigns.selected_tool
    module = socket.assigns.module

    # Convert params to proper types
    args = 
      Enum.reduce(tool.params, %{}, fn {name, type}, acc ->
        value = socket.assigns.tool_params[name]
        typed_value = cast_param(value, type)
        Map.put(acc, name, typed_value)
      end)

    # Execute the tool
    socket = assign(socket, :executing, true)
    
    result = execute_tool(tool, module, args)

    socket =
      socket
      |> assign(:tool_result, result)
      |> assign(:tool_error, nil)
      |> assign(:executing, false)

    {:noreply, socket}
  rescue
    e ->
      socket =
        socket
        |> assign(:tool_error, Exception.message(e))
        |> assign(:executing, false)

      {:noreply, socket}
  end

  def handle_event("clear_result", _params, socket) do
    {:noreply, assign(socket, tool_result: nil, tool_error: nil)}
  end

  def handle_event("reset_params", _params, socket) do
    tool = socket.assigns.selected_tool
    
    params = 
      tool.params
      |> Enum.map(fn {k, v} -> {k, default_value_for_type(v)} end)
      |> Enum.into(%{})

    {:noreply, assign(socket, tool_params: params, tool_result: nil, tool_error: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold text-gray-900">Agent Explorer: <%= @slug %></h1>
          <.badge variant="info"><%= length(@tools) %> tools</.badge>
        </div>
        <.link navigate={~p"/fosm/admin/agent-chat/#{@slug}"} class="text-blue-600 hover:text-blue-800 text-sm">
          Switch to Chat →
        </.link>
      </div>

      <p class="text-gray-600">
        Test FOSM tools directly without LLM interaction. Select a tool to see its parameters and execute it.
      </p>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Tool List -->
        <div class="lg:col-span-1 space-y-2">
          <h2 class="text-sm font-semibold text-gray-700 uppercase tracking-wider">Available Tools</h2>
          
          <%= for tool <- @tools do %>
            <button
              phx-click="select_tool"
              phx-value-tool={tool.name}
              class={[
                "w-full text-left p-3 rounded-lg border transition-colors",
                if(@selected_tool && @selected_tool.name == tool.name,
                  do: "bg-blue-50 border-blue-500 ring-1 ring-blue-500",
                  else: "bg-white border-gray-200 hover:bg-gray-50"
                )
              ]}
            >
              <div class="flex items-center justify-between">
                <span class="font-medium text-gray-900"><%= tool.name %></span>
                <.badge variant={category_badge_color(tool.category)}>
                  <%= tool.category %>
                </.badge>
              </div>
              <p class="text-xs text-gray-500 mt-1 line-clamp-2"><%= tool.description %></p>
              <%= if tool[:event] do %>
                <div class="mt-2 flex items-center gap-2 text-xs">
                  <span class="text-gray-400">Event:</span>
                  <span class="font-mono text-blue-600"><%= tool.event %></span>
                </div>
              <% end %>
            </button>
          <% end %>
        </div>

        <!-- Tool Details & Execution -->
        <div class="lg:col-span-2 space-y-6">
          <%= if @selected_tool do %>
            <!-- Tool Info Card -->
            <.card>
              <div class="flex items-start justify-between mb-4">
                <div>
                  <h3 class="text-lg font-semibold text-gray-900"><%= @selected_tool.name %></h3>
                  <p class="text-sm text-gray-600 mt-1"><%= @selected_tool.description %></p>
                </div>
                <.badge variant={category_badge_color(@selected_tool.category)}>
                  <%= @selected_tool.category %>
                </.badge>
              </div>

              <%= if @selected_tool[:event] do %>
                <div class="bg-yellow-50 border border-yellow-200 rounded p-3 text-sm">
                  <p class="font-medium text-yellow-800">⚠️ State Transition Event</p>
                  <p class="text-yellow-700 mt-1">
                    This tool fires the '<%= @selected_tool.event %>' event which will:
                  </p>
                  <ul class="list-disc list-inside text-yellow-700 mt-1">
                    <li>Run all guards</li>
                    <li>Execute immediate side effects</li>
                    <li>Create transition log entry</li>
                    <li>Cannot be undone</li>
                  </ul>
                </div>
              <% end %>
            </.card>

            <!-- Parameters Form -->
            <.card>
              <h4 class="text-sm font-semibold text-gray-700 mb-4">Parameters</h4>
              
              <%= if map_size(@selected_tool.params) == 0 do %>
                <p class="text-gray-500 text-sm italic">No parameters required</p>
              <% else %>
                <div class="space-y-4">
                  <%= for {param_name, param_type} <- @selected_tool.params do %>
                    <div>
                      <label class="block text-sm font-medium text-gray-700 mb-1">
                        <%= param_name %>
                        <span class="text-xs text-gray-500 font-normal">(<%= param_type %>)</span>
                      </label>
                      
                      <%= case param_type do %>
                        <% "boolean" -> %>
                          <select
                            name={param_name}
                            phx-change="update_param"
                            phx-value-field={param_name}
                            class="w-full rounded border-gray-300 text-sm"
                          >
                            <option value="true" selected={@tool_params[param_name] == true}>true</option>
                            <option value="false" selected={@tool_params[param_name] == false}>false</option>
                          </select>
                        
                        <% "integer" -> %>
                          <input
                            type="number"
                            name={param_name}
                            value={@tool_params[param_name]}
                            phx-change="update_param"
                            phx-value-field={param_name}
                            class="w-full rounded border-gray-300 text-sm"
                            placeholder="Enter number..."
                          />
                        
                        <% _ -> %>
                          <input
                            type="text"
                            name={param_name}
                            value={@tool_params[param_name]}
                            phx-change="update_param"
                            phx-value-field={param_name}
                            class="w-full rounded border-gray-300 text-sm"
                            placeholder="Enter value..."
                          />
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <div class="mt-6 flex items-center gap-3">
                <.button
                  phx-click="execute_tool"
                  disabled={@executing}
                  variant="primary"
                >
                  <%= if @executing do %>
                    <span class="flex items-center gap-2">
                      <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Executing...
                    </span>
                  <% else %>
                    Execute Tool
                  <% end %>
                </.button>
                
                <.button
                  phx-click="reset_params"
                  variant="secondary"
                  type="button"
                >
                  Reset
                </.button>
                
                <%= if @tool_result || @tool_error do %>
                  <.button
                    phx-click="clear_result"
                    variant="ghost"
                    type="button"
                  >
                    Clear Result
                  </.button>
                <% end %>
              </div>
            </.card>

            <!-- Result Display -->
            <%= if @tool_error do %>
              <.card class="border-red-200 bg-red-50">
                <h4 class="text-sm font-semibold text-red-800 mb-2">Error</h4>
                <pre class="text-sm text-red-700 whitespace-pre-wrap overflow-x-auto"><%= @tool_error %></pre>
              </.card>
            <% end %>

            <%= if @tool_result do %>
              <.card class="border-green-200">
                <div class="flex items-center justify-between mb-4">
                  <h4 class="text-sm font-semibold text-green-800">Result</h4>
                  <%= if @tool_result[:success] != nil do %>
                    <%= if @tool_result.success do %>
                      <.badge variant="success">Success</.badge>
                    <% else %>
                      <.badge variant="danger">Failed</.badge>
                    <% end %>
                  <% end %>
                </div>
                <pre class="text-sm text-gray-700 bg-gray-50 p-4 rounded overflow-x-auto"><%= Jason.encode!(@tool_result, pretty: true) %></pre>
              </.card>
            <% end %>
          <% else %>
            <.card class="h-full flex items-center justify-center text-gray-400">
              <div class="text-center">
                <svg class="w-12 h-12 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                </svg>
                <p>Select a tool from the list to test it</p>
              </div>
            </.card>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------------------
  # Private Functions
  # ----------------------------------------------------------------------------

  defp derive_tool_definitions(module, lifecycle) do
    resource_name = 
      module.__schema__(:source)
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    plural = Inflex.pluralize(resource_name)

    base_tools = [
      %{
        name: "list_#{plural}",
        description: "List #{plural} with their current state. Optionally filter by state.",
        params: %{"state" => "string"},
        category: :read
      },
      %{
        name: "get_#{resource_name}",
        description: "Get a #{resource_name} by ID with its current state and available transitions.",
        params: %{"id" => "integer"},
        category: :read
      },
      %{
        name: "available_events_for_#{resource_name}",
        description: "Check which lifecycle events can be fired on a record in its current state.",
        params: %{"id" => "integer"},
        category: :read
      },
      %{
        name: "transition_history_for_#{resource_name}",
        description: "Full audit trail of state transitions for a record.",
        params: %{"id" => "integer"},
        category: :read
      }
    ]

    event_tools = 
      Enum.map(lifecycle.events, fn event ->
        from_desc = Enum.join(event.from_states, " or ")
        
        has_guards = 
          lifecycle.guards
          |> Enum.any?(& &1.event == event.name)
        
        has_effects = 
          lifecycle.side_effects
          |> Enum.any?(& &1.event == event.name)
        
        guard_note = if has_guards, do: " [GUARDS]", else: ""
        effect_note = if has_effects, do: " [SIDE EFFECTS]", else: ""

        %{
          name: "#{event.name}_#{resource_name}",
          description: "Fire '#{event.name}' event: #{from_desc} → #{event.to_state}#{guard_note}#{effect_note}",
          params: %{"id" => "integer"},
          event: event.name,
          category: :mutate
        }
      end)

    base_tools ++ event_tools
  end

  defp category_badge_color(:read), do: "info"
  defp category_badge_color(:mutate), do: "warning"
  defp category_badge_color(_), do: "default"

  defp default_value_for_type("boolean"), do: "true"
  defp default_value_for_type("integer"), do: ""
  defp default_value_for_type(_), do: ""

  defp cast_param("", "integer"), do: nil
  defp cast_param(value, "integer") when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> raise "Invalid integer: #{value}"
    end
  end
  defp cast_param("true", "boolean"), do: true
  defp cast_param("false", "boolean"), do: false
  defp cast_param(value, _), do: value

  defp execute_tool(tool, module, args) do
    case tool.name do
      "list_" <> _ ->
        query = if args["state"] && args["state"] != "",
          do: Ecto.Query.where(module, state: args["state"]),
          else: module

        records = Fosm.Repo.all(query)
        
        %{
          success: true,
          count: length(records),
          records: Enum.map(records, &serialize_record/1)
        }

      "get_" <> _ ->
        case Fosm.Repo.get(module, args["id"]) do
          nil ->
            %{success: false, error: "Record not found"}
          
          record ->
            available = Definition.available_events_from(module.fosm_lifecycle(), record.state)
            
            Map.merge(
              serialize_record(record),
              %{
                available_events: available,
                can_fire_info: can_fire_info(module, record)
              }
            )
        end

      "available_events_for_" <> _ ->
        record = Fosm.Repo.get!(module, args["id"])
        available = Definition.available_events_from(module.fosm_lifecycle(), record.state)
        
        %{
          id: record.id,
          current_state: record.state,
          available_events: available,
          is_terminal: Definition.is_terminal?(module.fosm_lifecycle(), record.state)
        }

      "transition_history_for_" <> _ ->
        history = 
          Fosm.TransitionLog
          |> Fosm.TransitionLog.for_record(module.__schema__(:source), args["id"])
          |> Ecto.Query.order_by(desc: :created_at)
          |> Ecto.Query.limit(20)
          |> Fosm.Repo.all()

        %{
          record_id: args["id"],
          transitions: Enum.map(history, fn t ->
            %{
              event: t.event_name,
              from: t.from_state,
              to: t.to_state,
              actor: t.actor_label || t.actor_type,
              at: t.created_at,
              has_snapshot: t.state_snapshot != nil
            }
          end)
        }

      event_tool_name ->
        # Extract event name from "event_name_resource_name"
        resource_suffix = 
          module.__schema__(:source)
          |> String.split(".")
          |> List.last()
          |> Macro.underscore()

        event_name = 
          event_tool_name
          |> String.replace("_#{resource_suffix}", "")
          |> String.to_atom()

        record = Fosm.Repo.get(module, args["id"])

        unless record do
          %{success: false, error: "Record ##{args["id"]} not found"}
        end

        case module.fire!(record, event_name, actor: :agent) do
          {:ok, updated} ->
            %{
              success: true,
              id: updated.id,
              previous_state: record.state,
              new_state: updated.state,
              event: event_name
            }

          {:error, reason} ->
            %{
              success: false,
              error: format_error(reason),
              current_state: record.state
            }
        end
    end
  end

  defp serialize_record(record) do
    base = %{
      id: record.id,
      state: record.state,
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    }

    # Add non-internal fields
    fields = record.__struct__.__schema__(:fields)
    
    Enum.reduce(fields, base, fn field, acc ->
      if field in [:id, :state, :inserted_at, :updated_at, :created_by_id] do
        acc
      else
        value = Map.get(record, field)
        Map.put(acc, field, serialize_value(value))
      end
    end)
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(%Date{} = d), do: Date.to_iso8601(d)
  defp serialize_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp serialize_value(%_{} = struct), do: Map.from_struct(struct)
  defp serialize_value(value), do: value

  defp can_fire_info(module, record) do
    # For each available event, check why_cannot_fire if applicable
    lifecycle = module.fosm_lifecycle()
    
    lifecycle.events
    |> Enum.filter(fn e -> 
      Definition.EventDefinition.valid_from?(e, record.state)
    end)
    |> Enum.map(fn e -> 
      %{event: e.name, from: e.from_states, to: e.to_state}
    end)
  end

  defp format_error(%Fosm.Errors.GuardFailed{guard: g, reason: r}) do
    base = "Guard '#{g}' failed"
    if r, do: "#{base}: #{r}", else: base
  end
  defp format_error(%Fosm.Errors.TerminalState{}), do: "Terminal state - cannot transition"
  defp format_error(%Fosm.Errors.InvalidTransition{} = e), do: "Cannot #{e.event} from #{e.from}"
  defp format_error(%Fosm.Errors.AccessDenied{}), do: "Access denied"
  defp format_error(e) when is_binary(e), do: e
  defp format_error(e), do: Exception.message(e)
end
