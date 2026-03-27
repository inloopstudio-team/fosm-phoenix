defmodule Fosm.Repo.Migrations.CreateRoleAssignments do
  @moduledoc """
  Creates the fosm_role_assignments table for RBAC role assignments.
  """
  use Ecto.Migration

  def up do
    create table(:fosm_role_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_type, :string, null: false, size: 255
      add :user_id, :string, null: false, size: 255
      add :resource_type, :string, null: false, size: 255
      add :resource_id, :string, size: 255
      add :role_name, :string, null: false, size: 255
      add :granted_by_type, :string, size: 255
      add :granted_by_id, :string, size: 255
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Unique constraint to prevent duplicate role assignments
    create unique_index(:fosm_role_assignments, 
      [:user_type, :user_id, :resource_type, :resource_id, :role_name],
      name: :role_assignments_unique_idx,
      where: "resource_id IS NOT NULL"
    )
    
    # Separate unique index for type-level assignments (where resource_id IS NULL)
    create unique_index(:fosm_role_assignments, 
      [:user_type, :user_id, :resource_type, :role_name],
      name: :role_assignments_type_level_unique_idx,
      where: "resource_id IS NULL"
    )

    # Indexes for common query patterns
    create index(:fosm_role_assignments, [:user_type, :user_id])
    create index(:fosm_role_assignments, [:resource_type, :resource_id])
    create index(:fosm_role_assignments, [:role_name])
    create index(:fosm_role_assignments, [:expires_at])
    
    # Partial index for active (non-expired) assignments
    create index(:fosm_role_assignments, [:user_type, :user_id, :resource_type],
      where: "expires_at IS NULL OR expires_at > NOW()",
      name: :role_assignments_active_idx
    )
  end

  def down do
    drop table(:fosm_role_assignments)
  end
end
