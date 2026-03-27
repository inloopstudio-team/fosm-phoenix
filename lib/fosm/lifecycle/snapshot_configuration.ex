defmodule Fosm.Lifecycle.SnapshotConfiguration do
  @moduledoc """
  Configuration for state snapshots with multiple strategies.

  Strategies:
  - :every - Snapshot on every transition
  - :count - Snapshot every N transitions
  - :time - Snapshot every N seconds
  - :terminal - Snapshot when entering terminal states
  - :manual - Only snapshot when explicitly requested
  """

  defstruct [:strategy, :interval, :attributes, :conditions]

  @type strategy :: :every | :count | :time | :terminal | :manual
  @type t :: %__MODULE__{
    strategy: strategy(),
    interval: integer() | nil,
    attributes: [atom()] | nil,
    conditions: keyword() | nil
  }

  @doc """
  Creates a snapshot configuration that captures every transition.
  """
  def every do
    %__MODULE__{strategy: :every, interval: nil, attributes: nil, conditions: nil}
  end

  @doc """
  Creates a snapshot configuration that captures every N transitions.
  """
  def count(n) when is_integer(n) and n > 0 do
    %__MODULE__{strategy: :count, interval: n, attributes: nil, conditions: nil}
  end

  @doc """
  Creates a snapshot configuration that captures every N seconds.
  """
  def time(seconds) when is_integer(seconds) and seconds > 0 do
    %__MODULE__{strategy: :time, interval: seconds, attributes: nil, conditions: nil}
  end

  @doc """
  Creates a snapshot configuration that only captures on terminal states.
  """
  def terminal do
    %__MODULE__{strategy: :terminal, interval: nil, attributes: nil, conditions: nil}
  end

  @doc """
  Creates a snapshot configuration that only captures manually.
  """
  def manual do
    %__MODULE__{strategy: :manual, interval: nil, attributes: nil, conditions: nil}
  end

  @doc """
  Sets the attributes to include in the snapshot.
  """
  def set_attributes(%__MODULE__{} = config, attrs) when is_list(attrs) do
    %{config | attributes: attrs}
  end

  @doc """
  Determines if a snapshot should be taken based on configuration and transition data.

  Parameters:
  - config: The snapshot configuration
  - transition_count: Number of transitions since last snapshot (for :count strategy)
  - seconds_since_last: Seconds since last snapshot (for :time strategy)
  - to_state: The target state atom
  - to_state_terminal: Whether the target state is terminal
  - opts: Keyword options including :force to override

  Returns boolean indicating whether to snapshot.
  """
  def should_snapshot?(%__MODULE__{} = config, transition_count, seconds_since_last, to_state, to_state_terminal, opts \\ []) do
    force = Keyword.get(opts, :force)

    # Manual override handling
    cond do
      force == true -> true
      force == false -> false
      true -> strategy_matches?(config, transition_count, seconds_since_last, to_state_terminal)
    end
  end

  defp strategy_matches?(%__MODULE__{strategy: :every}, _, _, _), do: true
  defp strategy_matches?(%__MODULE__{strategy: :count, interval: n}, count, _, _) when is_integer(n) and n > 0, do: count >= n
  defp strategy_matches?(%__MODULE__{strategy: :time, interval: seconds}, _, elapsed, _) when is_integer(seconds) and seconds > 0, do: elapsed >= seconds
  defp strategy_matches?(%__MODULE__{strategy: :terminal}, _, _, true), do: true
  defp strategy_matches?(%__MODULE__{strategy: :terminal}, _, _, false), do: false
  defp strategy_matches?(%__MODULE__{strategy: :manual}, _, _, _), do: false
  defp strategy_matches?(_, _, _, _), do: false

  @doc """
  Builds a snapshot map for a record.

  Includes specified attributes (or defaults to all non-internal fields),
  serialized appropriately, plus metadata.
  """
  def build_snapshot(module, record, attrs \\ nil, extra_observations \\ nil) do
    attrs = attrs || default_attributes(module)

    base = %{
      _fosm_snapshot_meta: %{
        snapshot_at: DateTime.utc_now(),
        record_class: module.__schema__(:source),
        record_id: to_string(record.id)
      }
    }

    snapshot_data = Enum.reduce(attrs, base, fn attr, acc ->
      value = Map.get(record, attr)
      Map.put(acc, attr, serialize_value(value))
    end)

    # Merge arbitrary observations if provided
    if extra_observations do
      Map.put(snapshot_data, :_observations, extra_observations)
    else
      snapshot_data
    end
  end

  defp default_attributes(module) do
    # Exclude internal fields, return remaining fields
    module.__schema__(:fields)
    |> Enum.reject(& &1 in [:id, :state, :inserted_at, :updated_at, :created_by_id])
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp serialize_value(%Date{} = d), do: Date.to_iso8601(d)
  defp serialize_value(%Time{} = t), do: Time.to_iso8601(t)
  defp serialize_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp serialize_value(%_{} = struct), do: Map.from_struct(struct)
  defp serialize_value(list) when is_list(list), do: Enum.map(list, &serialize_value/1)
  defp serialize_value(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {k, serialize_value(v)} end) |> Map.new()
  end
  defp serialize_value(value), do: value
end
