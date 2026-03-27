defmodule <%= @app_module %>.Repo.Migrations.Create<%= Macro.camelize(@plural) %> do
  use Ecto.Migration

  def change do
    create table(:<%= @plural %><%= if @binary_id, do: ", primary_key: false", else: "" %>) do
<%= if @binary_id do %>      add :id, :binary_id, primary_key: true
<% end %>
      # FOSM state field (required)
      add :state, :string, null: false, default: "<%= Enum.find(@states, &(&1.type == :initial))[:name] || "draft" %>"

      # FOSM metadata for extensibility
      add :fosm_metadata, :map, default: %{}

<%= for {name, type} <- @fields do %><%= case type do
  :string -> "      add #{inspect(name)}, :string, null: false"
  :text -> "      add #{inspect(name)}, :text, null: false"
  :integer -> "      add #{inspect(name)}, :integer, null: false"
  :float -> "      add #{inspect(name)}, :float, null: false"
  :decimal -> "      add #{inspect(name)}, :decimal, null: false"
  :boolean -> "      add #{inspect(name)}, :boolean, null: false"
  :date -> "      add #{inspect(name)}, :date, null: false"
  :time -> "      add #{inspect(name)}, :time, null: false"
  :datetime -> "      add #{inspect(name)}, :utc_datetime, null: false"
  :naive_datetime -> "      add #{inspect(name)}, :naive_datetime, null: false"
  :utc_datetime -> "      add #{inspect(name)}, :utc_datetime, null: false"
  :uuid -> "      add #{inspect(name)}, :uuid, null: false"
  :binary -> "      add #{inspect(name)}, :binary, null: false"
  :map -> "      add #{inspect(name)}, :map, null: false"
  :array -> "      add #{inspect(name)}, {:array, :string}, null: false"
  :references -> "      add #{inspect(name)}, :integer"
  other -> "      add #{inspect(name)}, #{inspect(other)}, null: false"
end %>
<% end %>
      timestamps()
    end

    # Indexes for efficient querying by state
    create index(:<%= @plural %>, [:state])
    create index(:<%= @plural %>, [:inserted_at])
    create index(:<%= @plural %>, [:updated_at])

    # Composite indexes for common query patterns
    create index(:<%= @plural %>, [:state, :inserted_at])
  end
end
