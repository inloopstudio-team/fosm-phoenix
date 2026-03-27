defmodule FosmWeb.Endpoint do
  @moduledoc """
  Minimal endpoint module for FOSM web interface.
  
  This endpoint is used for:
  - Verified routes (~p sigil)
  - URL generation in emails/notifications
  
  Host applications should configure this in their config:
  
      config :fosm, FosmWeb.Endpoint,
        url: [host: "localhost", port: 4000, scheme: "http"]
  """
  
  use Phoenix.Endpoint,
    otp_app: :fosm,
    adapter: Bandit.PhoenixAdapter

  # Serve static assets at /fosm/assets
  plug Plug.Static,
    at: "/fosm/assets",
    from: :fosm,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  
  # Session management
  plug Plug.Session,
    store: :cookie,
    key: "_fosm_session",
    signing_salt: "FOSM_SECRET"

  # The router
  plug FosmWeb.Router
end
