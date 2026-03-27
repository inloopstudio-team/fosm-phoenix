defmodule <%= @app_module %>.Repo.Migrations.Create<%= Macro.camelize(@plural) %> do
  use Ecto.Migration

  def change do
    create table(:<%= @plural %><%= if @binary_id, do: ", primary_key: false", else: "" %>) do
<%= if @binary_id do %>      add :id, :binary_id, primary_key: true
<% end %>
      # FOSM state field (required)
      add :state, :string, null: false, default: "<%= if @states != [], do: Enum.find(@states, &(&1.type == :initial))[:name], else: "draft" %>"

      # FOSM metadata for extensibility
      add :fosm_metadata, :map, default: %{}

<%= for {name, type} <- @fields do %><%= render_field(name, type) %>
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

<%= for {name, type} <- @fields do %><%= case type do
  :references ->
    """
    # Add foreign key constraint (optional)
    # create index(:#{@plural}, [:#{name}])
    # alter table(:#{@plural}) do
    #   modify :#{name}, references(:other_table, on_delete: :nothing)
    # end
    """
  _ -> ""
end %><% end %>
  # Helper to render field definitions
  defp render_field(name, type) do
    type_def = case type do
      :string -> ":string"
      :text -> ":text"
      :integer -> ":integer"
      :float -> ":float"
      :decimal -> ":decimal"
      :boolean -> ":boolean"
      :date -> ":date"
      :time -> ":time"
      :datetime -> ":utc_datetime"
      :naive_datetime -> ":naive_datetime"
      :utc_datetime -> ":utc_datetime"
      :uuid -> ":uuid"
      :binary -> ":binary"
      :map -> ":map"
      :array -> "{:array, :string}"
      {:array, inner} -> "{:array, #{inner}}"
      :references -> ":integer"
      other -> inspect(other)
    end

    nullable = if type in [:references], do: "", else: ", null: false"

    "      add #{inspect(name)}, #{type_def}#{nullable}"
  end
end
