defmodule FosmWeb.Admin.WebhooksLiveTest do
  @moduledoc """
  LiveView tests for Webhooks admin interface.

  Tests the webhook subscription management including:
  - Listing webhooks
  - Creating new webhooks
  - Editing webhooks
  - Testing webhooks
  - Enabling/disabling webhooks
  """
  use Fosm.LiveViewCase, async: true

  import Fosm.Factory

  describe "webhooks list" do
    @tag as: :admin
    test "displays webhook subscriptions", %{conn: conn} do
      webhook = insert!(:webhook_subscription)

      {:ok, view, html} = live(conn, "/admin/webhooks")

      assert html =~ "Webhook Subscriptions"
      assert html =~ webhook.url
      assert html =~ webhook.event_name
    end

    @tag as: :admin
    test "shows active/inactive status", %{conn: conn} do
      insert!(:webhook_subscription, active: true)
      insert!(:webhook_subscription, active: false)

      {:ok, view, html} = live(conn, "/admin/webhooks")

      assert html =~ "Active"
      assert html =~ "Inactive"
    end
  end

  describe "creating webhooks" do
    @tag as: :admin
    test "can create new webhook", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/webhooks/new")

      submit_form(view, "#webhook-form",
        model_class_name: "Fosm.Invoice",
        event_name: "pay",
        url: "https://example.com/webhooks/new"
      )

      # Should redirect to list
      assert_redirect(view, "/admin/webhooks")
    end

    @tag as: :admin
    test "validates required fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/webhooks/new")

      html = submit_form(view, "#webhook-form",
        model_class_name: "",
        event_name: "",
        url: ""
      )

      assert html =~ "can't be blank"
    end

    @tag as: :admin
    test "validates URL format", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/webhooks/new")

      html = submit_form(view, "#webhook-form",
        model_class_name: "Fosm.Invoice",
        event_name: "pay",
        url: "not-a-valid-url"
      )

      assert html =~ "invalid URL"
    end
  end

  describe "editing webhooks" do
    @tag as: :admin
    test "can edit webhook URL", %{conn: conn} do
      webhook = insert!(:webhook_subscription)

      {:ok, view, _html} = live(conn, "/admin/webhooks/#{webhook.id}/edit")

      submit_form(view, "#webhook-form",
        url: "https://new-url.com/webhook"
      )

      assert_redirect(view, "/admin/webhooks")
    end
  end

  describe "testing webhooks" do
    @tag as: :admin
    test "can send test payload", %{conn: conn} do
      webhook = insert!(:webhook_subscription)

      {:ok, view, _html} = live(conn, "/admin/webhooks")

      html = view
      |> element("#test-webhook-#{webhook.id}")
      |> render_click()

      # Should show test result
      assert html =~ "Test sent" or html =~ "queued"
    end
  end

  describe "enabling/disabling webhooks" do
    @tag as: :admin
    test "can toggle webhook active state", %{conn: conn} do
      webhook = insert!(:webhook_subscription, active: true)

      {:ok, view, _html} = live(conn, "/admin/webhooks")

      view
      |> element("#toggle-webhook-#{webhook.id}")
      |> render_click()

      # Should now be inactive
      # This would verify by checking the database
    end
  end
end
