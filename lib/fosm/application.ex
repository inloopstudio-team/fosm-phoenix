defmodule Fosm.Application do
  @moduledoc """
  OTP Application for FOSM.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Fosm.Repo,
      {Oban, oban_config()},
      Fosm.Current,  # RBAC cache
      Fosm.Registry,  # Model registry
      Fosm.Agent.Session  # Agent conversation persistence
    ]

    opts = [strategy: :one_for_one, name: Fosm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp oban_config do
    Application.get_env(:fosm, Oban, [repo: Fosm.Repo, queues: [default: 10]])
  end
end
