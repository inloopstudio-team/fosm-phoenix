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
    # Ensure repo is always set, even if config hasn't been merged yet
    base_config = Application.get_env(:fosm, Oban, [])
    Keyword.put(base_config, :repo, Fosm.Repo)
  end
end
