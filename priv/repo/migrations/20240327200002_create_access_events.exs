defmodule Fosm.Repo.Migrations.CreateAccessEvents do
  @moduledoc """
  Creates the fosm_access_events table for RBAC audit logging.
  """
  use Ecto.Migration

  def up do
    create table(:fosm_access_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string, null: false, size: 50
      add :user_type, :string, null: false, size: 255
      add :user_id, :string, null: false, size: 255
      add :resource_type, :string, null: false, size: 255
      add :resource_id, :string, size: 255
      add :role_name, :string, size: 255
      add :event_name, :string, size: 255
      add :result, :string, null: false, size: 50
      add :reason, :string, size: 1000
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Indexes for common query patterns
    create index(:fosm_access_events, [:user_type, :user_id])
    create index(:fosm_access_events, [:resource_type, :resource_id])
    create index(:fosm_access_events, [:action])
    create index(:fosm_access_events, [:result])
    create index(:fosm_access_events, [:inserted_at])
    
    # Composite index for access pattern queries
    create index(:fosm_access_events, [:user_type, :user_id, :resource_type])
    
    # Index for denied access monitoring
    create index(:fosm_access_events, [:inserted_at], 
      where: "result = 'denied'",
      name: :access_events_denied_idx
    )
    
    # GIN index for metadata
    create index(:fosm_access_events, [:metadata], using: :gin)
  end

  def down do
    drop table(:fosm_access_events)
  end
end
