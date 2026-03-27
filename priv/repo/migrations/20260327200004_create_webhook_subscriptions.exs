defmodule Fosm.Repo.Migrations.CreateWebhookSubscriptions do
  @moduledoc """
  Creates the fosm_webhook_subscriptions table for webhook configuration.
  """
  use Ecto.Migration

  def up do
    create table(:fosm_webhook_subscriptions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:url, :string, null: false, size: 2000)
      add(:events, {:array, :string}, default: [])
      add(:record_type, :string, size: 255)
      add(:record_id, :string, size: 255)
      add(:secret_token, :string, size: 500)
      add(:active, :boolean, default: true, null: false)
      add(:delivery_mode, :string, default: "async", size: 10)
      add(:retry_count, :integer, default: 0)
      add(:last_delivery_at, :utc_datetime)
      add(:last_delivery_status, :string, size: 50)
      add(:metadata, :map, default: %{})

      timestamps(type: :utc_datetime)
    end

    # Unique constraint to prevent duplicate webhooks for same target
    create(
      unique_index(
        :fosm_webhook_subscriptions,
        [:url, :record_type, :record_id],
        name: :webhook_subscriptions_unique_idx
      )
    )

    # Indexes for common query patterns
    create(index(:fosm_webhook_subscriptions, [:active]))
    create(index(:fosm_webhook_subscriptions, [:record_type]))
    create(index(:fosm_webhook_subscriptions, [:record_type, :record_id]))
    create(index(:fosm_webhook_subscriptions, [:inserted_at]))

    if postgres?() do
      # GIN index for events array (PostgreSQL only)
      create(index(:fosm_webhook_subscriptions, [:events], using: :gin))

      # Partial index for active subscriptions only (PostgreSQL)
      create(
        index(:fosm_webhook_subscriptions, [:record_type, :record_id],
          where: "active = true",
          name: :webhook_subscriptions_active_idx
        )
      )

      # Index for subscriptions needing retry (PostgreSQL)
      create(
        index(:fosm_webhook_subscriptions, [:retry_count, :last_delivery_status],
          where: "active = true AND retry_count < 10",
          name: :webhook_subscriptions_needs_retry_idx
        )
      )

      # GIN index for metadata (PostgreSQL only)
      create(index(:fosm_webhook_subscriptions, [:metadata], using: :gin))
    end
  end

  def down do
    drop(table(:fosm_webhook_subscriptions))
  end

  # Helper to check if we're using PostgreSQL
  defp postgres? do
    repo = Application.get_env(:fosm, :ecto_repos, [Fosm.Repo]) |> List.first()
    config = if repo, do: Application.get_env(:fosm, repo, [])
    adapter = if config, do: Keyword.get(config, :adapter, Ecto.Adapters.Postgres)
    adapter == Ecto.Adapters.Postgres
  end
end
