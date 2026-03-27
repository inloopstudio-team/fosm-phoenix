defmodule FosmWeb.Admin.TransitionsLiveTest do
  use FosmWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Fosm.{Repo, TransitionLog}

  describe "Transitions LiveView" do
    setup do
      # Create test transition logs
      transition1 = Repo.insert!(%TransitionLog{
        record_type: "invoices",
        record_id: "1",
        event_name: "send_invoice",
        from_state: "draft",
        to_state: "sent",
        actor_type: "User",
        actor_id: "42",
        created_at: DateTime.utc_now()
      })

      transition2 = Repo.insert!(%TransitionLog{
        record_type: "orders",
        record_id: "2",
        event_name: "complete",
        from_state: "pending",
        to_state: "completed",
        actor_type: "symbol",
        actor_label: "agent",
        created_at: DateTime.utc_now()
      })

      {:ok, transition1: transition1, transition2: transition2}
    end

    test "renders transitions list", %{conn: conn, transition1: t1} do
      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/transitions")

      assert html =~ "Transition Log"
      assert html =~ t1.event_name
      assert html =~ to_string(t1.record_id)
    end

    test "filters by model via URL params", %{conn: conn, transition1: t1, transition2: t2} do
      :meck.new(Fosm.Registry, [:non_strict])
      :meck.expect(Fosm.Registry, :all, fn -> [] end)

      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/transitions?model=invoices")

      assert html =~ t1.event_name
      refute html =~ t2.event_name

      :meck.unload(Fosm.Registry)
    end

    test "filters by actor type via URL params", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/transitions?actor=agent")

      # Should only show agent transitions
      assert html =~ "Agent"
    end

    test "applies filters via handle_event", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/transitions")

      lv
      |> form("form[phx-change='apply_filters']", %{"model" => "invoices", "event" => "send_invoice"})
      |> render_change()

      # Should update URL with filters
      assert_redirected(lv, ~p"/fosm/admin/transitions?model=invoices&event=send_invoice")
    end

    test "clears all filters", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/fosm/admin/transitions?model=invoices&event=test")

      lv
      |> element("button", "Clear All")
      |> render_click()

      assert_redirected(lv, ~p"/fosm/admin/transitions")
    end

    test "shows pagination when many records", %{conn: conn} do
      # Create many transitions to trigger pagination
      for i <- 1..60 do
        Repo.insert!(%TransitionLog{
          record_type: "test",
          record_id: to_string(i),
          event_name: "event#{i}",
          from_state: "start",
          to_state: "end",
          created_at: DateTime.utc_now()
        })
      end

      {:ok, _lv, html} = live(conn, ~p"/fosm/admin/transitions")

      assert html =~ "Previous"
      assert html =~ "Next"
    end
  end
end
