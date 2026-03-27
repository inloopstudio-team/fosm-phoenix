defmodule FosmWeb.Router do
  @moduledoc """
  FOSM Admin routes and router configuration.
  
  Import this module in your application's router:
  
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
