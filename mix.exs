defmodule Fosm.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dwarvesfoundation/fosm-phoenix"

  def project do
    [
      app: :fosm,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: "Finite Object State Machine for Phoenix",
      package: package(),
      docs: docs(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      mod: {Fosm.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core dependencies
      {:ecto, "~> 3.11"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},

      # Phoenix/LiveView (required for Admin UI)
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_html, "~> 4.0"},
      {:jason, "~> 1.4"},

      # Background jobs (optional)
      {:oban, "~> 2.17", optional: true},

      # HTTP client for webhooks (optional)
      {:req, "~> 0.5", optional: true},

      # Pagination for admin UI
      {:scrivener_ecto, "~> 2.0"},

      # String inflection for generators
      {:inflex, "~> 2.0"},

      # Development and testing
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_machina, "~> 2.7", only: :test},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "git_hooks.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      # Quality checks
      quality: ["format --check-formatted", "credo --strict", "compile --warnings-as-errors"],
      "quality.fix": ["format", "credo --strict"],
      "git_hooks.setup": ["cmd cp .git_hooks/pre-commit .git/hooks/pre-commit", "cmd cp .git_hooks/pre-push .git/hooks/pre-push", "cmd chmod +x .git/hooks/pre-commit .git/hooks/pre-push"]
    ]
  end

  defp package do
    [
      name: :fosm,
      files: ~w(lib config priv .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "Fosm",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "FOSM_PHOENIX_IMPLEMENTATION.md",
        "FOSM_PHOENIX_COMPLETE_SPEC.md",
        "guides/getting_started.md",
        "guides/code_quality.md",
        "examples/invoice_workflow.ex": [filename: "example_invoice_workflow", title: "Example: Invoice Workflow"]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end
end
