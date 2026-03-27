defmodule FosmWeb.Admin.RolesLiveTest do
  @moduledoc """
  LiveView tests for Roles Management admin interface.

  Tests the role assignment UI including:
  - Listing current role assignments
  - Granting new roles
  - Revoking existing roles
  - User search functionality
  - Cache invalidation on role changes
  """
  use Fosm.LiveViewCase, async: false

  import Fosm.Factory
  import Fosm.TestHelpers

  alias Fosm.Current

  describe "roles list page" do
    @tag as: :admin
    test "displays role assignments", %{conn: conn} do
      # Create some role assignments
      user = insert!(:user)
      invoice = build(:invoice)

      assign_role!(user, invoice, :owner)

      # Visit roles page
      {:ok, view, html} = live(conn, "/admin/roles")

      # Should display the resource type
      assert html =~ "Role Management"
      assert html =~ "Fosm.Invoice"
    end

    @tag as: :admin
    test "shows empty state when no roles", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin/roles")

      assert html =~ "No role assignments"
    end
  end

  describe "granting roles" do
    @tag as: :admin
    test "can grant type-level role", %{conn: conn} do
      user = insert!(:user)

      {:ok, view, _html} = live(conn, "/admin/roles")

      # Fill grant form
      html = fill_form(view, "#grant-role-form",
        user_id: user.id,
        user_type: "Fosm.User",
        resource_type: "Fosm.Invoice",
        role: "viewer"
      )

      # Submit form
      submit_form(view, "#grant-role-form",
        user_id: user.id,
        user_type: "Fosm.User",
        resource_type: "Fosm.Invoice",
        role: "viewer"
      )

      # Verify role was granted
      roles = Current.roles_for(user, "Fosm.Invoice", nil)
      assert :viewer in roles
    end

    @tag as: :admin
    test "can grant record-level role", %{conn: conn} do
      user = insert!(:user)
      invoice = insert!(:invoice)

      {:ok, view, _html} = live(conn, "/admin/roles")

      # Select resource and grant role
      submit_form(view, "#grant-role-form",
        user_id: user.id,
        resource_type: "Fosm.Invoice",
        resource_id: invoice.id,
        role: "editor"
      )

      # Verify role was granted
      roles = Current.roles_for(user, "Fosm.Invoice", invoice.id)
      assert :editor in roles
    end

    @tag as: :admin
    test "invalidates cache when granting role", %{conn: conn} do
      user = insert!(:user)

      # Prime cache with empty roles
      Current.roles_for(user, "Fosm.Invoice", nil)

      {:ok, view, _html} = live(conn, "/admin/roles")

      # Grant role
      submit_form(view, "#grant-role-form",
        user_id: user.id,
        resource_type: "Fosm.Invoice",
        role: "owner"
      )

      # Verify cache was invalidated and new role is visible
      roles = Current.roles_for(user, "Fosm.Invoice", nil)
      assert :owner in roles
    end
  end

  describe "revoking roles" do
    @tag as: :admin
    test "can revoke existing role", %{conn: conn} do
      user = insert!(:user)
      invoice = insert!(:invoice)

      # First grant a role
      assignment = assign_role!(user, invoice, :owner)

      {:ok, view, _html} = live(conn, "/admin/roles")

      # Click revoke button
      view
      |> element("#revoke-role-#{assignment.id}")
      |> render_click()

      # Verify role was revoked
      roles = Current.roles_for(user, "Fosm.Invoice", invoice.id)
      refute :owner in roles
    end

    @tag as: :admin
    test "invalidates cache when revoking role", %{conn: conn} do
      user = insert!(:user)
      assignment = assign_type_role!(user, "Fosm.Invoice", :owner)

      # Prime cache
      Current.roles_for(user, "Fosm.Invoice", nil)

      {:ok, view, _html} = live(conn, "/admin/roles")

      # Revoke role
      view
      |> element("#revoke-role-#{assignment.id}")
      |> render_click()

      # Verify cache was invalidated
      roles = Current.roles_for(user, "Fosm.Invoice", nil)
      refute :owner in roles
    end
  end

  describe "user search" do
    @tag as: :admin
    test "can search for users", %{conn: conn} do
      # Create users with distinct emails
      user1 = insert!(:user, email: "alice@example.com")
      user2 = insert!(:user, email: "bob@example.com")

      {:ok, view, _html} = live(conn, "/admin/roles")

      # Type in search field
      html = fill_form(view, "#user-search-form", q: "alice")

      # Should show matching user
      assert html =~ "alice@example.com"
      refute html =~ "bob@example.com"
    end

    @tag as: :admin
    test "shows no results when no matches", %{conn: conn} do
      insert!(:user, email: "test@example.com")

      {:ok, view, _html} = live(conn, "/admin/roles")

      html = fill_form(view, "#user-search-form", q: "nonexistent")

      assert html =~ "No users found"
    end
  end

  describe "permission enforcement" do
    @tag as: :user
    test "non-admin cannot access roles page", %{conn: conn} do
      # Should redirect or show error
      {:ok, view, _html} = live(conn, "/admin/roles")

      # Should see access denied message or be redirected
      assert_redirect(view, "/")
    end
  end

  describe "error handling" do
    @tag as: :admin
    test "shows error for invalid user", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/roles")

      # Try to grant role to non-existent user
      html = submit_form(view, "#grant-role-form",
        user_id: 999999,
        resource_type: "Fosm.Invoice",
        role: "owner"
      )

      assert html =~ "User not found"
    end

    @tag as: :admin
    test "shows error for invalid resource", %{conn: conn} do
      user = insert!(:user)

      {:ok, view, _html} = live(conn, "/admin/roles")

      html = submit_form(view, "#grant-role-form",
        user_id: user.id,
        resource_type: "NonExistent.Resource",
        role: "owner"
      )

      assert html =~ "Invalid resource type"
    end
  end
end
