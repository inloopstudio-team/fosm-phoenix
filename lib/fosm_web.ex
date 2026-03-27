defmodule FosmWeb do
  @moduledoc """
  Web interface for FOSM Admin.

  This module defines the core Phoenix components used by the FOSM Admin UI.
  """

  @doc """
  Returns the list of static paths for FOSM web assets.
  """
  def static_paths, do: ~w(assets fonts images favicon.ico robots.txt)

  def html do
    quote do
      use Phoenix.Component

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      # Include general helpers for rendering HTML
      unquote(html_helpers())
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {FosmWeb.Layouts, :app}

      unquote(html_helpers())

      # Enable verified routes for ~p sigil
      use Phoenix.VerifiedRoutes,
        endpoint: FosmWeb.Endpoint,
        router: FosmWeb.Router
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Phoenix.LiveView.Router

      # Enable verified routes
      use Phoenix.VerifiedRoutes,
        endpoint: FosmWeb.Endpoint,
        router: FosmWeb.Router,
        statics: FosmWeb.static_paths()
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :json],
        layouts: [html: FosmWeb.Layouts]

      import Plug.Conn
    end
  end

  defp html_helpers do
    quote do
      # HTML escaping functionality
      import Phoenix.HTML
      # Core UI components
      import FosmWeb.CoreComponents

      # Shortcut for generating JS commands
      alias Phoenix.LiveView.JS

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  defp verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: FosmWeb.Endpoint,
        router: FosmWeb.Router,
        statics: FosmWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/live_view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
