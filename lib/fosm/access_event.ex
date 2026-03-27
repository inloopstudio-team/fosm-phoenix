defmodule Fosm.AccessEvent do
  @moduledoc """
  Ecto schema for access control audit events.

  Immutable audit log for role grants, revocations, and auto-assignments.

  ## Fields

    * `action` - "grant", "revoke", or "auto_grant"
    * `user_type`, `user_id` - Who received/lost the role
    * `user_label` - Human-readable identifier
    * `resource_type`, `resource_id` - What resource
    * `role_name` - Which role
    * `performed_by_type`, `performed_by_id` - Who performed the action
    * `metadata` - Additional context
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @actions ["grant", "revoke", "auto_grant", "auto_revoke"]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "fosm_access_events" do
    field :action, :string  # grant, revoke, auto_grant, auto_revoke

    # Subject (who received/lost the role)
    field :user_type, :string
    field :user_id, :string
    field :user_label, :string

    # Resource
    field :resource_type, :string
    field :resource_id, :string

    # Role
    field :role_name, :string

    # Actor (who performed the action)
    field :performed_by_type, :string
    field :performed_by_id, :string

    # Metadata
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields [:action, :user_type, :user_id, :resource_type, :role_name]
  @optional_fields [:resource_id, :user_label, :performed_by_type, :performed_by_id, :metadata]

  @doc """
  Creates a changeset for access event.
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:action, @actions)
  end

  @doc """
  Creates an access event.
  """
  def create!(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Fosm.Repo.insert!()
  end

  # ============================================================================
  # Query Scopes
  # ============================================================================

  @doc """
  Scope: Recent events first.
  """
  def recent(query \\ __MODULE__, limit \\ 50) do
    from(e in query,
      order_by: [desc: e.inserted_at],
      limit: ^limit
    )
  end

  @doc """
  Scope: Events for a specific user.
  """
  def for_user(query \\ __MODULE__, user_type, user_id) do
    from(e in query,
      where: e.user_type == ^user_type,
      where: e.user_id == ^user_id
    )
  end

  @doc """
  Scope: Events for a specific resource.
  """
  def for_resource(query \\ __MODULE__, resource_type, resource_id) do
    from(e in query,
      where: e.resource_type == ^resource_type,
      where: e.resource_id == ^to_string(resource_id)
    )
  end

  @doc """
  Scope: Events for a specific role.
  """
  def for_role(query \\ __MODULE__, role_name) do
    from(e in query, where: e.role_name == ^to_string(role_name))
  end

  @doc """
  Scope: Events by action type.
  """
  def by_action(query \\ __MODULE__, action) do
    from(e in query, where: e.action == ^to_string(action))
  end

  @doc """
  Scope: Events within time range.
  """
  def between(query \\ __MODULE__, start_time, end_time) do
    from(e in query,
      where: e.inserted_at >= ^start_time,
      where: e.inserted_at <= ^end_time
    )
  end

  # ============================================================================
  # Predicates
  # ============================================================================

  @doc """
  Returns true if this was an auto-grant (via creator assignment).
  """
  def auto_grant?(%__MODULE__{} = event) do
    event.action == "auto_grant"
  end

  @doc """
  Returns true if this was an auto-revoke.
  """
  def auto_revoke?(%__MODULE__{} = event) do
    event.action == "auto_revoke"
  end

  @doc """
  Returns true if this was performed by a system process.
  """
  def by_system?(%__MODULE__{} = event) do
    event.performed_by_type == "system" || event.performed_by_type == ":system"
  end

  @doc """
  Returns true if this was performed by a human user.
  """
  def by_human?(%__MODULE__{} = event) do
    !by_system?(event) && event.performed_by_id != nil
  end
end
