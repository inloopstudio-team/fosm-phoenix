defmodule FosmWeb.Admin.WebhooksLiveTest do
  use FosmWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Fosm.{Repo, WebhookSubscription}

  describe "Webhooks LiveView" do
    setup do
      webhook = Repo.insert!(%WebhookSubscription{
        model_class_name: "invoices",
        event_name: "send_invoice",
        url: "https://example.com/webhook",
        active: true
      })

      {:ok, webhook: webhook}
    end

    test "renders webhook list", %{conn: conn, webhook: wh} do
      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/webhooks")

      assert html =~ "Webhook Subscriptions"
      assert html =~ wh.model_class_name
      assert html =~ wh.event_name
      assert html =~ "Active"
    end

    test "toggles webhook status", %{conn: conn, webhook: wh} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/webhooks")

      lv
      |> element("button[phx-click='toggle']")
      |> render_click(%{"id" => wh.id})

      # Webhook should now be inactive
      updated = Repo.get(WebhookSubscription, wh.id)
      assert updated.active == false
    end

    test "navigates to new webhook form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/webhooks")

      lv
      |> element("a", "New Webhook")
      |> render_click()

      assert_redirected(lv, ~p"/fosm/admin/webhooks/new")
    end

    test "creates new webhook", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/webhooks/new")

      lv
      |> form("form[phx-submit='save']", %{
        "webhook_subscription" => %{
          "model_class_name" => "orders",
          "event_name" => "complete",
          "url" => "https://hooks.example.com/fosm",
          "active" => "true"
        }
      })
      |> render_submit()

      assert_redirected(lv, ~p"/fosm/admin/webhooks")
      assert Repo.get_by(WebhookSubscription, url: "https://hooks.example.com/fosm")
    end

    test "validates webhook form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/webhooks/new")

      result =
        lv
        |> form("form[phx-submit='save']", %{
          "webhook_subscription" => %{
            "url" => "invalid-url"
          }
        })
        |> render_submit()

      assert result =~ "error"
    end

    test "deletes webhook", %{conn: conn, webhook: wh} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/webhooks")

      lv
      |> element("button[phx-click='delete']", "Delete")
      |> render_click(%{"id" => wh.id})

      refute Repo.get(WebhookSubscription, wh.id)
    end
  end
end
