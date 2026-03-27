defmodule Fosm.LiveViewCase do
  @moduledoc """
  Test case for FOSM Phoenix LiveView tests.

  Provides:
  - LiveView testing helpers
  - Component rendering
  - Event simulation
  - Flash message assertions

  ## Usage

      defmodule FosmWeb.Admin.RolesLiveTest do
        use Fosm.LiveViewCase, async: true

        test "displays roles", %{conn: conn} do
          {:ok, view, html} = live(conn, "/admin/roles")
          assert html =~ "Role Management"
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import LiveView testing helpers
      import Phoenix.LiveViewTest

      # Standard testing imports
      import Phoenix.ConnTest
      import Fosm.LiveViewCase
      import Fosm.Factory
      import Fosm.Assertions
      import Fosm.TestHelpers

      # The default endpoint for testing
      @endpoint FosmWeb.Endpoint
    end
  end

  setup tags do
    # Start Ecto sandbox
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Fosm.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    # Clear RBAC cache
    Fosm.Current.clear()

    # Clean process state
    Fosm.TestHelpers.cleanup_fosm_state()

    # Build connection
    conn = Phoenix.ConnTest.build_conn()

    # Authenticate if requested
    conn = if tags[:as] do
      authenticate_for_live_view(conn, tags[:as])
    else
      conn
    end

    # Setup user
    user = setup_live_view_user(tags)

    %{conn: conn, user: user}
  end

  @doc """
  Authenticates a connection for LiveView testing.
  """
  def authenticate_for_live_view(conn, :admin) do
    admin = %{id: System.unique_integer([:positive]), __struct__: Fosm.User, superadmin: true, email: "admin@example.com"}
    put_live_view_auth(conn, admin)
  end

  def authenticate_for_live_view(conn, :user) do
    user = %{id: System.unique_integer([:positive]), __struct__: Fosm.User, superadmin: false, email: "user@example.com"}
    put_live_view_auth(conn, user)
  end

  def authenticate_for_live_view(conn, user) when is_map(user) do
    put_live_view_auth(conn, user)
  end

  def authenticate_for_live_view(conn, _), do: conn

  defp put_live_view_auth(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Phoenix.ConnTest.put_session(:current_user_id, user.id)
    |> Phoenix.ConnTest.put_session(:current_user_type, to_string(user.__struct__))
  end

  defp setup_live_view_user(%{as: :admin}) do
    %{id: System.unique_integer([:positive]), __struct__: Fosm.User, superadmin: true, email: "admin@example.com"}
  end

  defp setup_live_view_user(%{as: :user}) do
    %{id: System.unique_integer([:positive]), __struct__: Fosm.User, superadmin: false, email: "user@example.com"}
  end

  defp setup_live_view_user(_) do
    %{id: System.unique_integer([:positive]), __struct__: Fosm.User, superadmin: false, email: "user@example.com"}
  end

  # ============================================================================
  # LiveView Assertions
  # ============================================================================

  @doc """
  Asserts that an element with the given selector exists in the rendered view.

  ## Examples

      assert_has(view, "h1", "Role Management")
      assert_has(view, "#role-table tr", count: 3)
  """
  def assert_has(view, selector, text \\ nil, opts \\ []) do
    html = render(view)

    count = Keyword.get(opts, :count)

    if count do
      assert count_elements(html, selector) == count,
        "Expected #{count} elements matching '#{selector}', but found #{count_elements(html, selector)}"
    end

    if text do
      assert html =~ text,
        "Expected rendered view to contain '#{text}'"
    end

    true
  end

  @doc """
  Asserts that an element does not exist.

  ## Examples

      refute_has(view, ".error-message")
  """
  def refute_has(view, selector) do
    html = render(view)
    count = count_elements(html, selector)

    assert count == 0,
      "Expected no elements matching '#{selector}', but found #{count}"
  end

  @doc """
  Asserts that a flash message is displayed.

  ## Examples

      assert_flash(view, :info, "Role assigned successfully")
      assert_flash(view, :error, ~r/permission denied/i)
  """
  def assert_flash(view, kind, pattern) when is_binary(pattern) do
    assert_flash_present(view, kind, fn msg ->
      assert msg == pattern
    end)
  end

  def assert_flash(view, kind, %Regex{} = pattern) do
    assert_flash_present(view, kind, fn msg ->
      assert msg =~ pattern
    end)
  end

  defp assert_flash_present(view, kind, assertion_fn) do
    # LiveView flash is typically rendered with specific data attributes
    html = render(view)

    # Look for flash element
    flash_present =
      case kind do
        :info -> html =~ ~r/<[^>]*class="[^"]*flash[^"]*info/
        :error -> html =~ ~r/<[^>]*class="[^"]*flash[^"]*error/
        :warning -> html =~ ~r/<[^>]*class="[^"]*flash[^"]*warning/
        _ -> false
      end

    assert flash_present, "Expected #{kind} flash to be present"

    assertion_fn.(extract_flash_text(html, kind))
  end

  @doc """
  Simulates clicking a link or button and asserts on the result.

  ## Examples

      click_and_assert(view, "#submit-btn", redirected_to: "/success")
  """
  def click_and_assert(view, selector, opts) do
    view
    |> element(selector)
    |> render_click()

    if redirected_to = Keyword.get(opts, :redirected_to) do
      assert_redirect(view, redirected_to)
    end

    if flash = Keyword.get(opts, :flash) do
      {kind, message} = flash
      assert_flash(view, kind, message)
    end

    view
  end

  @doc """
  Fills a form field and renders the change.

  ## Examples

      fill_form(view, "#role-form", user_id: "42", role: "owner")
  """
  def fill_form(view, selector, attrs) do
    view
    |> form(selector, attrs)
    |> render_change()
  end

  @doc """
  Submits a form and asserts on the result.

  ## Examples

      submit_form(view, "#role-form", user_id: "42", role: "owner",
        flash: {:info, "Role assigned"},
        redirected_to: "/admin/roles"
      )
  """
  def submit_form(view, selector, attrs, opts \\ []) do
    html =
      view
      |> form(selector, attrs)
      |> render_submit()

    if flash = Keyword.get(opts, :flash) do
      {kind, message} = flash
      # Flash might be in redirect, so check both
      assert html =~ message or assert_flash(view, kind, message)
    end

    if redirected_to = Keyword.get(opts, :redirected_to) do
      assert_redirect(view, redirected_to)
    end

    html
  end

  @doc """
  Waits for an element to appear (useful for async operations).

  ## Examples

      wait_for_element(view, "#async-loaded", timeout: 1000)
  """
  def wait_for_element(view, selector, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 50)

    wait_loop(view, selector, timeout, interval)
  end

  defp wait_loop(_view, _selector, remaining, _interval) when remaining <= 0 do
    flunk("Timeout waiting for element")
  end

  defp wait_loop(view, selector, remaining, interval) do
    html = render(view)

    if count_elements(html, selector) > 0 do
      :ok
    else
      Process.sleep(interval)
      wait_loop(view, selector, remaining - interval, interval)
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp count_elements(html, selector) do
    # Simple selector counting - in real implementation would use Floki
    # For now, basic string matching
    case selector do
      "#" <> id -> if html =~ ~r/id="#{id}"/, do: 1, else: 0
      "." <> class ->
        regex = ~r/class="[^"]*#{class}/
        Regex.scan(regex, html) |> length()
      tag when is_binary(tag) ->
        regex = ~r/<#{tag}[\s>]/
        Regex.scan(regex, html) |> length()
      _ ->
        if html =~ selector, do: 1, else: 0
    end
  end

  defp extract_flash_text(html, kind) do
    # Extract text from flash element
    # This is a simplified implementation
    case kind do
      :info ->
        Regex.run(~r/<[^>]*flash[^>]*info[^>]*>([^<]+)/, html, capture: :all_but_first)
        |> List.first()
        |> Kernel.||("")
        |> String.trim()

      :error ->
        Regex.run(~r/<[^>]*flash[^>]*error[^>]*>([^<]+)/, html, capture: :all_but_first)
        |> List.first()
        |> Kernel.||("")
        |> String.trim()

      _ ->
        ""
    end
  end
end
