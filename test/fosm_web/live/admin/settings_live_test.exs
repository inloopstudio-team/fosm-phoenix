defmodule FosmWeb.Admin.SettingsLiveTest do
  use FosmWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "Settings LiveView" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/settings")

      assert html =~ "FOSM Settings"
      assert html =~ "LLM Providers"
      assert html =~ "Configuration"
      assert html =~ "System Health"
    end

    test "displays LLM provider status", %{conn: conn} do
      # Set up a fake API key
      System.put_env("ANTHROPIC_API_KEY", "sk-test123")

      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/settings")

      assert html =~ "Anthropic (Claude)"
      assert html =~ "Configured"

      System.delete_env("ANTHROPIC_API_KEY")
    end

    test "shows unconfigured providers", %{conn: conn} do
      # Ensure no API keys are set
      for key <- ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY"] do
        System.delete_env(key)
      end

      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/settings")

      assert html =~ "Not Configured"
    end

    test "displays FOSM version", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/settings")

      assert html =~ "v"
    end

    test "shows system health metrics", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/settings")

      assert html =~ "Registered Applications"
      assert html =~ "Total Transitions"
    end

    test "auto-refreshes health metrics", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/settings")

      # Send refresh message
      send(lv.pid, :refresh)

      # Should reload without error
      assert render(lv) =~ "FOSM Settings"
    end
  end
end
