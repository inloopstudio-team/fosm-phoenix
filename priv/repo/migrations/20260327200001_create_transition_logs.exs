defmodule Fosm.Repo.Migrations.CreateTransitionLogs do
  @moduledoc """
  Creates the fosm_transition_logs table for immutable audit logging.
  """
  use Ecto.Migration

  def up do
    create table(:fosm_transition_logs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:record_type, :string, null: false, size: 255)
      add(:record_id, :string, null: false, size: 255)
      add(:event_name, :string, null: false, size: 255)
      add(:from_state, :string, null: false, size: 255)
      add(:to_state, :string, null: false, size: 255)
      add(:actor_type, :string, size: 255)
      add(:actor_id, :string, size: 255)
      add(:actor_label, :string, size: 255)
      add(:metadata, :map, default: %{})
      add(:state_snapshot, :map)
      add(:snapshot_reason, :string, size: 50)
      add(:triggered_by, :map)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Composite indexes for common query patterns
    create(index(:fosm_transition_logs, [:record_type, :record_id]))
    create(index(:fosm_transition_logs, [:inserted_at]))
    create(index(:fosm_transition_logs, [:event_name]))
    create(index(:fosm_transition_logs, [:actor_type, :actor_id]))
    create(index(:fosm_transition_logs, [:from_state, :to_state]))

    # Partial index for entries with snapshots (PostgreSQL only)
    if postgres?() do
      create(
        index(:fosm_transition_logs, [:record_type, :record_id],
          where: "state_snapshot IS NOT NULL",
          name: :transition_logs_with_snapshot_idx
        )
      )

      # GIN indexes for JSONB fields (PostgreSQL only)
      create(index(:fosm_transition_logs, [:metadata], using: :gin))
      create(index(:fosm_transition_logs, [:state_snapshot], using: :gin))
      create(index(:fosm_transition_logs, [:triggered_by], using: :gin))
    end
  end

  def down do
    drop(table(:fosm_transition_logs))
  end

  # Helper to check if we're using PostgreSQL
  defp postgres? do
    repo = Application.get_env(:fosm, :ecto_repos, [Fosm.Repo]) |> List.first()
    config = if repo, do: Application.get_env(:fosm, repo, [])
    adapter = if config, do: Keyword.get(config, :adapter, Ecto.Adapters.Postgres)
    adapter == Ecto.Adapters.Postgres
  end
end
