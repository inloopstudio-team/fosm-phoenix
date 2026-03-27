defmodule Fosm.Agent do
  @moduledoc """
  Base module for FOSM AI agents with bounded autonomy.

  FOSM agents provide LLM-powered interaction with state machine records while
  maintaining strict safety constraints:

  - **Bounded Autonomy**: Agents can only call `fire!` for state transitions
  - **Tool-Based**: All operations go through auto-generated tools from lifecycle DSL
  - **Observable**: All tool calls and reasoning are visible in the UI
  - **Safe**: Guards and side effects always run; no direct database updates

  ## Usage

  Define an agent for your FOSM module:

      defmodule MyApp.Fosm.InvoiceAgent do
        use Fosm.Agent,
          model_class: MyApp.Fosm.Invoice,
          default_model: "anthropic/claude-3-5-sonnet-20241022"

        # Optional: Add custom tools beyond the auto-generated ones
        defp build_custom_tools do
          [
            %{
              name: "calculate_tax",
              description: "Calculate tax for an invoice amount",
              parameters: %{
                type: "object",
                properties: %{
                  amount: %{type: "number", description: "Invoice amount"},
                  rate: %{type: "number", description: "Tax rate (e.g., 0.08 for 8%)"}
                },
                required: ["amount", "rate"]
              },
              handler: fn args ->
                amount = args["amount"]
                rate = args["rate"]
                %{tax: amount * rate, total: amount * (1 + rate)}
              end
            }
          ]
        end
      end

  Run the agent:

      {:ok, response} = MyApp.Fosm.InvoiceAgent.run(
        "List all draft invoices",
        session_id: "sess_123"
      )

  ## Architecture

  1. **Tool Generation**: Tools are auto-generated from the lifecycle definition at compile time
  2. **System Prompt**: Includes FOSM constraints, valid states, available events, and tool descriptions
  3. **LLM Integration**: Direct API calls (Anthropic, OpenAI, etc.) with tool calling
  4. **Response Parsing**: Structured outputs with text, tool_calls, and reasoning
  5. **Session Persistence**: Conversation history stored via `Fosm.Agent.Session`

  ## Safety Guarantees

  - Agents cannot bypass guards or side effects
  - Terminal states block all transitions
  - Failed tool calls are reported, not retried automatically
  - All actions are logged as coming from `:agent` actor

  """

  @doc """
  Runtime struct for agent execution.
  """
  defstruct [
    :model,
    :tools,
    :instructions,
    :model_class,
    :max_tokens,
    :temperature
  ]

  @type t :: %__MODULE__{
    model: String.t(),
    tools: [map()],
    instructions: String.t(),
    model_class: module(),
    max_tokens: non_neg_integer() | nil,
    temperature: float() | nil
  }

  defmodule Response do
    @moduledoc """
    Response from an agent run.
    """
    defstruct [:text, :tool_calls, :reasoning, :usage, :model]

    @type t :: %__MODULE__{
      text: String.t(),
      tool_calls: [map()],
      reasoning: String.t() | nil,
      usage: map() | nil,
      model: String.t()
    }
  end

  @default_max_tokens 4096
  @default_temperature 0.7

  # ----------------------------------------------------------------------------
  # Using Macro
  # ----------------------------------------------------------------------------

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @model_class opts[:model_class]
      @default_model opts[:default_model] || "anthropic/claude-3-5-sonnet-20241022"
      @api_key_env opts[:api_key_env]

      # Validate model_class is provided
      unless @model_class do
        raise ArgumentError, "Fosm.Agent requires :model_class option"
      end

      @doc """
      Returns the configured model class.
      """
      def model_class, do: @model_class

      @doc """
      Returns the default model identifier.
      """
      def default_model, do: @default_model

      @doc """
      Returns all available tools (auto-generated + custom).
      """
      def tools do
        build_standard_tools() ++ build_custom_tools()
      end

      @doc """
      Builds an agent runtime configuration.

      ## Options
        - :model - Override the default model
        - :instructions - Additional system instructions
        - :max_tokens - Maximum tokens for response (default: 4096)
        - :temperature - Sampling temperature (default: 0.7)
      """
      @spec build_agent(keyword()) :: Fosm.Agent.t()
      def build_agent(opts \\ []) do
        model = opts[:model] || @default_model
        extra_instructions = opts[:instructions] || ""
        max_tokens = opts[:max_tokens] || 4096
        temperature = opts[:temperature] || 0.7

        instructions = build_system_instructions(extra_instructions)

        %Fosm.Agent{
          model: model,
          tools: tools(),
          instructions: instructions,
          model_class: @model_class,
          max_tokens: max_tokens,
          temperature: temperature
        }
      end

      @doc """
      Runs the agent with a user prompt.

      ## Parameters
        - prompt: The user's message
        - opts: Keyword list of options
          - :session_id - Session ID for history persistence
          - :model - Override the model for this run
          - :async - If true, returns immediately and sends message to caller

      ## Returns
        - {:ok, response} on success
        - {:error, reason} on failure
      """
      @spec run(String.t(), keyword()) :: {:ok, Fosm.Agent.response()} | {:error, any()}
      def run(prompt, opts \\ []) do
        agent = build_agent(opts)
        session_id = opts[:session_id]

        # Fetch or initialize conversation history
        history = if session_id do
          case Fosm.Agent.Session.fetch_history(session_id) do
            {:ok, existing} -> existing
            :expired -> []
          end
        else
          []
        end

        # Add user message to history
        user_message = %{role: "user", content: prompt}
        updated_history = history ++ [user_message]

        # Build messages for LLM
        messages = [
          %{role: "system", content: agent.instructions}
          | updated_history
        ]

        # Call LLM with tools
        case call_llm(agent, messages) do
          {:ok, llm_response} ->
            # Parse response and execute any tool calls
            parsed = parse_response(llm_response)

            # Execute tool calls if present
            {tool_results, executed_tools} =
              if parsed[:tool_calls] && parsed.tool_calls != [] do
                execute_tools(agent, parsed.tool_calls)
              else
                {[], []}
              end

            # Build response struct
            response = %Fosm.Agent.Response{
              text: parsed.text || "",
              tool_calls: executed_tools,
              reasoning: parsed.reasoning,
              usage: parsed.usage,
              model: agent.model
            }

            # Store assistant response in history
            assistant_message = %{
              role: "assistant",
              content: response.text,
              tool_calls: response.tool_calls,
              reasoning: response.reasoning
            }

            final_history = updated_history ++ [assistant_message]

            if session_id do
              Fosm.Agent.Session.store_history(session_id, final_history)
            end

            {:ok, response}

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc """
      Runs the agent asynchronously.
      Returns immediately and sends result to caller process.
      """
      @spec run_async(String.t(), keyword()) :: Task.t()
      def run_async(prompt, opts \\ []) do
        caller = self()
        session_id = opts[:session_id]

        Task.async(fn ->
          result = run(prompt, opts)
          send(caller, {:agent_response, session_id, result})
          result
        end)
      end

      # ----------------------------------------------------------------------------
      # Private Functions
      # ----------------------------------------------------------------------------

      # Auto-generate standard tools from lifecycle
      defp build_standard_tools do
        lifecycle = @model_class.fosm_lifecycle()
        resource_name = resource_name_from_module(@model_class)
        plural = Inflex.pluralize(resource_name)

        read_tools = [
          build_list_tool(resource_name, plural),
          build_get_tool(resource_name),
          build_available_events_tool(resource_name),
          build_transition_history_tool(resource_name)
        ]

        event_tools = build_event_tools(lifecycle, resource_name)

        read_tools ++ event_tools
      end

      defp build_list_tool(resource_name, plural) do
        %{
          name: "list_#{plural}",
          description: "List all #{plural} with their current state. Optionally filter by state.",
          parameters: %{
            type: "object",
            properties: %{
              state: %{
                type: "string",
                description: "Optional state filter (e.g., 'draft', 'active')",
                enum: enum_states(@model_class.fosm_lifecycle())
              }
            }
          },
          required: [],
          handler: fn args ->
            state_filter = args["state"]

            query = if state_filter && state_filter != "",
              do: Ecto.Query.where(@model_class, state: state_filter),
              else: @model_class

            records = Fosm.Repo.all(query)

            %{
              success: true,
              count: length(records),
              records: Enum.map(records, &serialize_record/1)
            }
          end
        }
      end

      defp build_get_tool(resource_name) do
        %{
          name: "get_#{resource_name}",
          description: "Get a #{resource_name} by ID with its current state and available transitions.",
          parameters: %{
            type: "object",
            properties: %{
              id: %{
                type: "integer",
                description: "The #{resource_name} ID"
              }
            },
            required: ["id"]
          },
          handler: fn args ->
            case Fosm.Repo.get(@model_class, args["id"]) do
              nil ->
                %{error: "#{resource_name} ##{args["id"]} not found"}

              record ->
                lifecycle = @model_class.fosm_lifecycle()
                available = Fosm.Lifecycle.Definition.available_events_from(lifecycle, record.state)

                Map.merge(
                  serialize_record(record),
                  %{
                    available_events: available,
                    is_terminal: Fosm.Lifecycle.Definition.is_terminal?(lifecycle, record.state)
                  }
                )
            end
          end
        }
      end

      defp build_available_events_tool(resource_name) do
        %{
          name: "available_events_for_#{resource_name}",
          description: "Check which lifecycle events can be fired on a record in its current state.",
          parameters: %{
            type: "object",
            properties: %{
              id: %{
                type: "integer",
                description: "The #{resource_name} ID"
              }
            },
            required: ["id"]
          },
          handler: fn args ->
            record = Fosm.Repo.get(@model_class, args["id"])

            unless record do
              %{error: "#{resource_name} ##{args["id"]} not found"}
            else
              lifecycle = @model_class.fosm_lifecycle()
              available = Fosm.Lifecycle.Definition.available_events_from(lifecycle, record.state)

              %{
                id: record.id,
                current_state: record.state,
                available_events: available,
                is_terminal: Fosm.Lifecycle.Definition.is_terminal?(lifecycle, record.state)
              }
            end
          end
        }
      end

      defp build_transition_history_tool(resource_name) do
        %{
          name: "transition_history_for_#{resource_name}",
          description: "Get the full audit trail of state transitions for a record.",
          parameters: %{
            type: "object",
            properties: %{
              id: %{
                type: "integer",
                description: "The #{resource_name} ID"
              },
              limit: %{
                type: "integer",
                description: "Maximum number of transitions to return (default: 20)",
                default: 20
              }
            },
            required: ["id"]
          },
          handler: fn args ->
            limit = args["limit"] || 20

            history =
              Fosm.TransitionLog
              |> Fosm.TransitionLog.for_record(@model_class.__schema__(:source), args["id"])
              |> Ecto.Query.order_by(desc: :created_at)
              |> Ecto.Query.limit(^limit)
              |> Fosm.Repo.all()

            %{
              record_id: args["id"],
              total_transitions: length(history),
              transitions: Enum.map(history, &serialize_transition/1)
            }
          end
        }
      end

      defp build_event_tools(lifecycle, resource_name) do
        Enum.map(lifecycle.events, fn event ->
          from_desc = Enum.join(event.from_states, " or ")

          has_guards = Enum.any?(lifecycle.guards, & &1.event == event.name)
          has_effects = Enum.any?(lifecycle.side_effects, & &1.event == event.name)

          guard_note = if has_guards, do: " Requires guard checks.", else: ""
          effect_note = if has_effects, do: " Triggers side effects.", else: ""

          %{
            name: "#{event.name}_#{resource_name}",
            description:
              "Fire the '#{event.name}' event to transition from [#{from_desc}] to '#{event.to_state}'." <>
                guard_note <> effect_note <>
                " Returns {:error, reason} if guards fail or transition is invalid.",
            parameters: %{
              type: "object",
              properties: %{
                id: %{
                  type: "integer",
                  description: "The #{resource_name} ID"
                }
              },
              required: ["id"]
            },
            handler: fn args ->
              record = Fosm.Repo.get(@model_class, args["id"])

              unless record do
                %{success: false, error: "#{resource_name} ##{args["id"]} not found"}
              else
                case @model_class.fire!(record, event.name, actor: :agent) do
                  {:ok, updated} ->
                    %{
                      success: true,
                      id: updated.id,
                      previous_state: record.state,
                      new_state: updated.state,
                      event: event.name,
                      message: "Successfully fired '#{event.name}' event"
                    }

                  {:error, reason} ->
                    %{
                      success: false,
                      error: format_error(reason),
                      current_state: record.state,
                      event: event.name
                    }
                end
              end
            end
          }
        end)
      end

      # Override this to add custom tools
      defp build_custom_tools, do: []

      defp build_system_instructions(extra) do
        lifecycle = @model_class.fosm_lifecycle()

        state_names = Enum.map(lifecycle.states, & &1.name) |> Enum.join(", ")

        terminal_states =
          lifecycle.states
          |> Enum.filter(& &1.terminal)
          |> Enum.map(& &1.name)
          |> case do
            [] -> "None"
            states -> Enum.join(states, ", ")
          end

        event_names = Enum.map(lifecycle.events, & &1.name) |> Enum.join(", ")

        resource_name = resource_name_from_module(@model_class)

        base = """
        You are a FOSM AI agent managing #{@model_class.__schema__(:source)} records.

        ## Architecture & Safety Constraints

        1. **State changes ONLY via lifecycle event tools** - Never attempt to update the state field directly.
        2. **Valid states:** #{state_names}
        3. **Terminal states (no transitions allowed):** #{terminal_states}
        4. **Available events:** #{event_names}
        5. **ALWAYS call available_events_for_#{resource_name} before firing an event.**
        6. **If a tool returns { success: false }, DO NOT retry the same action.**
        7. **Records in terminal states cannot transition** - Check is_terminal flag.
        8. **All state transitions are logged** with actor: :agent.
        9. **Guards must pass** before a transition succeeds - respect guard failures.

        ## Decision Process

        Before taking any action:
        1. Think step-by-step about the user's request
        2. Identify which records are involved
        3. Check current states and available transitions
        4. Determine if the requested action is valid
        5. Call appropriate tools with correct parameters
        6. Report results clearly to the user

        ## Tool Calling

        - Use provided tools for ALL data access and mutations
        - read tools: list_*, get_*, available_events_*, transition_history_*
        - mutate tools: *_#{resource_name} event tools
        - Tools return {:ok, result} or {:error, reason} - never crash
        """

        if extra && extra != "" do
          base <> "\n\n## Additional Instructions\n\n" <> extra
        else
          base
        end
      end

      # ----------------------------------------------------------------------------
      # LLM Integration (Direct API Calls)
      # ----------------------------------------------------------------------------

      defp call_llm(agent, messages) do
        model = agent.model

        cond do
          String.starts_with?(model, "anthropic/") ->
            call_anthropic(agent, messages)

          String.starts_with?(model, "openai/") ->
            call_openai(agent, messages)

          true ->
            # Default to anthropic format
            call_anthropic(agent, messages)
        end
      end

      defp call_anthropic(agent, messages) do
        api_key = System.get_env("ANTHROPIC_API_KEY")

        if is_nil(api_key) do
          {:error, "ANTHROPIC_API_KEY not set"}
        else
          do_call_anthropic(agent, messages, api_key)
        end
      end

      defp do_call_anthropic(agent, messages, api_key) do
        # Extract model name from "anthropic/model-name"
        model = agent.model |> String.replace("anthropic/", "")

        # Format tools for Anthropic API
        tools = format_tools_for_anthropic(agent.tools)

        # Separate system from other messages
        {system_msg, conversation} =
          case messages do
            [%{role: "system", content: sys} | rest] -> {sys, rest}
            _ -> {"", messages}
          end

        # Build request body
        body = %{
          model: model,
          max_tokens: agent.max_tokens || @default_max_tokens,
          temperature: agent.temperature || @default_temperature,
          system: system_msg,
          messages: format_messages_for_anthropic(conversation),
          tools: tools
        }

        # Remove tools if empty (Anthropic requires at least one if present)
        body = if tools == [], do: Map.delete(body, :tools), else: body

        # Make request
        case Req.post(
               "https://api.anthropic.com/v1/messages",
               headers: [
                 {"x-api-key", api_key},
                 {"anthropic-version", "2023-06-01"},
                 {"content-type", "application/json"}
               ],
               json: body
             ) do
          {:ok, %{status: 200, body: response}} ->
            {:ok, parse_anthropic_response(response)}

          {:ok, %{status: status, body: body}} ->
            error_msg = get_in(body, ["error", "message"]) || "HTTP #{status}"
            {:error, "Anthropic API error: #{error_msg}"}

          {:error, reason} ->
            {:error, "Request failed: #{inspect(reason)}"}
        end
      end

      defp call_openai(agent, messages) do
        api_key = System.get_env("OPENAI_API_KEY")

        if is_nil(api_key) do
          {:error, "OPENAI_API_KEY not set"}
        else
          do_call_openai(agent, messages, api_key)
        end
      end

      defp do_call_openai(agent, messages, api_key) do

        model = agent.model |> String.replace("openai/", "")
        tools = format_tools_for_openai(agent.tools)

        body = %{
          model: model,
          max_tokens: agent.max_tokens || @default_max_tokens,
          temperature: agent.temperature || @default_temperature,
          messages: messages,
          tools: tools
        }

        body = if tools == [], do: Map.delete(body, :tools), else: body

        case Req.post(
               "https://api.openai.com/v1/chat/completions",
               headers: [
                 {"authorization", "Bearer #{api_key}"},
                 {"content-type", "application/json"}
               ],
               json: body
             ) do
          {:ok, %{status: 200, body: response}} ->
            {:ok, parse_openai_response(response)}

          {:ok, %{status: status, body: body}} ->
            error_msg = get_in(body, ["error", "message"]) || "HTTP #{status}"
            {:error, "OpenAI API error: #{error_msg}"}

          {:error, reason} ->
            {:error, "Request failed: #{inspect(reason)}"}
        end
      end

      # ----------------------------------------------------------------------------
      # Tool Formatting
      # ----------------------------------------------------------------------------

      defp format_tools_for_anthropic(tools) do
        Enum.map(tools, fn tool ->
          %{
            name: tool.name,
            description: tool.description,
            input_schema: tool.parameters
          }
        end)
      end

      defp format_tools_for_openai(tools) do
        Enum.map(tools, fn tool ->
          %{
            type: "function",
            function: %{
              name: tool.name,
              description: tool.description,
              parameters: tool.parameters
            }
          }
        end)
      end

      defp format_messages_for_anthropic(messages) do
        Enum.map(messages, fn msg ->
          case msg.role do
            "user" -> %{role: "user", content: msg.content}
            "assistant" -> %{role: "assistant", content: msg.content}
            _ -> %{role: "user", content: msg.content}
          end
        end)
      end

      # ----------------------------------------------------------------------------
      # Response Parsing
      # ----------------------------------------------------------------------------

      defp parse_anthropic_response(response) do
        content = response["content"] || []

        text_content =
          content
          |> Enum.filter(& &1["type"] == "text")
          |> Enum.map(& &1["text"])
          |> Enum.join("\n")

        tool_calls =
          content
          |> Enum.filter(& &1["type"] == "tool_use")
          |> Enum.map(fn tool ->
            %{
              id: tool["id"],
              name: tool["name"],
              parameters: tool["input"] || %{}
            }
          end)

        %{
          text: text_content,
          tool_calls: tool_calls,
          reasoning: nil,
          usage: response["usage"],
          model: response["model"]
        }
      end

      defp parse_openai_response(response) do
        choice = List.first(response["choices"] || [])
        message = choice["message"] || %{}

        text_content = message["content"] || ""

        tool_calls =
          (message["tool_calls"] || [])
          |> Enum.map(fn tool ->
            args = Jason.decode(tool["function"]["arguments"] || "{}")

            %{
              id: tool["id"],
              name: tool["function"]["name"],
              parameters: args
            }
          end)

        %{
          text: text_content,
          tool_calls: tool_calls,
          reasoning: nil,
          usage: response["usage"],
          model: response["model"]
        }
      end

      defp parse_response(response), do: response

      # ----------------------------------------------------------------------------
      # Tool Execution
      # ----------------------------------------------------------------------------

      defp execute_tools(agent, tool_calls) do
        Enum.reduce(tool_calls, {[], []}, fn tool_call, {results, executed} ->
          tool_def = Enum.find(agent.tools, & &1.name == tool_call.name)

          if tool_def do
            try do
              result = tool_def.handler.(tool_call.parameters)

              executed_tool = %{
                id: tool_call.id,
                name: tool_call.name,
                params: tool_call.parameters,
                success: not Map.has_key?(result, :error),
                result: result
              }

              {[result | results], [executed_tool | executed]}
            rescue
              e ->
                error_tool = %{
                  id: tool_call.id,
                  name: tool_call.name,
                  params: tool_call.parameters,
                  success: false,
                  error: Exception.message(e)
                }

                {[%{error: Exception.message(e)} | results], [error_tool | executed]}
            end
          else
            error = %{error: "Unknown tool: #{tool_call.name}"}
            error_tool = %{id: tool_call.id, name: tool_call.name, success: false, error: error}

            {[error | results], [error_tool | executed]}
          end
        end)
      end

      # ----------------------------------------------------------------------------
      # Utilities
      # ----------------------------------------------------------------------------

      defp resource_name_from_module(module) do
        module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
      end

      defp enum_states(lifecycle) do
        lifecycle.states
        |> Enum.map(&to_string(&1.name))
      end

      defp serialize_record(record) do
        %{
          id: record.id,
          state: record.state,
          inserted_at: record.inserted_at,
          updated_at: record.updated_at
        }
      end

      defp serialize_transition(log) do
        %{
          id: log.id,
          event: log.event_name,
          from: log.from_state,
          to: log.to_state,
          actor: log.actor_label || log.actor_type,
          at: log.created_at,
          has_snapshot: log.state_snapshot != nil
        }
      end

      defp format_error(%Fosm.Errors.GuardFailed{guard: g, reason: r}) do
        base = "Guard '#{g}' failed"
        if r, do: "#{base}: #{r}", else: base
      end

      defp format_error(%Fosm.Errors.TerminalState{}), do: "Terminal state - no transitions allowed"

      defp format_error(%Fosm.Errors.InvalidTransition{} = e) do
        "Cannot #{e.event} from #{e.from}"
      end

      defp format_error(%Fosm.Errors.AccessDenied{}), do: "Access denied"
      defp format_error(e) when is_binary(e), do: e
      defp format_error(e), do: Exception.message(e)

      defp get_in(data, keys) do
        Enum.reduce(keys, data, fn key, acc ->
          case acc do
            nil -> nil
            %{} = map -> Map.get(map, key)
            _ -> nil
          end
        end)
      end

      defoverridable build_custom_tools: 0
    end
  end

  # ----------------------------------------------------------------------------
  # Response Module
  # ----------------------------------------------------------------------------

  defmodule Response do
    @moduledoc """
    Struct for agent responses.
    """
    defstruct [:text, :tool_calls, :reasoning, :usage, :model]

    @type t :: %__MODULE__{
      text: String.t(),
      tool_calls: [map()],
      reasoning: String.t() | nil,
      usage: map() | nil,
      model: String.t()
    }
  end
end
