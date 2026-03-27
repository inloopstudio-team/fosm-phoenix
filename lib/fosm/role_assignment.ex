defmodule Fosm.RoleAssignment do
  @moduledoc """
  Ecto schema for role assignments.

  Represents a role granted to a user on a resource (type-level or record-level).

  ## Fields

    * `user_type` - String module name (e.g., "User")
    * `user_id` - String user ID (e.g., "42")
    * `resource_type` - String resource module (e.g., "Fosm.Invoice")
    * `resource_id` - String record ID or nil for type-level roles
    * `role_name` - String role name (e.g., "owner")
    * `granted_by_type` - Who granted this role
    * `granted_by_id` - Granter ID
    * `expires_at` - Optional expiration

  ## Unique Constraint

  [:user_type, :user_id, :resource_type, :resource_id, :role_name]
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "fosm_role_assignments" do
    field :user_type, :string
    field :user_id, :string
    field :resource_type, :string
    field :resource_id, :string  # nil for type-level roles
    field :role_name, :string
    field :granted_by_type, :string
    field :granted_by_id, :string
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:user_type, :user_id, :resource_type, :role_name]
  @optional_fields [:resource_id, :granted_by_type, :granted_by_id, :expires_at]

  @doc """
  Creates a changeset for role assignment.
  """
  def changeset(role_assignment, attrs) do
    role_assignment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:user_type, :user_id, :resource_type, :resource_id, :role_name],
      name: :fosm_role_assignments_unique_idx,
      message: "has already been taken"
    )
  end

  # ============================================================================
  # Query Scopes
  # ============================================================================

  @doc """
  Scope: Get assignments for a specific user.
  """
  def for_user(query \\ __MODULE__, user_type, user_id) do
    from(ra in query,
      where: ra.user_type == ^user_type,
      where: ra.user_id == ^user_id
    )
  end

  @doc """
  Scope: Get assignments for a specific resource.
  """
  def for_resource(query \\ __MODULE__, resource_type, resource_id \\ nil) do
    query = from(ra in query, where: ra.resource_type == ^resource_type)

    if resource_id do
      from(ra in query, where: ra.resource_id == ^to_string(resource_id))
    else
      from(ra in query, where: is_nil(ra.resource_id))
    end
  end

  @doc """
  Scope: Get assignments for a specific role.
  """
  def for_role(query \\ __MODULE__, role_name) do
    from(ra in query, where: ra.role_name == ^to_string(role_name))
  end

  @doc """
  Scope: Only active (non-expired) assignments.
  """
  def active(query \\ __MODULE__) do
    now = DateTime.utc_now()
    from(ra in query, where: is_nil(ra.expires_at) or ra.expires_at > ^now)
  end

  @doc """
  Scope: Get all roles for a user on a resource.
  """
  def roles_for(query \\ __MODULE__, user_type, user_id, resource_type, resource_id \\ nil) do
    query
    |> for_user(user_type, user_id)
    |> for_resource(resource_type, resource_id)
    |> active()
    |> select([ra], ra.role_name)
  end

  # ============================================================================
  # Helper Methods
  # ============================================================================

  @doc """
  Check if a user has a specific role.
  """
  def has_role?(user_type, user_id, resource_type, resource_id \\ nil, role_name) do
    __MODULE__
    |> for_user(user_type, user_id)
    |> for_resource(resource_type, resource_id)
    |> for_role(role_name)
    |> active()
    |> Fosm.Repo.exists?()
  end

  @doc """
  Get all role names for a user on a resource type (includes type-level and record-level).
  """
  def all_roles_for(user_type, user_id, resource_type, resource_id) do
    # Type-level roles
    type_roles =
      __MODULE__
      |> for_user(user_type, user_id)
      |> for_resource(resource_type, nil)
      |> active()
      |> select([ra], ra.role_name)
      |> Fosm.Repo.all()

    # Record-level roles
    record_roles =
      if resource_id do
        __MODULE__
        |> for_user(user_type, user_id)
        |> for_resource(resource_type, resource_id)
        |> active()
        |> select([ra], ra.role_name)
        |> Fosm.Repo.all()
      else
        []
      end

    (type_roles ++ record_roles)
    |> Enum.map(&String.to_atom/1)
    |> Enum.uniq()
  end

  @doc """
  Creates a role assignment and invalidates the cache.
  """
  def create_with_invalidation!(attrs) do
    # Build user struct for cache invalidation (if we can)
    user_type = attrs[:user_type] || attrs["user_type"]
    user_id = attrs[:user_id] || attrs["user_id"]

    # Create the assignment
    {:ok, assignment} =
      %__MODULE__{}
      |> changeset(attrs)
      |> Fosm.Repo.insert()

    # Try to invalidate cache
    invalidate_cache(user_type, user_id)

    {:ok, assignment}
  end

  @doc """
  Deletes a role assignment and invalidates the cache.
  """
  def delete_with_invalidation!(assignment) do
    # Get identity before deletion
    user_type = assignment.user_type
    user_id = assignment.user_id

    # Delete
    Fosm.Repo.delete!(assignment)

    # Invalidate cache
    invalidate_cache(user_type, user_id)

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp invalidate_cache(user_type, user_id) do
    # Try to construct a minimal struct for cache invalidation
    try do
      module = Module.concat([user_type])
      user = %{__struct__: module, id: user_id}
      Fosm.Current.invalidate_for(user)
    rescue
      _ ->
        # If we can't create the struct, the cache key will just miss
        # on next access, so it's not a critical error
        :ok
    end
  end
end
