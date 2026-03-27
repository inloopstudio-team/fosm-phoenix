defmodule Fosm.Application do
  @moduledoc """
  OTP Application for FOSM.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Fosm.Repo,
      {Oban, Application.fetch_env!(:fosm, Oban)},
      Fosm.Current,  # RBAC cache
      Fosm.Registry,  # Model registry
      Fosm.Agent.Session  # Agent conversation persistence
    ]

    opts = [strategy: :one_for_one, name: Fosm.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
