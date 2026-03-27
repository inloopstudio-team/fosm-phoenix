defmodule <%= @module %> do
  @moduledoc """
  Controller for <%= @resource_name %> FOSM resource.

  Provides REST API endpoints for managing <%= @plural %> through their lifecycle.
  """

  use <%= @web_module %>, :controller

  alias <%= @schema_module %>
  alias <%= @app_module %>.Repo

  action_fallback <%= @web_module %>.FallbackController

  @doc """
  List all <%= @plural %> with optional filtering by state.
  """
  def index(conn, params) do
    <%= @plural %> = list_<%= @plural %>(params)
    render(conn, :index, <%= @plural %>: <%= @plural %>)
  end

  @doc """
  Show a single <%= @resource_name %>.
  """
  def show(conn, %{"id" => id}) do
    <%= @resource_path %> = get_<%= @resource_path %>!(id)
    render(conn, :show, <%= @resource_path %>: <%= @resource_path %>)
  end

  @doc """
  Create a new <%= @resource_name %> in the initial state.
  """
  def create(conn, %{"<%= @resource_path %>" => <%= @resource_path %>_params}) do
    with {:ok, <%= @resource_path %>} <- create_<%= @resource_path %>(<%= @resource_path %>_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/<%= @plural %>/#{<%= @resource_path %>.id}")
      |> render(:show, <%= @resource_path %>: <%= @resource_path %>)
    end
  end

  @doc """
  Update <%= @resource_name %> attributes (not state - use events for that).
  """
  def update(conn, %{"id" => id, "<%= @resource_path %>" => <%= @resource_path %>_params}) do
    <%= @resource_path %> = get_<%= @resource_path %>!(id)

    with {:ok, <%= @resource_path %>} <- update_<%= @resource_path %>(<%= @resource_path %>, <%= @resource_path %>_params) do
      render(conn, :show, <%= @resource_path %>: <%= @resource_path %>)
    end
  end

  @doc """
  Fire a lifecycle event on the <%= @resource_name %>.

  POST /<%= @plural %>/:id/events

  Params:
    - event: The event name to fire (e.g., "complete", "send")
    - actor_id: ID of the user performing the action (for RBAC)

  Returns:
    - 200: Successful transition
    - 422: Guard failure or invalid transition
    - 403: Access denied
  """
  def fire_event(conn, %{"id" => id, "event" => event_name} = params) do
    <%= @resource_path %> = get_<%= @resource_path %>!(id)
    actor = get_actor(conn, params)

    event = String.to_atom(event_name)

    case <%= @schema_module %>.fire!(<%= @resource_path %>, event, actor: actor) do
      {:ok, updated} ->
        render(conn, :show, <%= @resource_path %>: updated)

      {:error, %Fosm.Errors.GuardFailed{guard: guard, reason: reason}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Guard failed", guard: guard, reason: reason})

      {:error, %Fosm.Errors.InvalidTransition{event: e, from: f}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Cannot #{e} from #{f}"})

      {:error, %Fosm.Errors.TerminalState{state: s}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Record is in terminal state: #{s}"})

      {:error, %Fosm.Errors.AccessDenied{action: a}} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied for #{a}"})
    end
  end

  @doc """
  Get available events for the current state of a <%= @resource_name %>.

  GET /<%= @plural %>/:id/available_events
  """
  def available_events(conn, %{"id" => id}) do
    <%= @resource_path %> = get_<%= @resource_path %>!(id)
    events = <%= @schema_module %>.available_events(<%= @resource_path %>)

    conn
    |> put_status(:ok)
    |> json(%{events: events, current_state: <%= @resource_path %>.state})
  end

  @doc """
  Get transition history for a <%= @resource_name %>.

  GET /<%= @plural %>/:id/transitions
  """
  def transitions(conn, %{"id" => id}) do
    <%= @resource_path %> = get_<%= @resource_path %>!(id)

    history =
      Fosm.TransitionLog
      |> Fosm.TransitionLog.for_record("<%= @plural %>", id)
      |> Fosm.TransitionLog.recent()
      |> Repo.all()

    conn
    |> put_status(:ok)
    |> json(%{transitions: history})
  end

  @doc """
  Delete a <%= @resource_name %>.

  Note: Only allowed from non-terminal states unless explicitly configured.
  """
  def delete(conn, %{"id" => id}) do
    <%= @resource_path %> = get_<%= @resource_path %>!(id)

    with {:ok, _} <- Repo.delete(<%= @resource_path %>) do
      send_resp(conn, :no_content, "")
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp list_<%= @plural %>(params) do
    query = <%= @schema_module %>

    query = case params["state"] do
      nil -> query
      state -> from(q in query, where: q.state == ^state)
    end

    query = case params["order_by"] do
      nil -> from(q in query, order_by: [desc: q.inserted_at])
      field -> from(q in query, order_by: [{^String.to_atom(params["order"] || "asc"), ^String.to_atom(field)}])
    end

    Repo.all(query)
  end

  defp get_<%= @resource_path %>!(id) do
    Repo.get!(<%= @schema_module %>, id)
  end

  defp create_<%= @resource_path %>(attrs) do
    %<%= @schema_module %>{}
    |> <%= @schema_module %>.changeset(attrs)
    |> Repo.insert()
  end

  defp update_<%= @resource_path %>(<%= @resource_path %>, attrs) do
    <%= @resource_path %>
    |> <%= @schema_module %>.changeset(attrs)
    |> Repo.update()
  end

  defp get_actor(conn, params) do
    # Resolve actor from params or current session
    case params["actor_id"] do
      nil ->
        # Fall back to current_user from session/token
        conn.assigns[:current_user] || :system

      actor_id ->
        # Look up user by ID
        case <%= @app_module %>.Accounts.get_user(actor_id) do
          nil -> conn.assigns[:current_user] || :system
          user -> user
        end
    end
  end
end
