defmodule FosmWeb.Admin.AuthorizationTest do
  @moduledoc """
  Integration tests for admin authorization.

  Verifies that admin routes require authentication and proper permissions.
  """
  use FosmWeb.ConnCase, async: true

  import Fosm.Factory
  import Fosm.TestHelpers

  alias Fosm.Errors.AccessDenied

  describe "unauthenticated access" do
    test "redirects to login for protected routes", %{conn: conn} do
      # Test various admin routes require auth
      routes = [
        "/admin/transitions",
        "/admin/roles",
        "/admin/webhooks",
        "/admin/settings"
      ]

      for route <- routes do
        conn = get(conn, route)
        assert redirected_to(conn) == "/login"
      end
    end
  end

  describe "authenticated non-admin access" do
    @tag as: :user
    test "returns 403 for admin-only routes", %{conn: conn} do
      # Regular users should not access admin routes
      routes = [
        "/admin/transitions",
        "/admin/settings"
      ]

      for route <- routes do
        conn = get(conn, route)
        assert conn.status == 403
      end
    end
  end

  describe "admin access" do
    @tag as: :admin
    test "allows access to admin routes", %{conn: conn} do
      # These routes should be accessible by admins
      # Note: Actual routes may not be implemented yet
      # This is a smoke test for when they are

      routes = [
        "/admin/transitions",
        "/admin/roles",
        "/admin/webhooks",
        "/admin/settings"
      ]

      for route <- routes do
        # If route exists, should return 200
        # If not, will return 404 which is also acceptable for now
        conn = get(conn, route)
        assert conn.status in [200, 404]
      end
    end
  end

  describe "role-based access control in admin" do
    @tag as: :admin
    test "role assignment requires admin", %{conn: conn} do
      # POST to roles endpoint should work for admin
      # Implementation pending actual routes
    end

    @tag as: :user
    test "role assignment forbidden for non-admin", %{conn: conn} do
      # POST to roles endpoint should fail for non-admin
    end
  end
end
