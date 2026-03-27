defmodule Fosm.Lifecycle.StateDefinition do
  @moduledoc """
  Defines a state in the FOSM lifecycle.
  """
  defstruct [:name, :initial, :terminal]

  @type t :: %__MODULE__{
    name: atom(),
    initial: boolean(),
    terminal: boolean()
  }
end

defmodule Fosm.Lifecycle.EventDefinition do
  @moduledoc """
  Defines an event (transition) in the FOSM lifecycle.
  """
  defstruct [:name, :from_states, :to_state, :guards, :side_effects]

  @type t :: %__MODULE__{
    name: atom(),
    from_states: [atom()],
    to_state: atom(),
    guards: [Fosm.Lifecycle.GuardDefinition.t()],
    side_effects: [Fosm.Lifecycle.SideEffectDefinition.t()]
  }

  def add_guard(%__MODULE__{guards: guards} = event, guard) do
    %{event | guards: [guard | guards]}
  end

  def add_side_effect(%__MODULE__{side_effects: effects} = event, effect) do
    %{event | side_effects: [effect | effects]}
  end

  def valid_from?(%__MODULE__{from_states: from_states}, state) do
    state in from_states
  end
end

defmodule Fosm.Lifecycle.GuardDefinition do
  @moduledoc """
  Defines a guard condition for an event.
  """
  defstruct [:name, :event, :check, :line, :file]

  @type t :: %__MODULE__{
    name: atom(),
    event: atom(),
    check: (any() -> :ok | {:error, String.t() | nil} | boolean()),
    line: integer(),
    file: String.t()
  }

  def evaluate(%__MODULE__{check: check}, record) do
    try do
      case check.(record) do
        true -> :ok
        :ok -> :ok
        false -> {:error, nil}
        :error -> {:error, nil}
        {:error, reason} -> {:error, reason}
        msg when is_binary(msg) -> {:error, msg}
        [:fail, reason] -> {:error, reason}
        _ -> :ok
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end
end

defmodule Fosm.Lifecycle.SideEffectDefinition do
  @moduledoc """
  Defines a side effect for an event.
  """
  defstruct [:name, :event, :effect, :defer, :line, :file]

  @type t :: %__MODULE__{
    name: atom(),
    event: atom(),
    effect: (any(), map() -> any()),
    defer: boolean(),
    line: integer(),
    file: String.t()
  }

  def deferred?(%__MODULE__{defer: defer}), do: defer == true

  def call(%__MODULE__{effect: effect}, record, transition_data) do
    effect.(record, transition_data)
  end
end

defmodule Fosm.Lifecycle.RoleDefinition do
  @moduledoc """
  Defines a role for access control.
  """
  defstruct [:name, :default, :crud_permissions, :event_permissions]

  @type t :: %__MODULE__{
    name: atom(),
    default: boolean(),
    crud_permissions: [:create | :read | :update | :delete],
    event_permissions: [atom()]
  }

  def can?(%__MODULE__{crud_permissions: crud, event_permissions: events}, :crud) do
    :create in crud and :read in crud and :update in crud and :delete in crud
  end

  def can?(%__MODULE__{crud_permissions: crud}, perm) when perm in [:create, :read, :update, :delete] do
    perm in crud
  end

  def can?(%__MODULE__{event_permissions: events}, event) when is_atom(event) do
    event in events
  end

  def can_crud?(%__MODULE__{crud_permissions: crud}) do
    crud != []
  end

  def can_event?(%__MODULE__{event_permissions: events}) do
    events != []
  end

  def all_permissions(%__MODULE__{crud_permissions: crud, event_permissions: events}) do
    crud ++ events
  end
end

defmodule Fosm.Lifecycle.AccessDefinition do
  @moduledoc """
  Defines access control for a lifecycle.
  """
  defstruct [:roles, :default_role]

  @type t :: %__MODULE__{
    roles: [Fosm.Lifecycle.RoleDefinition.t()],
    default_role: atom() | nil
  }

  def roles_for_event(%__MODULE__{roles: roles}, event) do
    Enum.filter(roles, fn role ->
      Fosm.Lifecycle.RoleDefinition.can?(role, event)
    end)
  end

  def roles_for_crud(%__MODULE__{roles: roles}, action) do
    Enum.filter(roles, fn role ->
      Fosm.Lifecycle.RoleDefinition.can?(role, action)
    end)
  end

  def find_role(%__MODULE__{roles: roles}, name) do
    Enum.find(roles, fn role -> role.name == name end)
  end
end

defmodule Fosm.Lifecycle.Definition do
  @moduledoc """
  The compiled lifecycle definition containing all states, events, guards, etc.
  """
  defstruct [:states, :events, :guards, :side_effects, :access, :snapshot]

  @type t :: %__MODULE__{
    states: [Fosm.Lifecycle.StateDefinition.t()],
    events: [Fosm.Lifecycle.EventDefinition.t()],
    guards: [Fosm.Lifecycle.GuardDefinition.t()],
    side_effects: [Fosm.Lifecycle.SideEffectDefinition.t()],
    access: Fosm.Lifecycle.AccessDefinition.t() | nil,
    snapshot: Fosm.Lifecycle.SnapshotConfiguration.t() | nil
  }

  def find_event(%__MODULE__{events: events}, name) do
    Enum.find(events, fn e -> e.name == name end)
  end

  def find_state(%__MODULE__{states: states}, name) do
    Enum.find(states, fn s -> s.name == name end)
  end

  def state_names(%__MODULE__{states: states}) do
    Enum.map(states, & &1.name)
  end

  def event_names(%__MODULE__{events: events}) do
    Enum.map(events, & &1.name)
  end

  def available_events_from(%__MODULE__{} = lifecycle, state) do
    lifecycle.events
    |> Enum.filter(fn event ->
      Fosm.Lifecycle.EventDefinition.valid_from?(event, state) and
        not is_terminal?(lifecycle, state)
    end)
    |> Enum.map(& &1.name)
  end

  def is_terminal?(%__MODULE__{states: states}, state_name) do
    case Enum.find(states, fn s -> s.name == state_name end) do
      nil -> false
      state -> state.terminal == true
    end
  end

  def to_diagram_data(%__MODULE__{} = lifecycle) do
    %{
      states: Enum.map(lifecycle.states, fn s ->
        %{
          name: s.name,
          initial: s.initial,
          terminal: s.terminal
        }
      end),
      events: Enum.map(lifecycle.events, fn e ->
        %{
          name: e.name,
          from: e.from_states,
          to: e.to_state,
          guards: Enum.map(e.guards, & &1.name),
          side_effects: Enum.map(e.side_effects, & &1.name)
        }
      end)
    }
  end
end
