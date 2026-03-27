defmodule <%= @module %> do
  @moduledoc """
  <%= @resource_name %> FOSM (Finite Object State Machine) model.

  This module defines the state machine lifecycle for <%= @resource_name %> records.
  Generated with fosm.gen.app.

  ## States
<%= for state <- @states do %>  * <%= state.name %> <%= if state.type == :initial, do: "(initial)", else: "" %><%= if state.type == :terminal, do: "(terminal)", else: "" %>
<% end %>
  ## Events
<%= for event <- @events do %>  * <%= event.name %> - <%= event.from %> → <%= event.to %>
<% end %>
  ## Usage

      # Create in initial state
<%= if @fields != [] do %>      {:ok, <%= @resource_path %>} = %<%= @module %>{}
        |> changeset(%{<%= Enum.map_join(@fields, ", ", fn {name, _} -> "#{name}: value" end) %>, state: :<%= Enum.find(@states, &(&1.type == :initial))[:name] %>})
        |> <%= @app_module %>.Repo.insert()
<% else %>      {:ok, <%= @resource_path %>} = %<%= @module %>{}
        |> changeset(%{state: :<%= Enum.find(@states, &(&1.type == :initial))[:name] %>})
        |> <%= @app_module %>.Repo.insert()
<% end %>

      # Transition via event
      {:ok, <%= @resource_path %>} = <%= @module %>.fire!(<%= @resource_path %>, :complete, actor: current_user)

  """

  use Ecto.Schema
  use Fosm.Lifecycle

  import Ecto.Changeset
<%= if @access_roles != [] do %>  import Fosm.RBAC
<% end %>
  alias <%= @app_module %>.Repo

  @type t :: %__MODULE__{}

<%= if @binary_id do %>  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
<% end %>
  schema "<%= @plural %>" do
    field :state, :string, default: "<%= Enum.find(@states, &(&1.type == :initial))[:name] %>"

<%= for {name, type} <- @fields do %>    field <%= inspect(name) %>, <%= inspect(type) %>
<% end %>

    # FOSM tracking fields
    field :fosm_metadata, :map, default: %{}

    timestamps()
  end

  @doc """
  Changeset for creating or updating a <%= @resource_name %>.
  Note: State should NOT be changed directly through changeset - use fire!/3.
  """
  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, [
      <%= Enum.map_join(@fields, ", ", fn {name, _} -> inspect(name) end) %>
    ])
<%= if @fields != [] do %>    |> validate_required([<%= Enum.map_join(Enum.take(@fields, min(2, length(@fields))), ", ", fn {name, _} -> inspect(name) end) %>])
<% else %>    # Add required validations here
<% end %>
  end

  @doc """
  Returns a changeset for the given state transition.
  This is called internally by fire!/3.
  """
  def state_changeset(struct, _event, _opts) do
    # Add any automatic field updates on transition here
    change(struct)
  end

  # ============================================================================
  # Lifecycle Definition
  # ============================================================================

  lifecycle do
    # --------------------------------------------------------------------------
    # States
    # --------------------------------------------------------------------------
<%= for state <- @states do %>    state <%= inspect(state.name) %><%= if state.type == :initial, do: ", initial: true", else: "" %><%= if state.type == :terminal, do: ", terminal: true", else: "" %>
<% end %>
    # --------------------------------------------------------------------------
    # Events (Transitions)
    # --------------------------------------------------------------------------
<%= for event <- @events do %>    event <%= inspect(event.name) %>, from: <%= if is_list(event.from), do: inspect(event.from), else: inspect(event.from) %>, to: <%= inspect(event.to) %>
<% end %>
    # TODO: Add more events as needed
    # Example:
    # event :send, from: :draft, to: :sent
    # event :pay, from: :sent, to: :paid

    # --------------------------------------------------------------------------
    # Guards (Validation)
    # --------------------------------------------------------------------------
    # Guards prevent invalid transitions. They run before the transition and must
    # return :ok or {:error, reason}.
    #
    # Example:
    # guard :has_required_fields, on: :complete do
    #   if record.name && record.amount do
    #     :ok
    #   else
    #     {:error, "Name and amount are required"}
    #   end
    # end
<%= for event <- @events do %>
    # guard :can_<%= event.name %>, on: <%= inspect(event.name) %> do
    #   # Add validation logic here
    #   :ok
    # end
<% end %>
<%= if @access_roles != [] do %>
    # --------------------------------------------------------------------------
    # Access Control Guards
    # --------------------------------------------------------------------------
    # Uncomment to enable RBAC guards:
    #
    # guard :check_access, on: :all do
    #   required_roles = [<%= Enum.map_join(@access_roles, ", ", &inspect/1) %>]
    #   if Fosm.Current.has_any_role?(actor, required_roles) do
    #     :ok
    #   else
    #     {:error, :access_denied}
    #   end
    # end
<% end %>
    # --------------------------------------------------------------------------
    # Side Effects (Actions)
    # --------------------------------------------------------------------------
    # Side effects run after the transition commits. They can be deferred
    # (async via Oban) or immediate.
    #
    # Example:
    # effect :send_notification, on: :send do
    #   # Runs immediately after commit
    #   MyApp.Notifier.send_email(record)
    # end
    #
    # effect :sync_to_crm, on: :pay, defer: true do
    #   # Queued as Oban job
    #   MyApp.CRM.sync(record)
    # end

  end

  # ============================================================================
  # State Predicates
  # ============================================================================

<%= for state <- @states do %>  @doc "Returns true if the record is in #{state.name} state."
  def <%= state.name %>?(record), do: record.state == "<%= state.name %>"
<% end %>
  # ============================================================================
  # Event Helpers
  # ============================================================================

<%= for event <- @events do %>  @doc "Fires the #{event.name} event with the given actor."
  def <%= event.name %>!(record, actor: actor) do
    fire!(record, <%= inspect(event.name) %>, actor: actor)
  end

  @doc "Returns true if #{event.name} can be fired from the current state."
  def can_<%= event.name %>?(record) do
    can_fire?(record, <%= inspect(event.name) %>)
  end
<% end %>
  # ============================================================================
  # Query Helpers
  # ============================================================================

  def with_state(query \\ __MODULE__, state) do
    from(q in query, where: q.state == ^state)
  end

  def initial_state(query \\ __MODULE__) do
    with_state(query, "<%= Enum.find(@states, &(&1.type == :initial))[:name] %>")
  end

  def terminal_states(query \\ __MODULE__) do
    states = [<%= Enum.filter(@states, &(&1.type == :terminal)) |> Enum.map_join(", ", fn s -> inspect(s.name) end) %>]
    from(q in query, where: q.state in ^states)
  end

  def non_terminal_states(query \\ __MODULE__) do
    states = [<%= Enum.filter(@states, &(&1.type != :terminal)) |> Enum.map_join(", ", fn s -> inspect(s.name) end) %>]
    from(q in query, where: q.state in ^states)
  end

  # ============================================================================
  # Snapshot Configuration
  # ============================================================================

  # Define what fields to capture in transition snapshots
  # def snapshot_configuration do
  #   %Fosm.Lifecycle.SnapshotConfiguration{
  #     attributes: [:name, :amount, :state],
  #     include_associations: [:line_items],
  #     include_metadata: true
  #   }
  # end
end
