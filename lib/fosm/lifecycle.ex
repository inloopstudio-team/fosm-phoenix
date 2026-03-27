defmodule Fosm.Lifecycle do
  @moduledoc """
  Transforms an Ecto schema into a finite state machine.

  ## Usage

      defmodule MyApp.Invoice do
        use Ecto.Schema
        use Fosm.Lifecycle

        schema "invoices" do
          field :state, :string
          field :amount, :decimal
          timestamps()
        end

        lifecycle do
          state :draft, initial: true
          state :sent
          state :paid, terminal: true

          event :send, from: :draft, to: :sent
          event :pay, from: :sent, to: :paid

          guard :positive_amount, on: :send do
            invoice.amount > 0
          end

          side_effect :notify_client, on: :send do
            Emailer.notify(invoice.client)
          end
        end
      end

  ## Generated Functions

  - State predicates: `draft?(record)`, `sent?(record)`, `paid?(record)`
  - Event methods: `send!(record, opts)`, `pay!(record, opts)`
  - Introspection: `can_send?(record)`, `available_events(record)`
  - Core: `fire!(record, event_name, opts)`, `why_cannot_fire?(record, event_name)`
  """

  alias Fosm.Lifecycle.{Definition, StateDefinition, EventDefinition, SnapshotConfiguration}

  defmacro __using__(_opts) do
    quote do
      import Fosm.Lifecycle, only: [lifecycle: 1]

      Module.register_attribute(__MODULE__, :fosm_states, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_events, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_guards, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_side_effects, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_roles, accumulate: true)
      Module.register_attribute(__MODULE__, :fosm_snapshot, accumulate: false)
      Module.register_attribute(__MODULE__, :fosm_snapshot_attrs, accumulate: false)

      @before_compile Fosm.Lifecycle
    end
  end

  defmacro lifecycle(do: block) do
    quote do
      import Fosm.Lifecycle.DSL
      unquote(block)
    end
  end

  defmacro __before_compile__(env) do
    states = Module.get_attribute(env.module, :fosm_states, [])
    events = Module.get_attribute(env.module, :fosm_events, [])
    guards = Module.get_attribute(env.module, :fosm_guards, [])
    side_effects = Module.get_attribute(env.module, :fosm_side_effects, [])
    roles = Module.get_attribute(env.module, :fosm_roles, [])
    snapshot = Module.get_attribute(env.module, :fosm_snapshot)
    snapshot_attrs = Module.get_attribute(env.module, :fosm_snapshot_attrs)

    # Apply snapshot attributes to config if provided
    snapshot = if snapshot && snapshot_attrs do
      SnapshotConfiguration.set_attributes(snapshot, snapshot_attrs)
    else
      snapshot
    end

    # Attach guards and side effects to events
    events_with_guards_and_effects = Enum.map(events, fn event ->
      event_guards = Enum.filter(guards, & &1.event == event.name)
      event_effects = Enum.filter(side_effects, & &1.event == event.name)

      %{event | guards: event_guards, side_effects: event_effects}
    end)

    # Build access definition if roles exist
    access_def = if roles != [] do
      default_role = Enum.find(roles, & &1.default)

      quote do
        %Fosm.Lifecycle.AccessDefinition{
          roles: unquote(Macro.escape(roles)),
          default_role: unquote(if(default_role, do: default_role.name, else: nil))
        }
      end
    else
      nil
    end

    lifecycle_def = quote do
      %Definition{
        states: unquote(Macro.escape(states)),
        events: unquote(Macro.escape(events_with_guards_and_effects)),
        guards: unquote(Macro.escape(guards)),
        side_effects: unquote(Macro.escape(side_effects)),
        access: unquote(access_def),
        snapshot: unquote(Macro.escape(snapshot))
      }
    end

    quote do
      def fosm_lifecycle, do: unquote(lifecycle_def)

      unquote(generate_state_predicates(states))
      unquote(generate_event_methods(events_with_guards_and_effects))
      unquote(generate_introspection_methods())
      unquote(generate_snapshot_methods())
    end
  end

  # Generate state predicate functions (e.g., draft?(record))
  defp generate_state_predicates(states) do
    Enum.map(states, fn %StateDefinition{name: name} ->
      predicate_name = String.to_atom("#{name}?")

      quote do
        def unquote(predicate_name)(%{state: state}) do
          state == unquote(to_string(name))
        end
      end
    end)
  end

  # Generate event methods (e.g., send!(record, opts))
  defp generate_event_methods(events) do
    Enum.map(events, fn %EventDefinition{name: name} ->
      method_name = String.to_atom("#{name}!")
      can_method_name = String.to_atom("can_#{name}?")

      quote do
        def unquote(method_name)(record, opts \\ []) do
          fire!(record, unquote(name), opts)
        end

        def unquote(can_method_name)(record) do
          can_fire?(record, unquote(name))
        end
      end
    end)
  end

  # Generate introspection methods
  defp generate_introspection_methods do
    quote do
      def fire!(record, event_name, opts \\ []) do
        Fosm.Lifecycle.Implementation.fire!(__MODULE__, record, event_name, opts)
      end

      def can_fire?(record, event_name) do
        Fosm.Lifecycle.Implementation.can_fire?(__MODULE__, record, event_name)
      end

      def why_cannot_fire?(record, event_name) do
        Fosm.Lifecycle.Implementation.why_cannot_fire?(__MODULE__, record, event_name)
      end

      def available_events(record) do
        Fosm.Lifecycle.Implementation.available_events(__MODULE__, record)
      end
    end
  end

  # Generate snapshot query methods
  defp generate_snapshot_methods do
    quote do
      def last_snapshot(record) do
        Fosm.TransitionLog
        |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
        |> Fosm.TransitionLog.with_snapshot()
        |> order_by(desc: :created_at)
        |> first()
        |> __schema__(:repo).one()
      end

      def last_snapshot_data(record) do
        case last_snapshot(record) do
          nil -> nil
          log -> log.state_snapshot
        end
      end

      def snapshots(record) do
        Fosm.TransitionLog
        |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
        |> Fosm.TransitionLog.with_snapshot()
        |> order_by(:created_at)
        |> __schema__(:repo).all()
      end

      def replay_from(record, transition_log_id) do
        Fosm.TransitionLog
        |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
        |> where([l], l.id > ^transition_log_id)
        |> order_by(:created_at)
        |> __schema__(:repo).all()
      end

      def transitions_since_snapshot(record) do
        case last_snapshot(record) do
          nil ->
            Fosm.TransitionLog
            |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
            |> __schema__(:repo).aggregate(:count)

          log ->
            Fosm.TransitionLog
            |> Fosm.TransitionLog.for_record(__schema__(:source), record.id)
            |> where([l], l.created_at > ^log.created_at)
            |> __schema__(:repo).aggregate(:count)
        end
      end
    end
  end
end
