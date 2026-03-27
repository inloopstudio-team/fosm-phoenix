defmodule Fosm.TransitionLog do
  @moduledoc """
  Immutable audit trail of every FOSM state transition.
  Records are never updated or deleted — this is an append-only log.
  Supports optional state snapshots for efficient replay and audit.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "fosm_transition_logs" do
    field :record_type, :string
    field :record_id, :string
    field :event_name, :string
    field :from_state, :string
    field :to_state, :string
    field :actor_type, :string
    field :actor_id, :string
    field :actor_label, :string
    field :metadata, :map, default: %{}
    field :state_snapshot, :map
    field :snapshot_reason, :string

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a transition log entry.
  """
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :record_type, :record_id, :event_name, :from_state, :to_state,
      :actor_type, :actor_id, :actor_label, :metadata, :state_snapshot, :snapshot_reason
    ])
    |> validate_required([
      :record_type, :record_id, :event_name, :from_state, :to_state
    ])
  end

  @doc """
  Creates a new transition log entry.
  """
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Fosm.Repo.insert()
  end

  @doc """
  Creates a new transition log entry, raising on error.
  """
  def create!(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Fosm.Repo.insert!()
  end

  @doc """
  Query scope: recent logs first.
  """
  def recent(query \\ base_query()) do
    query |> order_by(desc: :created_at)
  end

  @doc """
  Query scope: logs for a specific record.
  """
  def for_record(query \\ base_query(), record_type, record_id) do
    query
    |> where(record_type: ^record_type)
    |> where(record_id: ^to_string(record_id))
  end

  @doc """
  Query scope: logs for a specific app/model.
  """
  def for_app(query \\ base_query(), model_class) do
    query |> where(record_type: ^model_class.__schema__(:source))
  end

  @doc """
  Query scope: logs by event name.
  """
  def by_event(query \\ base_query(), event) do
    query |> where(event_name: ^to_string(event))
  end

  @doc """
  Query scope: logs by actor type.
  """
  def by_actor_type(query \\ base_query(), type) do
    query |> where(actor_type: ^type)
  end

  @doc """
  Query scope: logs with snapshots.
  """
  def with_snapshot(query \\ base_query()) do
    query |> where([l], not is_nil(l.state_snapshot))
  end

  @doc """
  Query scope: logs without snapshots.
  """
  def without_snapshot(query \\ base_query()) do
    query |> where([l], is_nil(l.state_snapshot))
  end

  @doc """
  Query scope: logs by snapshot reason.
  """
  def by_snapshot_reason(query \\ base_query(), reason) do
    query |> where(snapshot_reason: ^reason)
  end

  @doc """
  Returns true if the log entry was created by an AI agent.
  """
  def by_agent?(%__MODULE__{} = log) do
    log.actor_type == "symbol" && log.actor_label == "agent"
  end

  @doc """
  Returns true if the log entry was created by a human user.
  """
  def by_human?(%__MODULE__{} = log) do
    !by_agent?(log) && log.actor_id != nil
  end

  @doc """
  Returns true if the log entry was created by a system process.
  """
  def by_system?(%__MODULE__{} = log) do
    log.actor_type == "symbol" && log.actor_label != "agent"
  end

  @doc """
  Returns true if the log entry includes a state snapshot.
  """
  def snapshot?(%__MODULE__{} = log) do
    log.state_snapshot != nil
  end

  defp base_query do
    __MODULE__ |> where([l], is_nil(l.id) or not is_nil(l.id))
  end
end
