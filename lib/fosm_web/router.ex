defmodule FosmWeb.Router do
  @moduledoc """
  FOSM Admin routes and router configuration.
  
  This is a router for the FOSM Admin UI. To use it in your application:
  
      defmodule MyAppWeb.Router do
        use Phoenix.Router
        
        import FosmWeb.Router
        
        scope "/", MyAppWeb do
          # Your routes...
        end
        
        # Add FOSM admin routes
        fosm_admin_routes()
      end
  """

  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FosmWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :fosm_admin do
    # Add any FOSM-specific plugs here
    # e.g., plug :require_admin_user
  end

  scope "/fosm/admin", FosmWeb.Admin do
    pipe_through [:browser, :fosm_admin]

    live "/", DashboardLive, :index
    live "/apps/:slug", AppLive, :show
    live "/transitions", TransitionsLive, :index
    live "/roles", RolesLive, :index
    live "/roles/:resource_type/:resource_id", RolesLive, :show
    live "/webhooks", WebhooksLive, :index
    live "/webhooks/new", WebhooksLive, :new
    live "/webhooks/:id/edit", WebhooksLive, :edit
    live "/settings", SettingsLive, :index
    live "/agent/:slug", Agent.ChatLive, :show
    live "/agent/:slug/explorer", Agent.ExplorerLive, :show
  end

  defmacro fosm_admin_routes do
    quote do
      scope "/fosm/admin", FosmWeb.Admin do
        pipe_through [:browser, :fosm_admin]

        live "/", DashboardLive, :index
        live "/apps/:slug", AppLive, :show
        live "/transitions", TransitionsLive, :index
        live "/roles", RolesLive, :index
        live "/roles/:resource_type/:resource_id", RolesLive, :show
        live "/webhooks", WebhooksLive, :index
        live "/webhooks/new", WebhooksLive, :new
        live "/webhooks/:id/edit", WebhooksLive, :edit
        live "/settings", SettingsLive, :index
      end
    end
  end

  @doc """
  Generates admin pipeline configuration.
  
  Add to your router's pipeline definitions:
  
      pipeline :fosm_admin do
        plug :require_fosm_admin
      end
      
      defp require_fosm_admin(conn, _opts) do
        FosmWeb.Router.require_admin_user(conn, [])
      end
  """
  def require_admin_user(conn, _opts) do
    # This is a placeholder that can be overridden
    # Users should implement their own authorization logic
    conn
  end
end
