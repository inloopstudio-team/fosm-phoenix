defmodule Mix.Tasks.Fosm.Gen.App do
  @moduledoc """
  Generates a complete FOSM application with model, migration, controller, and LiveViews.

  ## Usage

      mix fosm.gen.app MyApp.Invoice \
        --fields "number:string amount:decimal status:string" \
        --states "draft:initial sent paid:terminal void:terminal" \
        --access "admin,accountant"

  ## Options

    * `--fields` - Comma-separated list of field:type pairs (e.g., "name:string amount:decimal")
    * `--states` - Comma-separated list of states with optional :initial or :terminal markers
    * `--access` - Comma-separated list of roles that can access this resource
    * `--no-live` - Skip generating LiveView files
    * `--no-controller` - Skip generating controller
    * `--web` - Namespace for web modules (default: FosmWeb)

  ## Generated Files

  Generates 5-6 files depending on options:

    * `lib/my_app/fosm/invoice.ex` - The FOSM model with lifecycle DSL
    * `priv/repo/migrations/..._create_fosm_invoices.exs` - Database migration
    * `lib/fosm_web/controllers/invoice_controller.ex` - REST API controller
    * `lib/fosm_web/live/invoice_live/index.ex` - LiveView index page
    * `lib/fosm_web/live/invoice_live/show.ex` - LiveView detail page
    * Updates `lib/fosm_web/router.ex` - Adds routes
    * Updates or creates `CLAUDE.md` - FOSM instructions

  ## Field Types

  Supports standard Ecto types:

    * `:string`, `:text`, `:integer`, `:float`, `:decimal`, `:boolean`
    * `:date`, `:time`, `:datetime`, `:naive_datetime`, `:utc_datetime`
    * `:uuid`, `:binary`, `:array`, `:map`
    * References: `:references` (creates `belongs_to`)

  ## State Configuration

  States can be marked as:

    * `:initial` - The starting state for new records (exactly one required)
    * `:terminal` - States that cannot transition out of (can have multiple)

  Example: `draft:initial,active,paid:terminal,void:terminal`

  ## Access Control

  Roles specified in `--access` are used for:

    * RBAC guard generation in the lifecycle
    * Route pipeline authorization
    * Admin UI role management
  """

  use Mix.Task

  @shortdoc "Generates a complete FOSM application"

  @switches [
    fields: :string,
    states: :string,
    access: :string,
    live: :boolean,
    controller: :boolean,
    web: :string,
    binary_id: :boolean,
    migration: :boolean
  ]

  @aliases [
    f: :fields,
    s: :states,
    a: :access
  ]

  @impl true
  def run(args) do
    case OptionParser.parse!(args, strict: @switches, aliases: @aliases) do
      {opts, [schema_name]} ->
        generate(schema_name, opts)

      {_opts, []} ->
        Mix.raise("""
        Missing schema name.

        Usage: mix fosm.gen.app SchemaName [options]

        Example:
            mix fosm.gen.app MyApp.Invoice --fields "number:string amount:decimal"
        """)
    end
  end

  defp generate(schema_name, opts) do
    ctx = build_context(schema_name, opts)

    # Ensure the project compiles first
    Mix.Task.run("compile")

    # Create the files
    create_model_file(ctx)
    create_migration_file(ctx)

    if Keyword.get(opts, :controller, true) do
      create_controller_file(ctx)
    end

    if Keyword.get(opts, :live, true) do
      create_live_files(ctx)
    end

    update_router(ctx)
    inject_claude_instructions(ctx)

    Mix.shell().info("""
    ✅ Generated FOSM application for #{ctx.human_name}

    Files created:
      #{ctx.schema_file}
      #{ctx.migration_file}
      #{if ctx.controller_file, do: ctx.controller_file <> "\n  ", else: ""}#{if ctx.live_index_file, do: ctx.live_index_file <> "\n  " <> ctx.live_show_file <> "\n  ", else: ""}

    Next steps:
      1. Run migrations: mix ecto.migrate
      2. Review and customize the generated lifecycle in #{ctx.schema_file}
      3. Define events, guards, and side effects as needed
      4. Add the resource to your admin panel
    """)
  end

  defp build_context(schema_name, opts) do
    # Parse the schema name
    {base_module, resource_name} = parse_schema_name(schema_name)
    app_module = Module.concat([base_module])
    web_namespace = Keyword.get(opts, :web, "FosmWeb")
    web_module = Module.concat([web_namespace])

    # Parse fields
    fields = parse_fields(Keyword.get(opts, :fields, ""))

    # Parse states
    states = parse_states(Keyword.get(opts, :states, "draft:initial,completed:terminal"))

    # Parse access roles
    access_roles = parse_access(Keyword.get(opts, :access, ""))

    # Generate paths and file names
    resource_path = Macro.underscore(resource_name)
    plural = Inflex.pluralize(resource_path)
    schema_file = "lib/#{Macro.underscore(base_module)}/fosm/#{resource_path}.ex"
    migration_file = "priv/repo/migrations/#{timestamp()}_create_fosm_#{plural}.exs"
    controller_file = if Keyword.get(opts, :controller, true) do
      "lib/#{Macro.underscore(web_module)}/controllers/#{resource_path}_controller.ex"
    end
    live_index_file = if Keyword.get(opts, :live, true) do
      "lib/#{Macro.underscore(web_module)}/live/#{resource_path}_live/index.ex"
    end
    live_show_file = if Keyword.get(opts, :live, true) do
      "lib/#{Macro.underscore(web_module)}/live/#{resource_path}_live/show.ex"
    end
    live_form_file = if Keyword.get(opts, :live, true) do
      "lib/#{Macro.underscore(web_module)}/live/#{resource_path}_live/form_component.ex"
    end

    %{
      app_module: app_module,
      web_module: web_module,
      resource_name: resource_name,
      resource_path: resource_path,
      human_name: Inflex.camelize(resource_path),
      plural: plural,
      schema_module: Module.concat([base_module, :Fosm, resource_name]),
      schema_file: schema_file,
      migration_file: migration_file,
      controller_file: controller_file,
      controller_module: if(controller_file, do: Module.concat([web_module, :Controllers, resource_name <> "Controller"])),
      live_index_file: live_index_file,
      live_show_file: live_show_file,
      live_form_file: live_form_file,
      live_index_module: if(live_index_file, do: Module.concat([web_module, :Live, resource_name <> "Live", :Index])),
      live_show_module: if(live_show_file, do: Module.concat([web_module, :Live, resource_name <> "Live", :Show])),
      live_form_module: if(live_form_file, do: Module.concat([web_module, :Live, resource_name <> "Live", :FormComponent])),
      fields: fields,
      states: states,
      access_roles: access_roles,
      binary_id: Keyword.get(opts, :binary_id, false),
      timestamp: timestamp()
    }
  end

  defp parse_schema_name(name) do
    parts = name |> String.split(".") |> Enum.map(&Macro.camelize/1)
    resource = List.last(parts)
    base = parts |> Enum.drop(-1) |> Enum.join(".") |> String.to_atom() |> List.wrap() |> hd()

    if base == nil do
      Mix.raise("Schema name must include a module prefix (e.g., MyApp.Invoice)")
    end

    {base, resource}
  end

  defp parse_fields(fields_str) when is_binary(fields_str) do
    fields_str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn field_def ->
      case String.split(field_def, ":", parts: 2) do
        [name, type] ->
          type_atom = String.to_atom(type)
          {String.to_atom(name), type_atom}

        [name] ->
          {String.to_atom(name), :string}
      end
    end)
  end
  defp parse_fields(nil), do: []

  defp parse_states(states_str) when is_binary(states_str) do
    states_str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn state_def ->
      cond do
        String.contains?(state_def, ":initial") ->
          name = state_def |> String.replace(":initial", "") |> String.to_atom()
          %{name: name, type: :initial}

        String.contains?(state_def, ":terminal") ->
          name = state_def |> String.replace(":terminal", "") |> String.to_atom()
          %{name: name, type: :terminal}

        true ->
          %{name: String.to_atom(state_def), type: :normal}
      end
    end)
  end
  defp parse_states(nil), do: [%{name: :draft, type: :initial}, %{name: :completed, type: :terminal}]

  defp parse_access(access_str) when is_binary(access_str) do
    access_str
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_atom/1)
  end
  defp parse_access(nil), do: []

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()
    :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [year, month, day, hour, minute, second])
    |> IO.iodata_to_binary()
  end

  defp create_model_file(ctx) do
    Mix.Generator.create_directory(Path.dirname(ctx.schema_file))

    assigns = [
      module: ctx.schema_module,
      resource_name: ctx.resource_name,
      resource_path: ctx.resource_path,
      plural: ctx.plural,
      fields: ctx.fields,
      states: ctx.states,
      access_roles: ctx.access_roles,
      binary_id: ctx.binary_id,
      events: generate_default_events(ctx.states)
    ]

    template_path = template_path("model.ex")
    content = EEx.eval_file(template_path, assigns: assigns, trim: true)

    Mix.Generator.create_file(ctx.schema_file, content)
  end

  defp create_migration_file(ctx) do
    Mix.Generator.create_directory(Path.dirname(ctx.migration_file))

    assigns = [
      resource_path: ctx.resource_path,
      plural: ctx.plural,
      fields: ctx.fields,
      binary_id: ctx.binary_id
    ]

    template_path = template_path("migration.exs")
    content = EEx.eval_file(template_path, assigns: assigns, trim: true)

    Mix.Generator.create_file(ctx.migration_file, content)
  end

  defp create_controller_file(ctx) do
    Mix.Generator.create_directory(Path.dirname(ctx.controller_file))

    assigns = [
      module: ctx.controller_module,
      schema_module: ctx.schema_module,
      resource_path: ctx.resource_path,
      plural: ctx.plural,
      resource_name: ctx.resource_name,
      fields: ctx.fields
    ]

    template_path = template_path("controller.ex")
    content = EEx.eval_file(template_path, assigns: assigns, trim: true)

    Mix.Generator.create_file(ctx.controller_file, content)
  end

  defp create_live_files(ctx) do
    # Create directory
    live_dir = Path.dirname(ctx.live_index_file)
    Mix.Generator.create_directory(live_dir)

    # Index LiveView
    assigns_index = [
      module: ctx.live_index_module,
      schema_module: ctx.schema_module,
      resource_path: ctx.resource_path,
      plural: ctx.plural,
      resource_name: ctx.resource_name,
      fields: ctx.fields,
      states: ctx.states
    ]

    template_path = template_path("live_index.ex")
    content = EEx.eval_file(template_path, assigns: assigns_index, trim: true)
    Mix.Generator.create_file(ctx.live_index_file, content)

    # Show LiveView
    assigns_show = [
      module: ctx.live_show_module,
      schema_module: ctx.schema_module,
      resource_path: ctx.resource_path,
      plural: ctx.plural,
      resource_name: ctx.resource_name,
      fields: ctx.fields,
      states: ctx.states
    ]

    template_path = template_path("live_show.ex")
    content = EEx.eval_file(template_path, assigns: assigns_show, trim: true)
    Mix.Generator.create_file(ctx.live_show_file, content)

    # Form Component
    assigns_form = [
      module: ctx.live_form_module,
      schema_module: ctx.schema_module,
      resource_path: ctx.resource_path,
      resource_name: ctx.resource_name,
      fields: ctx.fields
    ]

    template_path = template_path("live_form.ex")
    content = EEx.eval_file(template_path, assigns: assigns_form, trim: true)
    Mix.Generator.create_file(ctx.live_form_file, content)
  end

  defp update_router(ctx) do
    router_path = "lib/#{Macro.underscore(ctx.web_module)}/router.ex"

    unless File.exists?(router_path) do
      Mix.shell().info("⚠️  Router file not found at #{router_path}. Skipping route injection.")
      return
    end

    router_content = File.read!(router_path)

    # Generate the routes to add
    routes = generate_routes(ctx)

    # Check if we already have fosm routes scope
    cond do
      String.contains?(router_content, "scope \"/fosm\"") ->
        inject_into_existing_fosm_scope(router_path, router_content, ctx, routes)

      String.contains?(router_content, "scope\"") ->
        inject_new_fosm_scope(router_path, router_content, ctx, routes)

      true ->
        Mix.shell().info("⚠️  Could not find appropriate location in router. Please add routes manually:")
        Mix.shell().info(routes)
    end
  end

  defp generate_routes(ctx) do
    """
    # FOSM #{ctx.human_name} routes
    live "/#{ctx.plural}", #{ctx.resource_name}Live.Index, :index
    live "/#{ctx.plural}/new", #{ctx.resource_name}Live.Index, :new
    live "/#{ctx.plural}/:id", #{ctx.resource_name}Live.Show, :show
    live "/#{ctx.plural}/:id/edit", #{ctx.resource_name}Live.Show, :edit
    """
  end

  defp inject_into_existing_fosm_scope(router_path, content, ctx, routes) do
    # Find the fosm scope and inject before its closing
    new_content = Regex.replace(
      ~r/(scope "\/fosm".*?do.*?)(\n\s*end)/s,
      content,
      "\\1\n      #{String.replace(routes, "\n", "\n      ")}\\2"
    )

    File.write!(router_path, new_content)
    Mix.shell().info("✅ Added routes to existing /fosm scope in router.ex")
  end

  defp inject_new_fosm_scope(router_path, content, ctx, routes) do
    # Find the last scope block and add after it
    new_content = Regex.replace(
      ~r/(.*scope.*do.*end)(.*)/s,
      content,
      "\\1\n\n  # FOSM resources\n  scope \"/fosm\" do\n    pipe_through :browser\n\n    #{String.replace(routes, "\n", "\n    ")}\n  end\\2",
      global: false
    )

    File.write!(router_path, new_content)
    Mix.shell().info("✅ Created new /fosm scope in router.ex")
  end

  defp inject_claude_instructions(ctx) do
    claude_md = Path.join(File.cwd!(), "CLAUDE.md")
    sentinel = "<!-- fosm:agent-instructions -->"

    section = generate_claude_section(ctx)

    if File.exists?(claude_md) && File.read!(claude_md) =~ sentinel do
      Mix.shell().info("📄 CLAUDE.md already has FOSM instructions")
      return
    end

    if File.exists?(claude_md) do
      File.write!(claude_md, "\n" <> section, [:append])
    else
      File.write!(claude_md, "# CLAUDE.md\n\n" <> section)
    end

    Mix.shell().info("✅ Updated CLAUDE.md with FOSM instructions")
  end

  defp generate_claude_section(ctx) do
    """
    #{sentinel}
    ## FOSM (#{ctx.resource_path})

    This project uses `fosm-phoenix` — a Finite Object State Machine engine.
    When working with #{ctx.human_name} or any FOSM resources, follow these conventions:

    ### Key FOSM Conventions

    1. **State changes ONLY via `fire!`** - Never direct Ecto updates to the state field
    2. **Guards are pure functions** - No side effects in guard blocks
    3. **Side effects can be deferred** - Use `defer: true` for cross-machine triggers
    4. **Every transition is logged** - Immutable audit trail in `fosm_transition_logs`
    5. **RBAC is role-based** - Check `#{ctx.app_module}.Fosm.Current.roles_for/3` for permissions

    ### #{ctx.human_name} State Machine

    States: #{Enum.map_join(ctx.states, ", ", & &1.name)}
    Initial: #{Enum.find(ctx.states, &(&1.type == :initial))[:name]}
    Terminal: #{Enum.filter(ctx.states, &(&1.type == :terminal)) |> Enum.map_join(", ", & &1.name)}

    ### Example Usage

    ```elixir
    # Create in initial state
    {:ok, <%= ctx.resource_path %>} = %<%= ctx.schema_module %>{}
      |> <%= ctx.schema_module %>.changeset(%{<%= example_fields(ctx.fields) %>state: :<%= get_initial_state(ctx.states) %>})
      |> <%= ctx.app_module %>.Repo.insert()

    # Transition via event
    {:ok, <%= ctx.resource_path %>} = <%= ctx.schema_module %>.fire!(<%= ctx.resource_path %>, :complete, actor: current_user)
    ```
    """
  end

  defp example_fields([]), do: ""
  defp example_fields(fields) do
    fields
    |> Enum.map(fn {name, _} -> "#{name}: ..." end)
    |> Enum.join(", ")
    |> Kernel.<>(", ")
  end

  defp get_initial_state(states) do
    case Enum.find(states, &(&1.type == :initial)) do
      nil -> "draft"
      state -> state[:name]
    end
  end

  defp generate_default_events(states) do
    initial = Enum.find(states, &(&1.type == :initial))[:name]
    terminals = Enum.filter(states, &(&1.type == :terminal)) |> Enum.map(& &1.name)
    normals = Enum.filter(states, &(&1.type == :normal)) |> Enum.map(& &1.name)

    cond do
      length(states) == 2 && initial && length(terminals) == 1 ->
        [%{name: :complete, from: initial, to: hd(terminals)}]

      length(states) >= 3 ->
        # Generate a flow: initial -> normal -> terminal
        all_non_terminals = [initial | normals]

        events =
          for i <- 0..(length(all_non_terminals)-2) do
            from = Enum.at(all_non_terminals, i)
            to = Enum.at(all_non_terminals, i + 1)
            %{name: String.to_atom("move_to_#{to}"), from: from, to: to}
          end

        # Add transitions from any non-terminal to terminal
        terminal_events =
          for terminal <- terminals,
              from <- all_non_terminals do
            %{name: String.to_atom("#{terminal}"), from: from, to: terminal}
          end

        events ++ terminal_events

      true ->
        []
    end
  end

  defp template_path(filename) do
    Path.join([:code.priv_dir(:fosm), "templates", filename])
  end
end
