defmodule Fosm.Agent.Session do
  @moduledoc """
  Manages agent conversation persistence using ETS.

  Provides in-memory storage for:
  - Agent state (tools, instructions, model config)
  - Conversation history (messages between user and agent)

  Features:
  - 4-hour TTL (configurable) for automatic cleanup
  - Periodic garbage collection of expired sessions
  - Public ETS table for concurrent access

  ## Usage

      # Store agent state
      Fosm.Agent.Session.store_agent(session_id, agent_state)

      # Retrieve agent state
      {:ok, agent_state} = Fosm.Agent.Session.fetch_agent(session_id)

      # Store conversation history
      Fosm.Agent.Session.store_history(session_id, messages)

      # Retrieve history
      {:ok, messages} = Fosm.Agent.Session.fetch_history(session_id)

      # Reset/clear a session
      Fosm.Agent.Session.reset(session_id)

  """
  use GenServer

  @table :fosm_agent_sessions
  @history_table :fosm_agent_history
  @default_ttl_hours 4
  @cleanup_interval :timer.minutes(10)

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Starts the Session GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores agent state for a session.

  ## Parameters
    - session_id: Unique identifier for the session (string)
    - agent_state: Map containing agent configuration (model, tools, instructions)

  ## Returns
    - :ok on success
  """
  @spec store_agent(String.t(), map()) :: :ok
  def store_agent(session_id, agent_state) when is_binary(session_id) and is_map(agent_state) do
    expires_at = calculate_expiry()
    :ets.insert(@table, {session_id, agent_state, expires_at})
    :ok
  end

  @doc """
  Retrieves agent state for a session.

  ## Returns
    - {:ok, agent_state} if found and not expired
    - :expired if the session has expired
    - :not_found if no session exists
  """
  @spec fetch_agent(String.t()) :: {:ok, map()} | :expired | :not_found
  def fetch_agent(session_id) when is_binary(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, agent_state, expires_at}] ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:ok, agent_state}
        else
          :expired
        end

      [] ->
        :not_found
    end
  end

  @doc """
  Stores conversation history for a session.

  ## Parameters
    - session_id: Unique identifier for the session
    - history: List of message maps (%{role: "user" | "assistant", content: String.t()})

  ## Returns
    - :ok on success
  """
  @spec store_history(String.t(), list(map())) :: :ok
  def store_history(session_id, history) when is_binary(session_id) and is_list(history) do
    expires_at = calculate_expiry()
    :ets.insert(@history_table, {session_id, history, expires_at})
    :ok
  end

  @doc """
  Retrieves conversation history for a session.

  ## Returns
    - {:ok, history} if found and not expired (history is empty list if not found)
    - :expired if the session has expired
  """
  @spec fetch_history(String.t()) :: {:ok, list(map())} | :expired
  def fetch_history(session_id) when is_binary(session_id) do
    case :ets.lookup(@history_table, session_id) do
      [{^session_id, history, expires_at}] ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:ok, history}
        else
          :expired
        end

      [] ->
        {:ok, []}
    end
  end

  @doc """
  Appends a message to the conversation history.

  ## Parameters
    - session_id: Unique identifier for the session
    - message: Message map to append (%{role: String.t(), content: String.t()})

  ## Returns
    - :ok on success
    - :not_found if no session exists (use store_history/2 first)
  """
  @spec append_message(String.t(), map()) :: :ok | :not_found
  def append_message(session_id, message) when is_binary(session_id) and is_map(message) do
    case fetch_history(session_id) do
      {:ok, history} ->
        store_history(session_id, history ++ [message])

      :expired ->
        # Reset with new message if expired
        store_history(session_id, [message])
    end
  end

  @doc """
  Resets/clears a session and its history.

  ## Returns
    - :ok on success
  """
  @spec reset(String.t()) :: :ok
  def reset(session_id) when is_binary(session_id) do
    :ets.delete(@table, session_id)
    :ets.delete(@history_table, session_id)
    :ok
  end

  @doc """
  Lists all active (non-expired) session IDs.

  ## Returns
    - List of session_id strings
  """
  @spec list_active_sessions() :: list(String.t())
  def list_active_sessions() do
    now = DateTime.utc_now()

    :ets.tab2list(@table)
    |> Enum.filter(fn {_id, _state, expires_at} ->
      DateTime.compare(expires_at, now) == :gt
    end)
    |> Enum.map(fn {id, _state, _expires} -> id end)
  end

  @doc """
  Returns the count of active sessions.
  """
  @spec session_count() :: non_neg_integer()
  def session_count() do
    list_active_sessions() |> length()
  end

  @doc """
  Manually triggers cleanup of expired sessions.
  Normally called automatically by the GenServer.
  """
  @spec cleanup_expired() :: non_neg_integer()
  def cleanup_expired() do
    now = DateTime.utc_now()

    # Delete expired agent states
    agent_deletes =
      :ets.select_delete(@table, [
        {{:"$1", :"$2", :"$3"}, [{:<, :"$3", {:const, now}}], [true]}
      ])

    # Delete expired histories
    history_deletes =
      :ets.select_delete(@history_table, [
        {{:"$1", :"$2", :"$3"}, [{:<, :"$3", {:const, now}}], [true]}
      ])

    agent_deletes + history_deletes
  end

  # ----------------------------------------------------------------------------
  # GenServer Callbacks
  # ----------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    # Create public ETS tables with read concurrency
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(@history_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    count = cleanup_expired()

    if count > 0 do
      require Logger
      Logger.info("[Fosm.Agent.Session] Cleaned up #{count} expired sessions")
    end

    schedule_cleanup()
    {:noreply, state}
  end

  # ----------------------------------------------------------------------------
  # Private Functions
  # ----------------------------------------------------------------------------

  defp calculate_expiry do
    hours = Application.get_env(:fosm, :agent_session_ttl_hours, @default_ttl_hours)
    DateTime.utc_now() |> DateTime.add(hours * 3600, :second)
  end

  defp schedule_cleanup do
    interval = Application.get_env(:fosm, :agent_session_cleanup_interval, @cleanup_interval)
    Process.send_after(self(), :cleanup, interval)
  end
end
