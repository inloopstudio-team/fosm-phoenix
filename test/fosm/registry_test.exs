defmodule Fosm.RegistryTest do
  @moduledoc """
  Tests for the FOSM Registry.
  
  These tests verify:
  - Model registration
  - Lookup by slug
  - Auto-registration at boot
  - Lifecycle introspection
  - Error handling for unknown models
  """
  use Fosm.DataCase, async: false

  import Fosm.Factory

  alias Fosm.Registry

  # Mock FOSM model for testing
  defmodule MockInvoice do
    @moduledoc false
    def fosm_lifecycle do
      %{
        states: [
          %{name: :draft, initial: true, terminal: false},
          %{name: :sent, initial: false, terminal: false},
          %{name: :paid, initial: false, terminal: true}
        ],
        events: [
          %{name: :send_invoice, from_states: [:draft], to_state: :sent},
          %{name: :pay, from_states: [:sent], to_state: :paid}
        ]
      }
    end

    def available_events(record) do
      case record.state do
        "draft" -> [:send_invoice]
        "sent" -> [:pay]
        _ -> []
      end
    end

    def __schema__(:source), do: "invoices"
  end

  setup do
    # Clean up registered models before each test
    for slug <- Registry.slugs() do
      Registry.unregister(slug)
    end

    :ok
  end

  describe "register/3" do
    test "registers a FOSM model" do
      assert :ok = Registry.register("invoice", MockInvoice)
      assert Registry.registered?("invoice")
    end

    test "returns error for non-FOSM modules" do
      # A regular module without fosm_lifecycle/0
      assert {:error, :not_a_fosm_model} = Registry.register("invalid", String)
    end

    test "overwrites existing registration" do
      Registry.register("model", MockInvoice)
      
      # Re-register with same slug
      assert :ok = Registry.register("model", MockInvoice)
      
      {:ok, module} = Registry.lookup("model")
      assert module == MockInvoice
    end
  end

  describe "lookup/1" do
    test "returns module for registered slug" do
      Registry.register("invoice", MockInvoice)
      
      assert {:ok, MockInvoice} = Registry.lookup("invoice")
    end

    test "returns :error for unregistered slug" do
      assert :error = Registry.lookup("unknown")
    end
  end

  describe "lookup!/1" do
    test "returns module for registered slug" do
      Registry.register("invoice", MockInvoice)
      
      assert MockInvoice = Registry.lookup!("invoice")
    end

    test "raises for unregistered slug" do
      assert_raise Fosm.Errors.RegistryNotFound, fn ->
        Registry.lookup!("unknown")
      end
    end
  end

  describe "unregister/1" do
    test "removes registration" do
      Registry.register("invoice", MockInvoice)
      assert Registry.registered?("invoice")

      Registry.unregister("invoice")
      refute Registry.registered?("invoice")
    end

    test "succeeds even if slug was not registered" do
      assert :ok = Registry.unregister("never_registered")
    end
  end

  describe "all/0" do
    test "returns map of all registrations" do
      Registry.register("invoice", MockInvoice)
      Registry.register("order", MockInvoice)

      all = Registry.all()
      
      assert is_map(all)
      assert all["invoice"] == MockInvoice
      assert all["order"] == MockInvoice
    end

    test "returns empty map when nothing registered" do
      assert Registry.all() == %{}
    end
  end

  describe "slugs/0" do
    test "returns list of registered slugs" do
      Registry.register("invoice", MockInvoice)
      Registry.register("order", MockInvoice)

      slugs = Registry.slugs()
      
      assert is_list(slugs)
      assert "invoice" in slugs
      assert "order" in slugs
    end
  end

  describe "registered?/1" do
    test "returns true for registered slug" do
      Registry.register("invoice", MockInvoice)
      assert Registry.registered?("invoice")
    end

    test "returns false for unregistered slug" do
      refute Registry.registered?("unknown")
    end
  end

  describe "lifecycle/1" do
    test "returns lifecycle for registered model" do
      Registry.register("invoice", MockInvoice)
      
      {:ok, lifecycle} = Registry.lifecycle("invoice")
      
      assert is_map(lifecycle)
      assert length(lifecycle.states) == 3
      assert length(lifecycle.events) == 2
    end

    test "returns error for unregistered model" do
      assert {:error, :not_found} = Registry.lifecycle("unknown")
    end
  end

  describe "available_events/2" do
    test "returns available events for a record" do
      Registry.register("invoice", MockInvoice)
      
      record = %{state: "draft"}
      {:ok, events} = Registry.available_events("invoice", record)
      
      assert is_list(events)
      assert :send_invoice in events
    end

    test "returns empty list for terminal state" do
      Registry.register("invoice", MockInvoice)
      
      record = %{state: "paid"}
      {:ok, events} = Registry.available_events("invoice", record)
      
      assert events == []
    end

    test "returns error for unregistered model" do
      record = %{state: "draft"}
      assert {:error, :not_found} = Registry.available_events("unknown", record)
    end
  end

  describe "auto_register/0" do
    test "registers models from application config" do
      # Set temporary config
      original = Application.get_env(:fosm, :models)
      
      Application.put_env(:fosm, :models, [
        {"test_invoice", MockInvoice}
      ])
      
      Registry.auto_register()
      
      assert Registry.registered?("test_invoice")
      
      # Restore original config
      if original do
        Application.put_env(:fosm, :models, original)
      else
        Application.delete_env(:fosm, :models)
      end
    end
  end

  describe "concurrent access" do
    test "supports concurrent reads from multiple processes" do
      Registry.register("invoice", MockInvoice)

      tasks = for _ <- 1..10 do
        Task.async(fn ->
          {:ok, module} = Registry.lookup("invoice")
          module
        end)
      end

      results = Task.await_many(tasks)
      
      assert Enum.all?(results, &(&1 == MockInvoice))
    end
  end

  describe "GenServer supervision" do
    test "is restartable" do
      pid = Process.whereis(Registry)
      assert is_pid(pid)
      
      # Pre-register a model
      Registry.register("invoice", MockInvoice)
      
      # Kill the registry
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      
      assert_receive {:DOWN, ^ref, :process, _, _}, 1000
      
      # Should restart
      Process.sleep(100)
      new_pid = Process.whereis(Registry)
      assert is_pid(new_pid)
      
      # Note: ETS table is lost on restart, so registrations are cleared
      # This is expected behavior for this GenServer
    end
  end
end
