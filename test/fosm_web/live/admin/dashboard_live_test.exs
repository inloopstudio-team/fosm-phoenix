defmodule FosmWeb.Admin.DashboardLiveTest do
  use FosmWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "Dashboard LiveView" do
    test "renders dashboard with registered apps", %{conn: conn} do
      # Mock the Registry to return test apps
      :meck.new(Fosm.Registry, [:non_strict])
      :meck.expect(Fosm.Registry, :all, fn ->
        [{"invoice", Fosm.TestModels.Invoice}]
      end)

      {:ok, _lv, html} = live(conn, ~p"/fosm/admin")

      assert html =~ "FOSM Dashboard"
      assert html =~ "Applications"

      :meck.unload(Fosm.Registry)
    end

    test "navigates to app detail page", %{conn: conn} do
      :meck.new(Fosm.Registry, [:non_strict])
      :meck.expect(Fosm.Registry, :all, fn ->
        [{"invoice", Fosm.TestModels.Invoice}]
      end)
      :meck.expect(Fosm.Registry, :lookup, fn "invoice" -> {:ok, Fosm.TestModels.Invoice} end)

      {:ok, lv, _html} = live(conn, ~p"/fosm/admin")

      # Click on app card
      lv
      |> element("a[href='/fosm/admin/apps/invoice']")
      |> render_click()

      assert_redirect(lv, ~p"/fosm/admin/apps/invoice")

      :meck.unload(Fosm.Registry)
    end

    test "shows empty state when no apps registered", %{conn: conn} do
      :meck.new(Fosm.Registry, [:non_strict])
      :meck.expect(Fosm.Registry, :all, fn -> [] end)

      {:ok, _lv, html} = live(conn, ~p"/fosm/admin")

      assert html =~ "No FOSM applications registered yet"

      :meck.unload(Fosm.Registry)
    end
  end
end
