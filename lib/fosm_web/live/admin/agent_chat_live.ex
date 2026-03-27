if Code.ensure_loaded?(Phoenix.LiveView) or Code.ensure_loaded?(Phoenix.Component) do
defmodule FosmWeb.Admin.AgentChatLive do
  @moduledoc """
  LiveView for conversational AI agent interface.

  Provides a chat interface for interacting with FOSM AI agents:
  - Shows conversation history with tool calls and reasoning
  - Real-time message streaming (prepared for future enhancement)
  - Session persistence via Fosm.Agent.Session
  - Bounded autonomy: agent can only call fire!, not direct updates

  ## Routes

      live "/fosm/admin/agent-chat/:slug", AgentChatLive, :show

  ## URL Parameters

    - slug: The registered FOSM application slug (e.g., "invoice", "contract")

  """
  use FosmWeb, :live_view
  import FosmWeb.Admin.Components

  alias Fosm.Agent.Session

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Lookup the FOSM module
    case Fosm.Registry.lookup(slug) do
      {:ok, module} ->
        session_id = generate_session_id()
        lifecycle = module.fosm_lifecycle()

        # Initialize or fetch existing session
        messages = initialize_session(session_id, slug, lifecycle)

        socket =
          socket
          |> assign(:slug, slug)
          |> assign(:module, module)
          |> assign(:lifecycle, lifecycle)
          |> assign(:session_id, session_id)
          |> assign(:messages, messages)
          |> assign(:input, "")
          |> assign(:loading, false)
          |> assign(:error, nil)
          |> assign(:page_title, "Agent Chat: #{slug}")
          |> assign(:current_path, "/fosm/admin/agent-chat/#{slug}")

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
  def handle_event("send_message", %{"message" => text}, socket) when text != "" do
    session_id = socket.assigns.session_id
    messages = socket.assigns.messages

    # Add user message
    user_message = %{role: "user", content: text, timestamp: DateTime.utc_now()}
    updated_messages = messages ++ [user_message]

    # Store updated history
    Session.store_history(session_id, updated_messages)

    # Mark loading and trigger async agent response
    socket =
      socket
      |> assign(:messages, updated_messages)
      |> assign(:input, "")
      |> assign(:loading, true)
      |> assign(:error, nil)

    # Start async agent processing
    Task.async(fn ->
      run_agent(socket.assigns.module, socket.assigns.session_id, text, updated_messages)
    end)

    {:noreply, socket}
  end

  def handle_event("send_message", _params, socket) do
    # Empty message, ignore
    {:noreply, socket}
  end

  def handle_event("update_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  def handle_event("clear_chat", _params, socket) do
    session_id = socket.assigns.session_id
    lifecycle = socket.assigns.lifecycle

    # Reset session with welcome message
    Session.reset(session_id)
    messages = initialize_session(session_id, socket.assigns.slug, lifecycle)

    {:noreply, assign(socket, :messages, messages)}
  end

  def handle_event("show_reasoning", %{"message_idx" => idx}, socket) do
    # Toggle reasoning visibility
    messages =
      List.update_at(socket.assigns.messages, String.to_integer(idx), fn msg ->
        Map.update(msg, :show_reasoning, true, &(!&1))
      end)

    {:noreply, assign(socket, :messages, messages)}
  end

  @impl true
  def handle_info({ref, {:ok, agent_response}}, socket) when is_reference(ref) do
    # DEMONITOR the task
    Process.demonitor(ref, [:flush])

    session_id = socket.assigns.session_id
    messages = socket.assigns.messages

    # Add assistant response
    assistant_message = %{
      role: "assistant",
      content: agent_response.text,
      tool_calls: agent_response.tool_calls,
      reasoning: agent_response.reasoning,
      show_reasoning: false,
      timestamp: DateTime.utc_now()
    }

    updated_messages = messages ++ [assistant_message]

    # Store updated history
    Session.store_history(session_id, updated_messages)

    socket =
      socket
      |> assign(:messages, updated_messages)
      |> assign(:loading, false)

    {:noreply, socket}
  end

  def handle_info({ref, {:error, reason}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(:loading, false)
      |> assign(:error, format_error(reason))

    {:noreply, socket}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    # Task crashed
    socket =
      socket
      |> assign(:loading, false)
      |> assign(:error, "Agent process crashed unexpectedly")

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-[calc(100vh-8rem)] flex flex-col">
      <!-- Header -->
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold text-gray-900">Agent Chat: <%= @slug %></h1>
          <.badge variant="info"><%= length(@lifecycle.states) %> states</.badge>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-xs text-gray-500">Session: <%= String.slice(@session_id, 0, 8) %>...</span>
          <button
            phx-click="clear_chat"
            class="text-sm text-gray-500 hover:text-gray-700 px-3 py-1 rounded border border-gray-300 hover:bg-gray-50"
          >
            Clear Chat
          </button>
        </div>
      </div>

      <!-- Error Alert -->
      <%= if @error do %>
        <.alert type="error" class="mb-4">
          <p><%= @error %></p>
        </.alert>
      <% end %>

      <!-- Messages Area -->
      <div class="flex-1 overflow-y-auto bg-gray-50 rounded-lg p-4 space-y-4 mb-4" id="messages-container" phx-hook="ScrollBottom">
        <%= for {msg, idx} <- Enum.with_index(@messages) do %>
          <div class={[
            "flex",
            if(msg.role == "user", do: "justify-end", else: "justify-start")
          ]}>
            <div class={[
              "max-w-3xl rounded-lg p-4 shadow-sm",
              if(msg.role == "user",
                do: "bg-blue-600 text-white",
                else: "bg-white border border-gray-200 text-gray-900"
              )
            ]}>
              <!-- Message Content -->
              <div class={[
                "prose prose-sm max-w-none",
                if(msg.role == "user", do: "prose-invert", else: "")
              ]}>
                <%= format_content(msg.content) %>
              </div>

              <!-- Tool Calls (Assistant only) -->
              <%= if msg.role == "assistant" && msg[:tool_calls] && msg.tool_calls != [] do %>
                <div class="mt-3 pt-3 border-t border-gray-200">
                  <p class="text-xs font-semibold text-gray-500 mb-2">Tool Calls:</p>
                  <div class="space-y-2">
                    <%= for tool <- msg.tool_calls do %>
                      <div class="bg-gray-100 rounded px-3 py-2 text-sm">
                        <div class="flex items-center gap-2">
                          <span class="font-medium text-gray-700"><%= tool.name %></span>
                          <%= if tool[:success] do %>
                            <%= if tool.success do %>
                              <span class="text-green-600 text-xs">✓ Success</span>
                            <% else %>
                              <span class="text-red-600 text-xs">✗ Failed</span>
                            <% end %>
                          <% end %>
                        </div>
                        <%= if tool[:params] do %>
                          <pre class="mt-1 text-xs text-gray-600 bg-white p-2 rounded overflow-x-auto"><%= Jason.encode!(tool.params, pretty: true) %></pre>
                        <% end %>
                        <%= if tool[:result] do %>
                          <div class="mt-1 text-xs text-gray-600">
                            <span class="font-medium">Result:</span> <%= inspect(tool.result) %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <!-- Reasoning Toggle (Assistant only) -->
              <%= if msg.role == "assistant" && msg[:reasoning] && msg.reasoning != "" do %>
                <div class="mt-2">
                  <button
                    phx-click="show_reasoning"
                    phx-value-message-idx={idx}
                    class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1"
                  >
                    <span><%= if msg[:show_reasoning], do: "▼", else: "▶" %> Reasoning</span>
                  </button>
                  <%= if msg[:show_reasoning] && msg.show_reasoning do %>
                    <div class="mt-2 p-3 bg-gray-50 rounded text-sm text-gray-600 italic">
                      <%= msg.reasoning %>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <!-- Timestamp -->
              <div class={[
                "mt-2 text-xs",
                if(msg.role == "user", do: "text-blue-200", else: "text-gray-400")
              ]}>
                <%= format_timestamp(msg.timestamp) %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Loading Indicator -->
        <%= if @loading do %>
          <div class="flex justify-start">
            <div class="bg-white border border-gray-200 rounded-lg p-4 shadow-sm">
              <div class="flex items-center gap-2 text-gray-500">
                <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <span class="text-sm">Agent is thinking...</span>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Input Area -->
      <div class="bg-white border-t pt-4">
        <form phx-submit="send_message" class="flex gap-2">
          <input
            type="text"
            name="message"
            value={@input}
            phx-change="update_input"
            phx-debounce="100"
            placeholder={"Ask the agent about #{@slug} records..."}
            class="flex-1 rounded-lg border-gray-300 px-4 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            autocomplete="off"
            disabled={@loading}
          />
          <.button type="submit" disabled={@loading || @input == ""}>
            <%= if @loading, do: "Sending...", else: "Send" %>
          </.button>
        </form>
        <p class="text-xs text-gray-500 mt-2">
          This agent has bounded autonomy: it can only trigger lifecycle events via fire!, not make direct database updates.
          Session expires in 4 hours.
        </p>
      </div>
    </div>
    """
  end

  # ----------------------------------------------------------------------------
  # Private Functions
  # ----------------------------------------------------------------------------

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  defp initialize_session(session_id, slug, lifecycle) do
    case Session.fetch_history(session_id) do
      {:ok, []} ->
        # New session - create welcome message
        welcome = %{
          role: "assistant",
          content: build_welcome_message(slug, lifecycle),
          timestamp: DateTime.utc_now()
        }

        Session.store_history(session_id, [welcome])
        [welcome]

      {:ok, existing} ->
        existing

      :expired ->
        # Session expired, start fresh
        welcome = %{
          role: "assistant",
          content: build_welcome_message(slug, lifecycle),
          timestamp: DateTime.utc_now()
        }

        Session.store_history(session_id, [welcome])
        [welcome]
    end
  end

  defp build_welcome_message(slug, lifecycle) do
    state_count = length(lifecycle.states)
    event_count = length(lifecycle.events)

    terminal_states =
      lifecycle.states
      |> Enum.filter(& &1.terminal)
      |> Enum.map(&to_string(&1.name))
      |> case do
        [] -> "No terminal states"
        states -> "Terminal states: #{Enum.join(states, ", ")}"
      end

    """
    Hello! I'm your AI assistant for managing **#{slug}** records.

    I can help you:
    - List and filter records by state
    - View record details and available transitions
    - Trigger lifecycle events (with proper guard checks)
    - Explain the state machine structure

    **Capabilities:**
    - #{state_count} states (#{terminal_states})
    - #{event_count} lifecycle events
    - Bounded autonomy: I can only call `fire!` for state transitions

    How can I help you today?
    """
  end

  defp run_agent(module, session_id, prompt, messages) do
    # For now, return a mock response since Fosm.Agent isn't fully implemented
    # This will be replaced with actual agent calls once Fosm.Agent is ready

    lifecycle = module.fosm_lifecycle()

    # Build mock tool calls based on the prompt content
    tool_calls = detect_mock_tool_calls(prompt, lifecycle)

    response_text = generate_mock_response(prompt, module, lifecycle, tool_calls)

    reasoning =
      "The user asked about '#{String.slice(prompt, 0, 50)}...'. " <>
        "I analyzed the #{module.__schema__(:source)} lifecycle with #{length(lifecycle.states)} states " <>
        "and determined the appropriate response and any necessary tool calls."

    {:ok,
     %{
       text: response_text,
       tool_calls: tool_calls,
       reasoning: reasoning
     }}
  end

  defp detect_mock_tool_calls(prompt, lifecycle) do
    prompt_lower = String.downcase(prompt)

    cond do
      String.contains?(prompt_lower, "list") || String.contains?(prompt_lower, "show") ||
          String.contains?(prompt_lower, "all") ->
        [
          %{
            name: "list_#{resource_name(lifecycle)}",
            params: %{},
            success: true,
            result: "Retrieved 5 records"
          }
        ]

      Regex.match?(~r/(get|find|show).*?(\d+)/i, prompt) ->
        id = Regex.run(~r/(\d+)/, prompt) |> List.last()

        [
          %{
            name: "get_#{resource_name(lifecycle)}",
            params: %{"id" => id},
            success: true,
            result: "Record #{id} found in current state"
          }
        ]

      true ->
        []
    end
  end

  defp generate_mock_response(prompt, module, lifecycle, tool_calls) do
    prompt_lower = String.downcase(prompt)
    resource = module.__schema__(:source)

    cond do
      String.contains?(prompt_lower, "help") || String.contains?(prompt_lower, "what can you") ->
        """
        I can help you with the following actions:

        **Read Operations:**
        - List all #{resource} records or filter by state
        - Get details of a specific record by ID
        - Check available transitions for a record
        - View transition history

        **State Transitions:**
        #{format_available_events(lifecycle)}

        **Important:** I can only trigger transitions through proper lifecycle events (fire!), which ensures all guards and side effects run correctly.
        """

      String.contains?(prompt_lower, "list") || String.contains?(prompt_lower, "show all") ->
        if tool_calls != [] do
          "I've retrieved the list of #{resource} records. Here's what I found:\n\n" <>
            "* 5 records total\n" <>
            "* States: draft (2), active (2), completed (1)\n\n" <>
            "Would you like me to show details for any specific record?"
        else
          "I can list all #{resource} records for you. Would you like to see all records or filter by a specific state?"
        end

      Regex.match?(~r/(event|transition|available)/i, prompt) ->
        "Here are the available lifecycle events for #{resource}:\n\n" <>
          format_available_events(lifecycle)

      true ->
        "I understand you're asking about #{resource}. To help you best, could you clarify if you'd like to:\n\n" <>
          "1. List records\n" <>
          "2. View a specific record\n" <>
          "3. Check available transitions\n" <>
          "4. Trigger a state transition\n\n" <>
          "Or feel free to ask in your own words!"
    end
  end

  defp format_available_events(lifecycle) do
    lifecycle.events
    |> Enum.map(fn event ->
      from_states = Enum.join(event.from_states, " or ")
      "- **#{event.name}**: #{from_states} → #{event.to_state}"
    end)
    |> Enum.join("\n")
  end

  defp resource_name(lifecycle) do
    # Extract resource name from first event or default
    lifecycle.events
    |> List.first()
    |> case do
      nil -> "record"
      event -> to_string(event.name)
    end
  end

  defp format_content(text) when is_binary(text) do
    # Simple markdown-like formatting
    text
    |> Phoenix.HTML.Format.text_to_html(
      attributes: [class: "whitespace-pre-wrap"],
      escape: false
    )
    |> Phoenix.HTML.safe_to_string()
  end

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_timestamp(_), do: ""

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: "An error occurred: #{inspect(reason)}"
end
end
