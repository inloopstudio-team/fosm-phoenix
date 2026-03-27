defmodule Fosm.Repo do
  @moduledoc """
  Ecto repository for FOSM (Finite Object State Machine).
  """
  use Ecto.Repo,
    otp_app: :fosm,
    adapter: Ecto.Adapters.Postgres
end
