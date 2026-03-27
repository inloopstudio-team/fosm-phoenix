defmodule Mix.Tasks.Fosm.Graph.Generate do
  @moduledoc """
  Generates visual state machine diagrams from FOSM lifecycle definitions.

  ## Usage

      # Generate graph for a specific model
      mix fosm.graph.generate MyApp.Fosm.Invoice --output docs/invoices.dot

      # Generate all FOSM models
      mix fosm.graph.generate --all --output docs/fosm_graphs/

      # Generate system overview (all models combined)
      mix fosm.graph.generate --system --output docs/system_overview.dot

  ## Output Formats

    * `--format dot` - Graphviz DOT format (default)
    * `--format mermaid` - Mermaid flowchart syntax
    * `--format json` - JSON representation of the state machine
    * `--format html` - Self-contained HTML with embedded visualization

  ## Options

    * `--model` - Specific FOSM module to generate graph for
    * `--all` - Generate graphs for all registered FOSM models
    * `--system` - Generate combined system overview
    * `--output` - Output file path (required)
    * `--format` - Output format: dot, mermaid, json, html (default: dot)
    * `--direction` - Layout direction: tb (top-bottom), lr (left-right), rl, bt (default: tb)

  ## Examples

      # Generate Mermaid diagram for quick README embedding
      mix fosm.graph.generate MyApp.Fosm.Invoice --format mermaid --output README.mmd

      # Generate HTML report with all models
      mix fosm.graph.generate --all --format html --output fosm_report.html

      # Generate JSON for programmatic consumption
      mix fosm.graph.generate --system --format json --output fosm_schema.json
  """

  use Mix.Task

  @shortdoc "Generate state machine visualizations"

  @switches [
    model: :string,
    all: :boolean,
    system: :boolean,
    output: :string,
    format: :string,
    direction: :string
  ]

  @aliases [
    m: :model,
    o: :output,
    f: :format
  ]

  @impl true
  def run(args) do
    {opts, _} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    # Validate required options
    output = Keyword.get(opts, :output)

    if is_nil(output) or output == "" do
      Mix.raise("--output is required. Example: --output docs/graph.dot")
    end

    format = String.to_atom(Keyword.get(opts, :format, "dot"))
    direction = Keyword.get(opts, :direction, "tb")

    # Compile the project to ensure modules are available
    Mix.Task.run("compile")

    cond do
      Keyword.get(opts, :system, false) ->
        generate_system_overview(output, format, direction)

      Keyword.get(opts, :all, false) ->
        generate_all_models(output, format, direction)

      model = Keyword.get(opts, :model) ->
        generate_single_model(model, output, format, direction)

      true ->
        Mix.raise("""
        Please specify one of:
          --model Module.Name    (generate for specific model)
          --all                  (generate for all models)
          --system               (generate combined overview)
        """)
    end
  end

  defp generate_single_model(model_name, output, format, direction) do
    module = resolve_module(model_name)

    unless fosm_module?(module) do
      Mix.raise("""
      #{model_name} does not appear to be a FOSM module.

      Ensure the module:
        1. Uses `Fosm.Lifecycle`
        2. Defines a `lifecycle do...end` block
        3. Has been compiled (run `mix compile` first)
      """)
    end

    lifecycle = extract_lifecycle(module)
    content = render(lifecycle, format, direction)

    write_output(output, content, format)
    Mix.shell().info("✅ Generated #{format} graph for #{model_name} -> #{output}")
  end

  defp generate_all_models(output_dir, format, direction) do
    models = find_all_fosm_modules()

    if models == [] do
      Mix.raise("No FOSM modules found. Ensure modules use `Fosm.Lifecycle`.")
    end

    # Create output directory if needed
    File.mkdir_p!(output_dir)

    # Generate individual graphs
    Enum.each(models, fn module ->
      lifecycle = extract_lifecycle(module)
      file_name = graph_file_name(module, format)
      file_path = Path.join(output_dir, file_name)
      content = render(lifecycle, format, direction)

      write_output(file_path, content, format)
    end)

    # Generate index file
    generate_index(models, output_dir, format)

    Mix.shell().info("✅ Generated #{length(models)} graphs in #{output_dir}")
  end

  defp generate_system_overview(output, format, direction) do
    models = find_all_fosm_modules()

    if models == [] do
      Mix.raise("No FOSM modules found for system overview.")
    end

    lifecycles = Enum.map(models, &extract_lifecycle/1)

    content =
      case format do
        :dot -> render_system_dot(lifecycles, direction)
        :mermaid -> render_system_mermaid(lifecycles, direction)
        :json -> render_system_json(lifecycles)
        :html -> render_system_html(lifecycles, direction)
        _ -> Mix.raise("Unsupported format: #{format}")
      end

    write_output(output, content, format)
    Mix.shell().info("✅ Generated system overview (#{length(models)} models) -> #{output}")
  end

  # ----------------------------------------------------------------------------
  # Module Discovery
  # ----------------------------------------------------------------------------

  defp resolve_module(name) when is_binary(name) do
    name
    |> String.split(".")
    |> Enum.map(&Macro.camelize/1)
    |> Module.concat()
  end

  defp resolve_module(name) when is_atom(name), do: name

  defp fosm_module?(module) do
    Code.ensure_loaded?(module) &&
      function_exported?(module, :fosm_lifecycle, 0)
  end

  defp find_all_fosm_modules do
    :code.all_loaded()
    |> Enum.map(fn {mod, _} -> mod end)
    |> Enum.filter(&fosm_module?/1)
  end

  # ----------------------------------------------------------------------------
  # Lifecycle Extraction
  # ----------------------------------------------------------------------------

  defp extract_lifecycle(module) do
    lifecycle = module.fosm_lifecycle()

    %{
      module: module,
      name: module |> Module.split() |> List.last(),
      full_name: inspect(module),
      states: lifecycle.states || [],
      events: lifecycle.events || [],
      guards: lifecycle.guards || [],
      side_effects: lifecycle.side_effects || [],
      initial_state: lifecycle.initial_state,
      terminal_states: lifecycle.terminal_states || []
    }
  end

  # ----------------------------------------------------------------------------
  # Rendering
  # ----------------------------------------------------------------------------

  defp render(lifecycle, :dot, direction) do
    render_dot(lifecycle, direction)
  end

  defp render(lifecycle, :mermaid, direction) do
    render_mermaid(lifecycle, direction)
  end

  defp render(lifecycle, :json, _direction) do
    render_json(lifecycle)
  end

  defp render(lifecycle, :html, direction) do
    render_html(lifecycle, direction)
  end

  defp render(lifecycle, format, _direction) do
    Mix.raise("Unsupported format: #{format}")
  end

  # ----------------------------------------------------------------------------
  # DOT Format (Graphviz)
  # ----------------------------------------------------------------------------

  defp render_dot(lifecycle, direction) do
    states_dot = Enum.map_join(lifecycle.states, "\n  ", &render_state_node/1)
    events_dot = Enum.map_join(lifecycle.events, "\n  ", &render_event_edge(&1, lifecycle))

    # Add guard annotations
    guards_dot =
      Enum.map_join(lifecycle.guards, "\n  ", fn guard ->
        label = if guard.reason, do: "\\n(#{guard.reason})", else: ""

        "#{guard.event} -> #{guard.event}_guard [style=dashed, color=orange, label=\"guard#{label}\"]"
      end)

    # Add side effect annotations
    effects_dot =
      Enum.map_join(lifecycle.side_effects, "\n  ", fn effect ->
        defer_label = if effect.defer, do: " (async)", else: ""

        "#{effect.event} -> #{effect.event}_effect [style=dashed, color=blue, label=\"effect#{defer_label}\"]"
      end)

    """
    digraph #{lifecycle.name} {
      rankdir=#{direction};
      node [shape=box, style=rounded, fontname="Helvetica"];
      edge [fontname="Helvetica", fontsize=10];

      // States
      #{states_dot}

      // Events (transitions)
      #{events_dot}

      // Guards (validation logic)
      #{if lifecycle.guards != [], do: guards_dot, else: "// No guards defined"}

      // Side Effects (actions)
      #{if lifecycle.side_effects != [], do: effects_dot, else: "// No side effects defined"}
    }
    """
  end

  defp render_state_node(state) do
    attrs =
      case state.type do
        :initial ->
          "[shape=ellipse, style=filled, fillcolor=lightgreen, label=\"#{state.name}\\n(initial)\"]"

        :terminal ->
          "[shape=ellipse, style=filled, fillcolor=lightcoral, label=\"#{state.name}\\n(terminal)\"]"

        _ ->
          "[label=\"#{state.name}\"]"
      end

    "#{state.name} #{attrs};"
  end

  defp render_event_edge(event, lifecycle) do
    from_states = if is_list(event.from), do: event.from, else: [event.from]

    Enum.map_join(from_states, "\n  ", fn from ->
      guard_note = if has_guard?(lifecycle, event.name), do: " (has guard)", else: ""
      effect_note = if has_side_effect?(lifecycle, event.name), do: " (has effect)", else: ""
      label = "#{event.name}#{guard_note}#{effect_note}"

      "#{from} -> #{event.to} [label=\"#{label}\"];"
    end)
  end

  defp has_guard?(lifecycle, event_name) do
    Enum.any?(lifecycle.guards, &(&1.event == event_name))
  end

  defp has_side_effect?(lifecycle, event_name) do
    Enum.any?(lifecycle.side_effects, &(&1.event == event_name))
  end

  # ----------------------------------------------------------------------------
  # Mermaid Format
  # ----------------------------------------------------------------------------

  defp render_mermaid(lifecycle, direction) do
    direction_str =
      case direction do
        "lr" -> "LR"
        "rl" -> "RL"
        "bt" -> "BT"
        _ -> "TD"
      end

    state_nodes =
      Enum.map_join(lifecycle.states, "\n    ", fn state ->
        case state.type do
          :initial -> "#{state.name}([#{state.name}])"
          :terminal -> "#{state.name}([#{state.name}])"
          _ -> "#{state_name}"
        end
      end)

    transitions =
      Enum.map_join(lifecycle.events, "\n    ", fn event ->
        from_states = if is_list(event.from), do: event.from, else: [event.from]

        Enum.map_join(from_states, "\n    ", fn from ->
          "#{from} -->|#{event.name}| #{event.to}"
        end)
      end)

    styles =
      Enum.map_join(lifecycle.states, "\n    ", fn state ->
        case state.type do
          :initial -> "style #{state.name} fill:#90EE90"
          :terminal -> "style #{state.name} fill:#F08080"
          _ -> ""
        end
      end)

    """
    ```mermaid
    flowchart #{direction_str}
        %% States
        #{state_nodes}

        %% Transitions
        #{transitions}

        %% Styling
        #{styles}
    ```
    """
  end

  # ----------------------------------------------------------------------------
  # JSON Format
  # ----------------------------------------------------------------------------

  defp render_json(lifecycle) do
    Jason.encode!(
      %{
        name: lifecycle.name,
        module: lifecycle.full_name,
        initial_state: lifecycle.initial_state,
        terminal_states: lifecycle.terminal_states,
        states:
          Enum.map(lifecycle.states, fn s ->
            %{
              name: s.name,
              type: s.type,
              initial: s.type == :initial,
              terminal: s.type == :terminal
            }
          end),
        events:
          Enum.map(lifecycle.events, fn e ->
            %{
              name: e.name,
              from: e.from,
              to: e.to
            }
          end),
        guards:
          Enum.map(lifecycle.guards, fn g ->
            %{
              name: g.name,
              event: g.event,
              reason: g.reason
            }
          end),
        side_effects:
          Enum.map(lifecycle.side_effects, fn s ->
            %{
              name: s.name,
              event: s.event,
              defer: s.defer
            }
          end)
      },
      pretty: true
    )
  end

  # ----------------------------------------------------------------------------
  # HTML Format (Self-contained)
  # ----------------------------------------------------------------------------

  defp render_html(lifecycle, direction) do
    dot_content = render_dot(lifecycle, direction)
    mermaid_content = render_mermaid(lifecycle, direction)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>FOSM: #{lifecycle.name}</title>
      <script src="https://unpkg.com/mermaid@10/dist/mermaid.min.js"></script>
      <script src="https://unpkg.com/@hpcc-js/wasm@2/dist/graphviz.umd.js"></script>
      <style>
        body { font-family: system-ui, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; }
        h1 { border-bottom: 2px solid #333; }
        .section { margin: 20px 0; }
        pre { background: #f5f5f5; padding: 15px; overflow-x: auto; }
        .mermaid { text-align: center; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background: #f0f0f0; }
        .state-initial { background: #90EE90; }
        .state-terminal { background: #F08080; }
      </style>
    </head>
    <body>
      <h1>#{lifecycle.name} State Machine</h1>
      <p><strong>Module:</strong> <code>#{lifecycle.full_name}</code></p>

      <div class="section">
        <h2>State Diagram</h2>
        <div class="mermaid">
    #{String.replace(mermaid_content, "```mermaid\n", "") |> String.replace("\n```", "")}
        </div>
      </div>

      <div class="section">
        <h2>States</h2>
        <table>
          <tr><th>Name</th><th>Type</th></tr>
          #{Enum.map_join(lifecycle.states, "\n          ", fn s ->
      type_class = case s.type do
        :initial -> "state-initial"
        :terminal -> "state-terminal"
        _ -> ""
      end
      "<tr class=\"#{type_class}\"><td>#{s.name}</td><td>#{s.type}</td></tr>"
    end)}
        </table>
      </div>

      <div class="section">
        <h2>Events</h2>
        <table>
          <tr><th>Name</th><th>From</th><th>To</th><th>Guards</th><th>Effects</th></tr>
          #{Enum.map_join(lifecycle.events, "\n          ", fn e ->
      guards = lifecycle.guards |> Enum.filter(&(&1.event == e.name)) |> Enum.map(& &1.name) |> Enum.join(", ")
      effects = lifecycle.side_effects |> Enum.filter(&(&1.event == e.name)) |> Enum.map(& &1.name) |> Enum.join(", ")
      from_str = if is_list(e.from), do: Enum.join(e.from, ", "), else: e.from
      "<tr><td>#{e.name}</td><td>#{from_str}</td><td>#{e.to}</td><td>#{guards}</td><td>#{effects}</td></tr>"
    end)}
        </table>
      </div>

      <div class="section">
        <h2>DOT Source</h2>
        <pre>#{escape_html(dot_content)}</pre>
      </div>

      <script>
        mermaid.initialize({ startOnLoad: true });
      </script>
    </body>
    </html>
    """
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  # ----------------------------------------------------------------------------
  # System Overview Rendering
  # ----------------------------------------------------------------------------

  defp render_system_dot(lifecycles, direction) do
    modules = Enum.map_join(lifecycles, "\n\n", &render_dot(&1, direction))

    # Create cluster overview
    clusters =
      Enum.map_join(lifecycles, "\n  ", fn lc ->
        """
        subgraph cluster_#{lc.name} {
          label="#{lc.name}";
          color=blue;
          #{Enum.map_join(lc.states, "; ", & &1.name)}
        }
        """
      end)

    """
    digraph FOSM_System {
      rankdir=#{direction};
      compound=true;
      node [shape=box, style=rounded, fontname="Helvetica"];

      // Individual state machines
      #{modules}

      // System clusters
      #{clusters}
    }
    """
  end

  defp render_system_mermaid(lifecycles, direction) do
    direction_str =
      case direction do
        "lr" -> "LR"
        "rl" -> "RL"
        "bt" -> "BT"
        _ -> "TD"
      end

    subgraphs =
      Enum.map_join(lifecycles, "\n  ", fn lc ->
        transitions =
          Enum.map_join(lc.events, "\n    ", fn e ->
            from_str = if is_list(e.from), do: hd(e.from), else: e.from
            "#{lc.name}_#{from_str} -->|#{e.name}| #{lc.name}_#{e.to}"
          end)

        """
        subgraph #{lc.name}
          #{transitions}
        end
        """
      end)

    """
    ```mermaid
    flowchart #{direction_str}
      #{subgraphs}
    ```
    """
  end

  defp render_system_json(lifecycles) do
    Jason.encode!(
      %{
        system: "FOSM",
        models:
          Enum.map(lifecycles, fn lc ->
            %{
              name: lc.name,
              module: lc.full_name,
              states: Enum.map(lc.states, & &1.name),
              events: Enum.map(lc.events, & &1.name),
              initial_state: lc.initial_state,
              terminal_states: lc.terminal_states
            }
          end),
        total_models: length(lifecycles),
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      pretty: true
    )
  end

  defp render_system_html(lifecycles, direction) do
    individual_diagrams =
      Enum.map_join(lifecycles, "\n<hr>\n", fn lc ->
        mermaid = render_mermaid(lc, direction)

        """
        <h3>#{lc.name}</h3>
        <div class="mermaid">
        #{String.replace(mermaid, "```mermaid\n", "") |> String.replace("\n```", "")}
        </div>
        """
      end)

    summary_table =
      Enum.map_join(lifecycles, "\n    ", fn lc ->
        """
        <tr>
          <td><a href=\"#\">#{lc.name}</a></td>
          <td>#{length(lc.states)}</td>
          <td>#{length(lc.events)}</td>
          <td>#{lc.initial_state}</td>
          <td>#{Enum.join(lc.terminal_states, ", ")}</td>
        </tr>
        """
      end)

    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>FOSM System Overview</title>
      <script src="https://unpkg.com/mermaid@10/dist/mermaid.min.js"></script>
      <style>
        body { font-family: system-ui, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; }
        h1 { border-bottom: 2px solid #333; }
        .section { margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background: #f0f0f0; }
        .mermaid { text-align: center; margin: 20px 0; }
        hr { margin: 40px 0; border: 1px solid #ddd; }
      </style>
    </head>
    <body>
      <h1>FOSM System Overview</h1>
      <p>Total Models: #{length(lifecycles)}</p>

      <div class="section">
        <h2>Summary</h2>
        <table>
          <tr>
            <th>Model</th>
            <th>States</th>
            <th>Events</th>
            <th>Initial</th>
            <th>Terminal</th>
          </tr>
          #{summary_table}
        </table>
      </div>

      <div class="section">
        <h2>State Machines</h2>
        #{individual_diagrams}
      </div>

      <script>
        mermaid.initialize({ startOnLoad: true });
      </script>
    </body>
    </html>
    """
  end

  # ----------------------------------------------------------------------------
  # File Operations
  # ----------------------------------------------------------------------------

  defp graph_file_name(module, format) do
    name = module |> Module.split() |> List.last() |> Macro.underscore()
    "#{name}.#{format_ext(format)}"
  end

  defp format_ext(:dot), do: "dot"
  defp format_ext(:mermaid), do: "mmd"
  defp format_ext(:json), do: "json"
  defp format_ext(:html), do: "html"
  defp format_ext(_), do: "txt"

  defp write_output(path, content, _format) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    File.write!(path, content)
  end

  defp generate_index(models, output_dir, format) do
    model_links =
      Enum.map_join(models, "\n", fn mod ->
        file = graph_file_name(mod, format)
        name = mod |> Module.split() |> List.last()
        "- [#{name}](#{file})"
      end)

    content = """
    # FOSM State Machines

    Generated at: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    ## Models

    #{model_links}

    ## Format

    These diagrams are in #{format} format.
    """

    File.write!(Path.join(output_dir, "README.md"), content)
  end
end
