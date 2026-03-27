defmodule Fosm.TransitionLog do
  @moduledoc """
  Schema for immutable transition logs.
  """

  import Ecto.Query

  # Placeholder schema definition - full implementation in task-4
  defstruct [
    :id,
    :record_type,
    :record_id,
    :event_name,
    :from_state,
    :to_state,
    :actor_type,
    :actor_id,
    :actor_label,
    :metadata,
    :state_snapshot,
    :snapshot_reason,
    :created_at
  ]

  @doc """
  Creates a new transition log entry.
  """
  def create!(attrs) do
    # Full implementation in task-4
    # For now, return a mock struct
    %__MODULE__{
      id: System.unique_integer([:positive]),
      record_type: attrs[:record_type],
      record_id: attrs[:record_id],
      event_name: attrs[:event_name],
      from_state: attrs[:from_state],
      to_state: attrs[:to_state],
      actor_type: attrs[:actor_type],
      actor_id: attrs[:actor_id],
      actor_label: attrs[:actor_label],
      metadata: attrs[:metadata],
      state_snapshot: attrs[:state_snapshot],
      snapshot_reason: attrs[:snapshot_reason],
      created_at: attrs[:created_at] || DateTime.utc_now()
    }
  end

  @doc """
  Query scope for filtering by record.
  """
  def for_record(query \\ __MODULE__, record_type, record_id) do
    # Placeholder - full implementation in task-4
    query
  end

  @doc """
  Query scope for records with snapshots.
  """
  def with_snapshot(query) do
    # Placeholder - full implementation in task-4
    query
  end

  @doc """
  Query scope for records without snapshots.
  """
  def without_snapshot(query) do
    # Placeholder - full implementation in task-4
    query
  end

  @doc """
  Query scope for filtering by snapshot reason.
  """
  def by_snapshot_reason(query, reason) do
    # Placeholder - full implementation in task-4
    query
  end

  @doc """
  Predicate to check if a log entry has a snapshot.
  """
  def snapshot?(%__MODULE__{state_snapshot: nil}), do: false
  def snapshot?(%__MODULE__{state_snapshot: _}), do: true
end
