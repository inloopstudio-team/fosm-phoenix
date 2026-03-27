defmodule Fosm.Repo.Migrations.CreateWebhookSubscriptions do
  @moduledoc """
  Creates the fosm_webhook_subscriptions table for webhook configuration.
  """
  use Ecto.Migration

  def up do
    create table(:fosm_webhook_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :url, :string, null: false, size: 2000
      add :events, {:array, :string}, default: []
      add :record_type, :string, size: 255
      add :record_id, :string, size: 255
      add :secret_token, :string, size: 500
      add :active, :boolean, default: true, null: false
      add :delivery_mode, :string, default: "async", size: 10
      add :retry_count, :integer, default: 0
      add :last_delivery_at, :utc_datetime
      add :last_delivery_status, :string, size: 50
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    # Unique constraint to prevent duplicate webhooks for same target
    create unique_index(:fosm_webhook_subscriptions,
      [:url, :record_type, :record_id],
      name: :webhook_subscriptions_unique_idx
    )

    # Indexes for common query patterns
    create index(:fosm_webhook_subscriptions, [:active])
    create index(:fosm_webhook_subscriptions, [:record_type])
    create index(:fosm_webhook_subscriptions, [:record_type, :record_id])
    create index(:fosm_webhook_subscriptions, [:events], using: :gin)
    create index(:fosm_webhook_subscriptions, [:inserted_at])
    
    # Partial index for active subscriptions only
    create index(:fosm_webhook_subscriptions, [:record_type, :record_id],
      where: "active = true",
      name: :webhook_subscriptions_active_idx
    )
    
    # Index for subscriptions needing retry
    create index(:fosm_webhook_subscriptions, [:retry_count, :last_delivery_status],
      where: "active = true AND retry_count < 10",
      name: :webhook_subscriptions_needs_retry_idx
    )
    
    # GIN index for metadata
    create index(:fosm_webhook_subscriptions, [:metadata], using: :gin)
  end

  def down do
    drop table(:fosm_webhook_subscriptions)
  end
end
