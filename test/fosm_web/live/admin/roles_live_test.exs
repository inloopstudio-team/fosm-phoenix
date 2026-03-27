defmodule FosmWeb.Admin.RolesLiveTest do
  use FosmWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Fosm.{Repo, RoleAssignment}

  describe "Roles LiveView" do
    setup do
      # Create test user (mock)
      assignment = Repo.insert!(%RoleAssignment{
        user_type: "User",
        user_id: "42",
        resource_type: "invoices",
        resource_id: "1",
        role_name: "owner"
      })

      {:ok, assignment: assignment}
    end

    test "renders role assignments", %{conn: conn, assignment: a} do
      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/roles")

      assert html =~ "Role Management"
      assert html =~ a.role_name
      assert html =~ a.user_id
    end

    test "filters by resource type via URL", %{conn: conn, assignment: a} do
      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/roles?resource_type=invoices")

      assert html =~ a.role_name
    end

    test "async user search with phx-change", %{conn: conn} do
      :meck.new(Fosm.TestModels.User, [:non_strict])
      :meck.expect(Fosm.TestModels.User, :__schema__, fn :fields -> [:id, :email, :name] end)
      
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/roles")

      # Select user type first
      lv
      |> element("input[value='User']")
      |> render_click()

      # Trigger search
      lv
      |> form("form", %{"user_query" => "john"})
      |> render_change()

      # Should show loading state initially
      assert render(lv) =~ "Searching..."

      :meck.unload(Fosm.TestModels.User)
    end

    test "grants role to selected user", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/roles?resource_type=invoices")

      # Simulate user selection
      lv
      |> element("div[phx-click='select_user']", "Test User")
      |> render_click(%{"user-id" => "123", "user-type" => "User"})

      # Submit grant form
      lv
      |> form("form[phx-submit='grant_role']", %{"role" => "editor"})
      |> render_submit()

      assert render(lv) =~ "Role granted successfully"
    end

    test "revokes role assignment", %{conn: conn, assignment: a} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/roles")

      lv
      |> element("button[phx-click='revoke_role']", "Revoke")
      |> render_click(%{"assignment_id" => a.id})

      assert render(lv) =~ "Role revoked successfully"
    end

    test "invalidates cache on role change", %{conn: conn} do
      :meck.new(Fosm.Current, [:non_strict])
      :meck.expect(Fosm.Current, :invalidate_for, fn _ -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/roles")

      lv
      |> element("button[phx-click='revoke_role']", "Revoke")
      |> render_click()

      assert :meck.called(Fosm.Current, :invalidate_for, [:_])

      :meck.unload(Fosm.Current)
    end
  end
end
