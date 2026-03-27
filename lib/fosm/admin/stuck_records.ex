defmodule Fosm.Admin.StuckRecords do
  @moduledoc """
  Detects records that may be stuck in a non-terminal state without progress.

  A record is considered "stuck" if:
  1. It's in a non-terminal state
  2. No transitions have occurred within the stale threshold (default: 7 days)

  This helps identify records that may need manual intervention or debugging.

  ## Usage

      # Detect stuck records for a specific model
      stuck = Fosm.Admin.StuckRecords.detect(Fosm.Invoice)
      # => [%Fosm.Invoice{id: 1, state: "pending", ...}, ...]

      # With custom options
      Fosm.Admin.StuckRecords.detect(Fosm.Invoice, stale_days: 14, states: ["pending", "review"])

      # Just get the count
      count = Fosm.Admin.StuckRecords.count(Fosm.Invoice)

      # Get summary across all FOSM models
      summary = Fosm.Admin.StuckRecords.summary()
  """

  import Ecto.Query
  require Logger

  @default_stale_days 7

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Detects stuck records for a given FOSM module.

  ## Parameters

    * `module` - The FOSM module (e.g., `Fosm.Invoice`)
    * `opts` - Options:
      * `:stale_days` - Days without transition to be considered stale (default: 7)
      * `:states` - List of states to check (default: all non-terminal states)
      * `:limit` - Maximum records to return (default: nil = no limit)

  ## Returns

  List of stuck records

  ## Examples

      # Default: 7 days, all non-terminal states
      Fosm.Admin.StuckRecords.detect(Fosm.Invoice)

      # 14 days, specific states only
      Fosm.Admin.StuckRecords.detect(Fosm.Invoice, stale_days: 14, states: ["pending"])

      # Limit results
      Fosm.Admin.StuckRecords.detect(Fosm.Invoice, limit: 10)
  """
  def detect(module, opts \\ []) do
    lifecycle = module.fosm_lifecycle()
    stale_days = Keyword.get(opts, :stale_days, @default_stale_days)
    limit = Keyword.get(opts, :limit)

    # Determine which states to check
    states_to_check =
      case Keyword.get(opts, :states) do
        nil ->
          # All non-terminal states
          lifecycle.states
          |> Enum.reject(& &1.terminal)
          |> Enum.map(&to_string(&1.name))

        states when is_list(states) ->
          Enum.map(states, &to_string/1)
      end

    # Short-circuit if no states to check
    if states_to_check == [] do
      []
    else
      # Get records in non-terminal states
      base_query =
        from(r in module,
          where: r.state in ^states_to_check
        )

      base_query = if limit, do: limit(base_query, ^limit), else: base_query

      candidates = Fosm.Repo.all(base_query)

      # Check which have recent transitions (efficient batch query)
      candidate_ids = Enum.map(candidates, & &1.id)

      # Edge case: no candidates
      if candidate_ids == [] do
        []
      else
        # Get IDs of recently active records in ONE query
        recently_active_ids =
          get_recently_active_ids(module, candidate_ids, stale_days)

        # Return records NOT in recently_active
        Enum.reject(candidates, fn r ->
          to_string(r.id) in recently_active_ids
        end)
      end
    end
  end

  @doc """
  Counts stuck records for a given FOSM module.

  More efficient than `detect/2` when you only need the count.

  ## Examples

      count = Fosm.Admin.StuckRecords.count(Fosm.Invoice)
      # => 42
  """
  def count(module, opts \\ []) do
    detect(module, opts) |> length()
  end

  @doc """
  Provides a summary of stuck records across all FOSM models.

  ## Examples

      summary = Fosm.Admin.StuckRecords.summary()
      # => %{
      #   "invoices" => %{count: 5, states: %{"pending" => 3, "review" => 2}},
      #   "contracts" => %{count: 0, states: %{}},
      #   ...
      # }
  """
  def summary(opts \\ []) do
    stale_days = Keyword.get(opts, :stale_days, @default_stale_days)

    # Get all registered FOSM modules
    modules = Fosm.Registry.all()

    Enum.reduce(modules, %{}, fn {_slug, module}, acc ->
      stuck = detect(module, stale_days: stale_days)

      if stuck == [] do
        acc
      else
        # Group by state
        by_state =
          Enum.group_by(stuck, & &1.state)
          |> Enum.map(fn {state, records} -> {state, length(records)} end)
          |> Map.new()

        key = module.__schema__(:source)

        Map.put(acc, key, %{
          count: length(stuck),
          states: by_state
        })
      end
    end)
  end

  @doc """
  Returns detailed information about stuck records for a module.

  Includes last transition info and duration since last activity.

  ## Examples

      details = Fosm.Admin.StuckRecords.details(Fosm.Invoice)
      # => [
      #   %{
      #     record: %Fosm.Invoice{...},
      #     state: "pending",
      #     last_transition_at: ~U[2024-03-20 10:00:00Z],
      #     days_since_transition: 10,
      #     available_events: [:cancel, :remind]
      #   },
      #   ...
      # ]
  """
  def details(module, opts \\ []) do
    stuck = detect(module, opts)

    # Get last transition info for each stuck record
    Enum.map(stuck, fn record ->
      last_transition = get_last_transition(module, record.id)

      days_since =
        if last_transition do
          DateTime.diff(DateTime.utc_now(), last_transition.created_at, :day)
        else
          # No transitions ever - use record creation time
          DateTime.diff(DateTime.utc_now(), record.inserted_at, :day)
        end

      %{
        record: record,
        state: record.state,
        last_transition_at: last_transition && last_transition.created_at,
        days_since_transition: days_since,
        available_events: module.available_events(record)
      }
    end)
  end

  @doc """
  Triggers alerts or notifications for stuck records.

  ## Examples

      # Send alert for all stuck invoices older than 14 days
      Fosm.Admin.StuckRecords.alert(Fosm.Invoice,
        stale_days: 14,
        callback: fn record ->
          MyApp.Notifications.notify(:stuck_record, record)
        end
      )
  """
  def alert(module, opts \\ []) do
    stuck = detect(module, opts)
    callback = Keyword.get(opts, :callback)

    if callback do
      Enum.each(stuck, callback)
    end

    stuck
  end

  @doc """
  Generates a report of stuck records across all models.

  ## Examples

      report = Fosm.Admin.StuckRecords.report()
      # => "Stuck Records Report\n\nInvoices (5):\n  - pending: 3\n  - review: 2\n\n..."
  """
  def report(opts \\ []) do
    stale_days = Keyword.get(opts, :stale_days, @default_stale_days)
    summary_data = summary(stale_days: stale_days)

    lines = ["Stuck Records Report", "=" |> String.duplicate(40)]

    lines =
      if summary_data == %{} do
        ["No stuck records found." | lines]
      else
        Enum.reduce(summary_data, lines, fn {model_name, data}, acc ->
          state_lines =
            Enum.map(data.states, fn {state, count} ->
              "  - #{state}: #{count}"
            end)

          ["#{model_name}: #{data.count} total" | state_lines] ++ acc
        end)
      end

    lines
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  # ============================================================================
  # Internal Functions
  # ============================================================================

  # Gets IDs of records that have had recent transitions
  # Returns MapSet of record_id strings
  defp get_recently_active_ids(module, candidate_ids, stale_days) do
    resource_type = module.__schema__(:source)
    stale_threshold = DateTime.utc_now() |> DateTime.add(-stale_days, :day)

    recently_active =
      from(t in Fosm.TransitionLog,
        where: t.record_type == ^resource_type,
        where: t.record_id in ^Enum.map(candidate_ids, &to_string/1),
        where: t.created_at > ^stale_threshold,
        select: t.record_id,
        distinct: true
      )
      |> Fosm.Repo.all()

    MapSet.new(recently_active)
  end

  # Gets the last transition for a specific record
  defp get_last_transition(module, record_id) do
    resource_type = module.__schema__(:source)

    from(t in Fosm.TransitionLog,
      where: t.record_type == ^resource_type,
      where: t.record_id == ^to_string(record_id),
      order_by: [desc: t.created_at],
      limit: 1
    )
    |> Fosm.Repo.one()
  end
end
