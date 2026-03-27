defmodule Fosm do
  @moduledoc """
  FOSM (Finite Object State Machine) for Phoenix.

  A complete state machine engine with:
  - Lifecycle DSL for defining states, events, guards, and side effects
  - RBAC with per-process caching
  - Comprehensive audit trails with snapshots
  - AI agent integration
  - Admin UI with LiveView

  ## Configuration

  Configure FOSM in your config/config.exs:

      config :fosm,
        repo: MyApp.Repo,
        transition_log_strategy: :sync,  # :sync, :async_job, :buffer
        enable_webhooks: true,
        default_oban_queue: :default

  ## Usage

      defmodule MyApp.Invoice do
        use Ecto.Schema
        use Fosm.Lifecycle

        schema "invoices" do
          field :state, :string
          field :amount, :decimal
          timestamps()
        end

        lifecycle do
          state :draft, initial: true
          state :sent
          state :paid, terminal: true

          event :send, from: :draft, to: :sent
          event :pay, from: :sent, to: :paid

          guard :positive_amount, on: :send do
            invoice.amount > 0
          end
        end
      end
  """

  @doc """
  Returns the FOSM configuration.
  """
  def config do
    Application.get_env(:fosm, Fosm, [])
    |> Enum.into(%{})
    |> Map.merge(default_config())
  end

  @doc """
  Returns a specific configuration value.
  """
  def config(key, default \\ nil) do
    Map.get(config(), key, default)
  end

  @doc """
  Updates the FOSM configuration at runtime.
  """
  def put_config(key, value) do
    current = Application.get_env(:fosm, Fosm, [])
    Application.put_env(:fosm, Fosm, Keyword.put(current, key, value))
  end

  defp default_config do
    %{
      repo: nil,
      transition_log_strategy: :sync,
      enable_webhooks: false,
      webhook_secret_header: "X-FOSM-Signature",
      default_oban_queue: :default,
      transition_buffer_interval_ms: 1000,
      transition_buffer_max_size: 100,
      rbac_cache_ttl_seconds: 300
    }
  end
end
