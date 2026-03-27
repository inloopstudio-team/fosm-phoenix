defmodule Fosm.Repo do
  @moduledoc """
  Ecto repository for FOSM (Finite Object State Machine).

  Supports multiple database adapters:
  - Ecto.Adapters.Postgres (production, CI/testing)
  - Ecto.Adapters.SQLite3 (development, embedded deployments)

  The adapter is configured via application config:

      config :fosm, Fosm.Repo,
        adapter: Ecto.Adapters.Postgres,  # or Ecto.Adapters.SQLite3
        # ...other options

  For SQLite in development:

      config :fosm, Fosm.Repo,
        adapter: Ecto.Adapters.SQLite3,
        database: "fosm_dev.db"
  """

  # Use Postgres as default at compile time, allow runtime override via config
  use Ecto.Repo,
    otp_app: :fosm,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Returns the configured adapter module for this repository.
  This reads from runtime config and may differ from compile-time default.
  """
  def adapter_module do
    config = config()
    Keyword.get(config, :adapter, Ecto.Adapters.Postgres)
  end

  @doc """
  Returns true if the repository is using PostgreSQL.
  """
  def postgres? do
    adapter_module() == Ecto.Adapters.Postgres
  end

  @doc """
  Returns true if the repository is using SQLite.
  """
  def sqlite? do
    adapter_module() == Ecto.Adapters.SQLite3
  end
end
