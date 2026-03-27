defmodule FosmWeb.Admin.TransitionsLiveTest do
  @moduledoc """
  LiveView tests for Transitions admin interface.

  Tests the transition log viewer including:
  - Pagination of transition logs
  - Filtering by model, event, actor
  - Snapshot viewing
  - Export functionality
  """
  use Fosm.LiveViewCase, async: true

  import Fosm.Factory

  describe "transitions list" do
    @tag as: :admin
    test "displays transition logs", %{conn: conn} do
      # Create some transition logs
      insert!(:transition_log, event_name: "send", from_state: "draft", to_state: "sent")
      insert!(:transition_log, event_name: "pay", from_state: "sent", to_state: "paid")

      {:ok, view, html} = live(conn, "/admin/transitions")

      assert html =~ "Transition Log"
      assert html =~ "send"
      assert html =~ "pay"
    end

    @tag as: :admin
    test "paginates results", %{conn: conn} do
      # Create many logs
      for i <- 1..60 do
        insert!(:transition_log, event_name: "event_#{i}")
      end

      {:ok, view, _html} = live(conn, "/admin/transitions?page=1")

      # Should have pagination controls
      assert_has(view, ".pagination")

      # Navigate to page 2
      view
      |> element("a[href='/admin/transitions?page=2']")
      |> render_click()

      # Should show page 2 results
      assert_redirect(view, "/admin/transitions?page=2")
    end

    @tag as: :admin
    test "filters by model", %{conn: conn} do
      insert!(:transition_log, record_type: "invoices")
      insert!(:transition_log, record_type: "workflows")

      {:ok, view, _html} = live(conn, "/admin/transitions?model=invoices")

      html = render(view)
      assert html =~ "invoices"
      refute html =~ "workflows"
    end

    @tag as: :admin
    test "filters by event", %{conn: conn} do
      insert!(:transition_log, event_name: "send")
      insert!(:transition_log, event_name: "pay")

      {:ok, view, _html} = live(conn, "/admin/transitions?event=send")

      html = render(view)
      assert html =~ "send"
      refute html =~ "pay"
    end

    @tag as: :admin
    test "filters by actor type", %{conn: conn} do
      insert!(:transition_log, actor_type: "Fosm.User", actor_id: "1")
      insert!(:agent_transition_log)

      {:ok, view, _html} = live(conn, "/admin/transitions?actor=human")

      html = render(view)
      assert html =~ "Fosm.User"
      refute html =~ "symbol"

      {:ok, view, _html} = live(conn, "/admin/transitions?actor=agent")

      html = render(view)
      assert html =~ "symbol"
    end
  end

  describe "snapshot viewing" do
    @tag as: :admin
    test "displays snapshot details", %{conn: conn} do
      insert!(:transition_log,
        event_name: "pay",
        state_snapshot: %{"amount" => "100.00", "state" => "paid"}
      )

      {:ok, view, html} = live(conn, "/admin/transitions")

      assert html =~ "pay"
    end

    @tag as: :admin
    test "expands snapshot on click", %{conn: conn} do
      log = insert!(:transition_log,
        state_snapshot: %{"amount" => "100.00"}
      )

      {:ok, view, _html} = live(conn, "/admin/transitions")

      view
      |> element("#snapshot-#{log.id}")
      |> render_click()

      html = render(view)
      assert html =~ "100.00"
    end
  end

  describe "export functionality" do
    @tag as: :admin
    test "can export to CSV", %{conn: conn} do
      insert!(:transition_log)

      {:ok, view, _html} = live(conn, "/admin/transitions")

      view
      |> element("#export-csv")
      |> render_click()

      # Should trigger download
      # Verify response headers would contain CSV content-type
    end
  end
end
