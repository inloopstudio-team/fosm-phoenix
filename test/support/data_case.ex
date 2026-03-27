defmodule Fosm.DataCase do
  @moduledoc """
  Base test case for FOSM database tests.

  Provides:
  - Ecto sandbox setup for test isolation
  - ExMachina factory integration
  - Custom FOSM assertions
  - Common test helpers

  ## Usage

      defmodule Fosm.LifecycleTest do
        use Fosm.DataCase, async: true
        import Fosm.Factory

        test "transitions work correctly", %{user: user} do
          record = insert!(:invoice, state: "draft")
          {:ok, updated} = Fosm.Lifecycle.fire!(record, :send, actor: user)
          assert updated.state == "sent"
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Fosm.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Fosm.DataCase
      import Fosm.Factory
      import Fosm.Assertions
      import Fosm.TestHelpers
    end
  end

  setup tags do
    # Start sandbox for SQL-based tests
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Fosm.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    # Clear RBAC cache
    Fosm.Current.clear()

    # Clear any deferred effects from process dictionary
    for key <- Map.keys(Process.get() || %{}), is_tuple(key) and elem(key, 0) == :fosm_deferred_effects do
      Process.delete(key)
    end

    # Clear causal chain context
    Process.delete(:fosm_trigger_context)

    # Setup any test users or actors needed
    user = setup_test_user(tags)

    %{user: user, conn: build_conn()}
  end

  # Setup helper for test users
  defp setup_test_user(%{user_type: :admin}) do
    %{id: 1, __struct__: Fosm.User, superadmin: true, email: "admin@test.com"}
  end

  defp setup_test_user(%{user_type: :user}) do
    %{id: 2, __struct__: Fosm.User, superadmin: false, email: "user@test.com"}
  end

  defp setup_test_user(_tags) do
    # Default: regular user with no special permissions
    %{id: System.unique_integer([:positive]), __struct__: Fosm.User, superadmin: false, email: "test@example.com"}
  end

  # Build a mock conn for testing
  defp build_conn do
    %Plug.Conn{
      assigns: %{},
      private: %{phoenix_format: "html"},
      req_headers: []
    }
  end
end
