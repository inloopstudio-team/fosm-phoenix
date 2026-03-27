defmodule Elixir.Fosm.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices) do

      # FOSM state field (required)
      add :state, :string, null: false, default: "draft"

      # FOSM metadata for extensibility
      add :fosm_metadata, :map, default: %{}

      add :number, :string, null: false
      add :amount, :decimal, null: false
      add :due_date, :date, null: false

      timestamps()
    end

    # Indexes for efficient querying by state
    create index(:invoices, [:state])
    create index(:invoices, [:inserted_at])
    create index(:invoices, [:updated_at])

    # Composite indexes for common query patterns
    create index(:invoices, [:state, :inserted_at])
  end
end
