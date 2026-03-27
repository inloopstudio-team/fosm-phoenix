defmodule Fosm.Current do
  @moduledoc """
  Per-request RBAC cache using Agent.

  Loads ALL role assignments for an actor in ONE query on first access,
  serves subsequent checks from in-memory map (O(1)).

  Cache structure:
  %{
    "User:42" => %{
      "Fosm.Invoice" => %{
        nil => [:owner],           # type-level roles
        "5" => [:approver]         # record-level roles
      }
    }
  }

  ## Usage

      # Check roles (first call loads from DB, subsequent calls use cache)
      Fosm.Current.roles_for(user, "Fosm.Invoice", nil)        # type-level
      Fosm.Current.roles_for(user, "Fosm.Invoice", invoice.id) # record-level

      # Invalidate after role changes
      Fosm.Current.invalidate_for(user)

      # Clear entire cache (testing)
      Fosm.Current.clear()

  ## Supervision

  Add to your application supervision tree:

      children = [
        # ... other children ...
        Fosm.Current
      ]
  """

  use Agent

  @cache_key :fosm_access_cache

  # Default name for the Agent
  @default_name __MODULE__

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the RBAC cache Agent.

  ## Options

    * `:name` - The name to register the Agent under (default: Fosm.Current)

  ## Examples

      # In supervision tree
      children = [
        Fosm.Current
      ]

      # With custom name
      Fosm.Current.start_link(name: :my_cache)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @doc """
  Returns all roles for an actor on a given resource type and optional record.

  First call loads ALL role assignments for the actor in ONE query.
  Subsequent calls are O(1) lookups from the in-memory cache.

  ## Parameters

    * `actor` - The actor (user, agent, etc.) struct with `__struct__` and `id`
    * `resource_type` - String module name (e.g., "Fosm.Invoice")
    * `record_id` - Optional record ID for record-level roles (default: nil)

  ## Returns

  List of role atoms, e.g., `[:owner, :approver]`

  ## Examples

      # Type-level roles only
      Fosm.Current.roles_for(user, "Fosm.Invoice", nil)
      # => [:owner]

      # Type-level + record-level roles
      Fosm.Current.roles_for(user, "Fosm.Invoice", 5)
      # => [:owner, :approver]

  ## RBAC Bypass Cases

  Returns `[:_all]` (universal permission) for:
    * nil actors
    * Symbol actors (:system, :agent)
    * Actors with `superadmin?` function returning true
  """
  def roles_for(actor, resource_type, record_id \\ nil, opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)

    # RBAC bypass cases
    cond do
      # nil actor - no authentication
      is_nil(actor) ->
        [:_all]

      # Symbol actors (:system, :agent) - internal processes
      is_atom(actor) and not is_struct(actor) ->
        [:_all]

      # Superadmin check
      superadmin?(actor) ->
        [:_all]

      # Normal role lookup
      true ->
        actor_key = cache_key(actor)

        # Get or load actor's role data
        actor_data = Agent.get(name, &Map.get(&1, actor_key))

        actor_data =
          case actor_data do
            nil ->
              data = load_for_actor(actor)
              Agent.update(name, &Map.put(&1, actor_key, data))
              data

            data ->
              data
          end

        # Combine type-level and record-level roles
        type_roles = get_in(actor_data, [resource_type, nil]) || []

        record_roles =
          if record_id do
            get_in(actor_data, [resource_type, to_string(record_id)]) || []
          else
            []
          end

        Enum.uniq(type_roles ++ record_roles)
    end
  end

  @doc """
  Invalidates the cache for a specific actor.

  Call this after granting or revoking roles for the actor.

  ## Examples

      # After granting a role
      Fosm.RoleAssignment.create!(...)
      Fosm.Current.invalidate_for(user)

      # After revoking a role
      Fosm.Repo.delete!(assignment)
      Fosm.Current.invalidate_for(user)
  """
  def invalidate_for(actor, opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    actor_key = cache_key(actor)
    Agent.update(name, &Map.delete(&1, actor_key))
  end

  @doc """
  Clears the entire cache.

  Useful for testing or when you need to force a full reload.

  ## Examples

      # In tests (setup or teardown)
      Fosm.Current.clear()
  """
  def clear(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    Agent.update(name, fn _ -> %{} end)
  end

  # ============================================================================
  # Internal Functions
  # ============================================================================

  # Generates a cache key for an actor
  # Format: "ModuleName:id"
  # Example: "User:42", "Fosm.Agent:5"
  defp cache_key(actor) when is_struct(actor) do
    "#{actor.__struct__}:#{actor.id}"
  end

  defp cache_key(actor) when is_atom(actor) do
    to_string(actor)
  end

  defp cache_key(actor) do
    to_string(actor)
  end

  # Loads all role assignments for an actor in ONE query
  # Returns nested map structure:
  # %{
  #   "Fosm.Invoice" => %{
  #     nil => [:owner],
  #     "5" => [:approver]
  #   }
  # }
  defp load_for_actor(actor) do
    import Ecto.Query

    # Determine user type and id from actor
    {user_type, user_id} = extract_actor_identity(actor)

    # Single query to load ALL role assignments
    Fosm.RoleAssignment
    |> where([r], r.user_type == ^user_type and r.user_id == ^user_id)
    |> Fosm.Repo.all()
    |> Enum.reduce(%{}, fn assignment, cache ->
      type = assignment.resource_type
      id = assignment.resource_id  # nil for type-level, string ID for record-level
      role = String.to_atom(assignment.role_name)

      cache
      |> Map.put_new(type, %{})
      |> update_in([type, id], fn existing ->
        [role | (existing || [])]
      end)
    end)
  end

  # Extracts user type and id from various actor formats
  defp extract_actor_identity(actor) when is_struct(actor) do
    user_type = to_string(actor.__struct__)
    user_id = to_string(actor.id)
    {user_type, user_id}
  end

  defp extract_actor_identity(actor) when is_map(actor) do
    user_type = Map.get(actor, :__struct__, "Unknown") |> to_string()
    user_id = Map.get(actor, :id, "") |> to_string()
    {user_type, user_id}
  end

  defp extract_actor_identity(actor) do
    {to_string(actor.__struct__), to_string(actor.id)}
  end

  # Safe nested map access
  defp get_in(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce(keys, map, fn key, acc ->
      case acc do
        nil -> nil
        %{} -> Map.get(acc, key)
        _ -> nil
      end
    end)
  end

  defp get_in(_map, _keys), do: nil

  # Nested map update helper
  defp update_in(map, keys, fun) when is_map(map) and is_list(keys) do
    do_update_in(map, keys, fun)
  end

  defp do_update_in(map, [key], fun) do
    value = Map.get(map, key)
    Map.put(map, key, fun.(value))
  end

  defp do_update_in(map, [key | rest], fun) do
    inner = Map.get(map, key) || %{}
    Map.put(map, key, do_update_in(inner, rest, fun))
  end

  # Check if actor is a superadmin
  # Supports both function-based and field-based checks
  defp superadmin?(actor) do
    cond do
      # Function-based check (preferred)
      function_exported?(actor.__struct__, :superadmin?, 1) ->
        actor.__struct__.superadmin?(actor)

      # Field-based check (fallback)
      is_map(actor) and Map.has_key?(actor, :superadmin) ->
        Map.get(actor, :superadmin) == true

      is_map(actor) and Map.has_key?(actor, :is_superadmin) ->
        Map.get(actor, :is_superadmin) == true

      true ->
        false
    end
  rescue
    _ -> false
  end

  # Helper for child_spec (for supervision tree)
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end
end
