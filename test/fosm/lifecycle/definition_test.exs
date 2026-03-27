defmodule Fosm.Lifecycle.DefinitionTest do
  @moduledoc """
  Tests for FOSM Lifecycle Definition structs.

  These tests verify the core data structures work correctly.
  """
  use Fosm.DataCase, async: true

  alias Fosm.Lifecycle.{
    StateDefinition,
    EventDefinition,
    GuardDefinition,
    SideEffectDefinition,
    RoleDefinition,
    AccessDefinition,
    Definition
  }

  describe "StateDefinition" do
    test "struct has correct defaults" do
      state = %StateDefinition{name: :draft, initial: true, terminal: false}

      assert state.name == :draft
      assert state.initial == true
      assert state.terminal == false
    end
  end

  describe "EventDefinition" do
    test "struct stores event configuration" do
      event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      assert event.name == :send
      assert event.from_states == [:draft]
      assert event.to_state == :sent
    end

    test "valid_from?/2 returns true for valid states" do
      event = %EventDefinition{
        name: :send,
        from_states: [:draft, :review],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      assert EventDefinition.valid_from?(event, :draft) == true
      assert EventDefinition.valid_from?(event, :review) == true
      assert EventDefinition.valid_from?(event, :sent) == false
    end

    test "add_guard/2 adds guard to event" do
      event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      guard = %{name: :has_line_items}
      updated = EventDefinition.add_guard(event, guard)

      assert length(updated.guards) == 1
      assert hd(updated.guards) == guard
    end

    test "add_side_effect/2 adds effect to event" do
      event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      effect = %{name: :notify_client}
      updated = EventDefinition.add_side_effect(event, effect)

      assert length(updated.side_effects) == 1
      assert hd(updated.side_effects) == effect
    end
  end

  describe "GuardDefinition" do
    test "struct stores guard configuration" do
      guard_fn = fn _record -> true end

      guard = %GuardDefinition{
        name: :has_line_items,
        event: :send,
        check: guard_fn,
        line: 42,
        file: "test.ex"
      }

      assert guard.name == :has_line_items
      assert guard.event == :send
      assert guard.check == guard_fn
      assert guard.line == 42
      assert guard.file == "test.ex"
    end

    test "evaluate/2 handles true return" do
      guard = %GuardDefinition{
        name: :always_pass,
        event: :test,
        check: fn _ -> true end,
        line: 1,
        file: "test.ex"
      }

      assert GuardDefinition.evaluate(guard, %{}) == :ok
    end

    test "evaluate/2 handles :ok return" do
      guard = %GuardDefinition{
        name: :ok_pass,
        event: :test,
        check: fn _ -> :ok end,
        line: 1,
        file: "test.ex"
      }

      assert GuardDefinition.evaluate(guard, %{}) == :ok
    end

    test "evaluate/2 handles false return" do
      guard = %GuardDefinition{
        name: :always_fail,
        event: :test,
        check: fn _ -> false end,
        line: 1,
        file: "test.ex"
      }

      assert GuardDefinition.evaluate(guard, %{}) == {:error, nil}
    end

    test "evaluate/2 handles :error return" do
      guard = %GuardDefinition{
        name: :error_fail,
        event: :test,
        check: fn _ -> :error end,
        line: 1,
        file: "test.ex"
      }

      assert GuardDefinition.evaluate(guard, %{}) == {:error, nil}
    end

    test "evaluate/2 handles {:error, reason} return" do
      guard = %GuardDefinition{
        name: :reason_fail,
        event: :test,
        check: fn _ -> {:error, "custom reason"} end,
        line: 1,
        file: "test.ex"
      }

      assert GuardDefinition.evaluate(guard, %{}) == {:error, "custom reason"}
    end

    test "evaluate/2 handles string message return" do
      guard = %GuardDefinition{
        name: :string_fail,
        event: :test,
        check: fn _ -> "failure message" end,
        line: 1,
        file: "test.ex"
      }

      assert GuardDefinition.evaluate(guard, %{}) == {:error, "failure message"}
    end

    test "evaluate/2 handles [:fail, reason] return" do
      guard = %GuardDefinition{
        name: :structured_fail,
        event: :test,
        check: fn _ -> [:fail, "structured reason"] end,
        line: 1,
        file: "test.ex"
      }

      assert GuardDefinition.evaluate(guard, %{}) == {:error, "structured reason"}
    end

    test "evaluate/2 catches exceptions" do
      guard = %GuardDefinition{
        name: :exception_fail,
        event: :test,
        check: fn _ -> raise "boom" end,
        line: 1,
        file: "test.ex"
      }

      result = GuardDefinition.evaluate(guard, %{)
      assert match?({:error, _}, result)
      assert result |> elem(1) =~ "boom"
    end
  end

  describe "SideEffectDefinition" do
    test "struct stores effect configuration" do
      effect_fn = fn _record, _transition -> :ok end

      effect = %SideEffectDefinition{
        name: :notify_client,
        event: :send,
        effect: effect_fn,
        defer: false,
        line: 42,
        file: "test.ex"
      }

      assert effect.name == :notify_client
      assert effect.event == :send
      assert effect.effect == effect_fn
      assert effect.defer == false
    end

    test "deferred?/1 returns true for deferred effects" do
      deferred = %SideEffectDefinition{
        name: :deferred_effect,
        event: :test,
        effect: fn _, _ -> :ok end,
        defer: true,
        line: 1,
        file: "test.ex"
      }

      assert SideEffectDefinition.deferred?(deferred) == true
    end

    test "deferred?/1 returns false for immediate effects" do
      immediate = %SideEffectDefinition{
        name: :immediate_effect,
        event: :test,
        effect: fn _, _ -> :ok end,
        defer: false,
        line: 1,
        file: "test.ex"
      }

      assert SideEffectDefinition.deferred?(immediate) == false
    end

    test "call/3 executes the effect" do
      called = self()

      effect = %SideEffectDefinition{
        name: :test_effect,
        event: :test,
        effect: fn record, transition ->
          send(called, {:effect_called, record, transition})
        end,
        defer: false,
        line: 1,
        file: "test.ex"
      }

      record = %{id: 1}
      transition = %{event: :test}

      SideEffectDefinition.call(effect, record, transition)

      assert_receive {:effect_called, ^record, ^transition}
    end
  end

  describe "RoleDefinition" do
    test "struct stores role configuration" do
      role = %RoleDefinition{
        name: :owner,
        default: true,
        crud_permissions: [:create, :read, :update, :delete],
        event_permissions: [:send, :cancel]
      }

      assert role.name == :owner
      assert role.default == true
    end

    test "can?/2 checks CRUD permission" do
      role = %RoleDefinition{
        name: :owner,
        default: true,
        crud_permissions: [:create, :read, :update, :delete],
        event_permissions: []
      }

      assert RoleDefinition.can?(role, :crud) == true
      assert RoleDefinition.can?(role, :create) == true
      assert RoleDefinition.can?(role, :read) == true
      assert RoleDefinition.can?(role, :update) == true
      assert RoleDefinition.can?(role, :delete) == true
    end

    test "can?/2 checks event permission" do
      role = %RoleDefinition{
        name: :approver,
        default: false,
        crud_permissions: [:read],
        event_permissions: [:approve, :reject]
      }

      assert RoleDefinition.can?(role, :read) == true
      assert RoleDefinition.can?(role, :approve) == true
      assert RoleDefinition.can?(role, :reject) == true
      assert RoleDefinition.can?(role, :delete) == false
    end

    test "can_crud?/1 returns true when CRUD permissions exist" do
      role = %RoleDefinition{
        name: :admin,
        default: true,
        crud_permissions: [:create, :read, :update, :delete],
        event_permissions: []
      }

      assert RoleDefinition.can_crud?(role) == true
    end

    test "can_crud?/1 returns false when no CRUD permissions" do
      role = %RoleDefinition{
        name: :viewer,
        default: false,
        crud_permissions: [],
        event_permissions: []
      }

      assert RoleDefinition.can_crud?(role) == false
    end

    test "all_permissions/1 combines CRUD and event permissions" do
      role = %RoleDefinition{
        name: :owner,
        default: true,
        crud_permissions: [:read, :update],
        event_permissions: [:send, :cancel]
      }

      perms = RoleDefinition.all_permissions(role)
      assert :read in perms
      assert :update in perms
      assert :send in perms
      assert :cancel in perms
    end
  end

  describe "AccessDefinition" do
    test "struct stores access configuration" do
      role1 = %RoleDefinition{
        name: :owner,
        default: true,
        crud_permissions: [:crud],
        event_permissions: []
      }

      access = %AccessDefinition{
        roles: [role1],
        default_role: :owner
      }

      assert access.default_role == :owner
      assert length(access.roles) == 1
    end

    test "roles_for_event/2 returns roles that can perform event" do
      owner = %RoleDefinition{
        name: :owner,
        default: true,
        crud_permissions: [:crud],
        event_permissions: [:cancel]
      }

      viewer = %RoleDefinition{
        name: :viewer,
        default: false,
        crud_permissions: [:read],
        event_permissions: []
      }

      approver = %RoleDefinition{
        name: :approver,
        default: false,
        crud_permissions: [:read],
        event_permissions: [:approve]
      }

      access = %AccessDefinition{
        roles: [owner, viewer, approver],
        default_role: :viewer
      }

      roles = AccessDefinition.roles_for_event(access, :approve)
      assert length(roles) == 1
      assert hd(roles).name == :approver

      roles = AccessDefinition.roles_for_event(access, :cancel)
      assert length(roles) == 1
      assert hd(roles).name == :owner
    end

    test "find_role/2 returns role by name" do
      owner = %RoleDefinition{
        name: :owner,
        default: true,
        crud_permissions: [:crud],
        event_permissions: []
      }

      access = %AccessDefinition{
        roles: [owner],
        default_role: :owner
      }

      assert AccessDefinition.find_role(access, :owner) == owner
      assert AccessDefinition.find_role(access, :nonexistent) == nil
    end
  end

  describe "Definition" do
    test "struct stores complete lifecycle definition" do
      draft = %StateDefinition{name: :draft, initial: true, terminal: false}
      paid = %StateDefinition{name: :paid, initial: false, terminal: true}

      send_event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      definition = %Definition{
        states: [draft, paid],
        events: [send_event],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      assert length(definition.states) == 2
      assert length(definition.events) == 1
    end

    test "find_event/2 returns event by name" do
      send_event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      definition = %Definition{
        states: [],
        events: [send_event],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      assert Definition.find_event(definition, :send) == send_event
      assert Definition.find_event(definition, :nonexistent) == nil
    end

    test "find_state/2 returns state by name" do
      draft = %StateDefinition{name: :draft, initial: true, terminal: false}

      definition = %Definition{
        states: [draft],
        events: [],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      assert Definition.find_state(definition, :draft) == draft
      assert Definition.find_state(definition, :nonexistent) == nil
    end

    test "state_names/1 returns list of state names" do
      draft = %StateDefinition{name: :draft, initial: true, terminal: false}
      paid = %StateDefinition{name: :paid, initial: false, terminal: true}

      definition = %Definition{
        states: [draft, paid],
        events: [],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      assert Definition.state_names(definition) == [:draft, :paid]
    end

    test "event_names/1 returns list of event names" do
      send_event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      pay_event = %EventDefinition{
        name: :pay,
        from_states: [:sent],
        to_state: :paid,
        guards: [],
        side_effects: []
      }

      definition = %Definition{
        states: [],
        events: [send_event, pay_event],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      assert Definition.event_names(definition) == [:send, :pay]
    end

    test "is_terminal?/2 returns true for terminal states" do
      draft = %StateDefinition{name: :draft, initial: true, terminal: false}
      paid = %StateDefinition{name: :paid, initial: false, terminal: true}

      definition = %Definition{
        states: [draft, paid],
        events: [],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      assert Definition.is_terminal?(definition, :paid) == true
      assert Definition.is_terminal?(definition, :draft) == false
      assert Definition.is_terminal?(definition, :nonexistent) == false
    end

    test "available_events_from/2 returns valid events" do
      draft = %StateDefinition{name: :draft, initial: true, terminal: false}
      sent = %StateDefinition{name: :sent, initial: false, terminal: false}

      send_event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      definition = %Definition{
        states: [draft, sent],
        events: [send_event],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      events = Definition.available_events_from(definition, "draft")
      assert :send in events

      events = Definition.available_events_from(definition, "sent")
      refute :send in events
    end

    test "available_events_from/2 returns empty for terminal states" do
      draft = %StateDefinition{name: :draft, initial: true, terminal: false}
      paid = %StateDefinition{name: :paid, initial: false, terminal: true}

      send_event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [],
        side_effects: []
      }

      definition = %Definition{
        states: [draft, paid],
        events: [send_event],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      events = Definition.available_events_from(definition, "paid")
      assert events == []
    end

    test "to_diagram_data/1 converts to serializable format" do
      draft = %StateDefinition{name: :draft, initial: true, terminal: false}
      paid = %StateDefinition{name: :paid, initial: false, terminal: true}

      send_event = %EventDefinition{
        name: :send,
        from_states: [:draft],
        to_state: :sent,
        guards: [%{name: :has_line_items}],
        side_effects: [%{name: :notify_client}]
      }

      definition = %Definition{
        states: [draft, paid],
        events: [send_event],
        guards: [],
        side_effects: [],
        access: nil,
        snapshot: nil
      }

      data = Definition.to_diagram_data(definition)

      assert length(data.states) == 2
      assert length(data.events) == 1

      event_data = hd(data.events)
      assert event_data.name == :send
      assert event_data.from == [:draft]
      assert event_data.to == :sent
      assert event_data.guards == [:has_line_items]
      assert event_data.side_effects == [:notify_client]
    end
  end
end
