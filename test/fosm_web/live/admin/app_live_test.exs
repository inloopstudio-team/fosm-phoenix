defmodule FosmWeb.Admin.AppLiveTest do
  use FosmWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query

  alias Fosm.Repo

  describe "App Detail LiveView" do
    setup do
      # Create test records
      invoice = Repo.insert!(%Fosm.TestModels.Invoice{
        name: "Test Invoice",
        state: "draft"
      })

      {:ok, invoice: invoice}
    end

    test "renders app details with records", %{conn: conn, invoice: invoice} do
      :meck.new(Fosm.Registry, [:non_strict])
      :meck.expect(Fosm.Registry, :lookup, fn "invoice" -> {:ok, Fosm.TestModels.Invoice} end)

      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/apps/invoice")

      assert html =~ "Invoice"
      assert html =~ to_string(invoice.id)
      assert html =~ "draft"

      :meck.unload(Fosm.Registry)
    end

    test "filters records by state via URL params", %{conn: conn} do
      :meck.new(Fosm.Registry, [:non_strict])
      :meck.expect(Fosm.Registry, :lookup, fn "invoice" -> {:ok, Fosm.TestModels.Invoice} end)

      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/apps/invoice?state=draft")

      assert html =~ "draft"

      :meck.unload(Fosm.Registry)
    end

    test "redirects to dashboard for unknown app", %{conn: conn} do
      :meck.new(Fosm.Registry, [:non_strict])
      :meck.expect(Fosm.Registry, :lookup, fn _ -> :error end)

      {:error, {:live_redirect, %{to: "/fosm/admin"}}} = live(conn, ~p"/fosm/admin/apps/unknown")

      :meck.unload(Fosm.Registry)
    end

    test "handles clear filters event", %{conn: conn} do
      :meck.new(Fosm.Registry, [:non_strict])
      :meck.expect(Fosm.Registry, :lookup, fn "invoice" -> {:ok, Fosm.TestModels.Invoice} end)

      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/apps/invoice?state=draft")

      lv
      |> element("button", "Clear")
      |> render_click()

      assert_redirect(lv, ~p"/fosm/admin/apps/invoice")

      :meck.unload(Fosm.Registry)
    end
  end
end
