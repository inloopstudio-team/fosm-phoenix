defmodule Fosm.TransitionBuffer do
  @moduledoc """
  Buffered logging strategy GenServer for FOSM transition logs.
  
  This GenServer accumulates transition log entries in memory and flushes them:
  - Every #{@flush_interval_ms}ms (scheduled flush)
  - When buffer reaches #{@max_buffer_size} entries (size-based flush)
  - On manual flush call
  
  Benefits:
  - Reduces database write pressure during high-volume transitions
  - Batches inserts for better performance
  - Maintains durability guarantees through supervised crashes
  
  ## Usage
  
      # Push a log entry to the buffer
      Fosm.TransitionBuffer.push(%{
        record_type: "Invoice",
        record_id: invoice.id,
        event: "pay",
        from_state: "sent",
        to_state: "paid",
        actor_id: user.id,
        metadata: %{ip: conn.remote_ip}
      })
      
      # Manually flush the buffer
      Fosm.TransitionBuffer.flush()
  """
  use GenServer

  require Logger

  @flush_interval_ms 1000
  @max_buffer_size 100

  # Client API

  @doc """
  Starts the TransitionBuffer GenServer.
  
  ## Options
  
    * `:name` - The name to register the GenServer under (default: `__MODULE__`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Pushes a log entry to the buffer.
  
  Returns immediately (async). The entry will be flushed either:
  - When the buffer reaches #{@max_buffer_size} entries
  - At the next scheduled flush interval
  - On manual flush
  """
  @spec push(map()) :: :ok
  def push(log_data) do
    GenServer.cast(__MODULE__, {:push, log_data})
  end

  @doc """
  Manually triggers a flush of the current buffer.
  
  This is synchronous and waits for the flush to complete.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  @doc """
  Returns the current buffer size (for monitoring/debugging).
  """
  @spec buffer_size() :: non_neg_integer()
  def buffer_size do
    GenServer.call(__MODULE__, :buffer_size)
  end

  @doc """
  Returns the current buffer contents (for debugging only).
  """
  @spec peek() :: list(map())
  def peek do
    GenServer.call(__MODULE__, :peek)
  end

  # Server Callbacks

  @impl GenServer
  def init(_opts) do
    state = %{
      buffer: [],
      pending_flush: nil,
      flush_count: 0,
      error_count: 0
    }
    
    # Schedule the first periodic flush
    schedule_flush()
    
    Logger.info("TransitionBuffer started with flush_interval=#{@flush_interval_ms}ms, max_buffer_size=#{@max_buffer_size}")
    
    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:push, log_data}, %{buffer: buffer} = state) do
    # Add timestamp if not present
    log_data = Map.put_new_lazy(log_data, :inserted_at, fn -> DateTime.utc_now() end)
    
    new_buffer = [log_data | buffer]
    new_size = length(new_buffer)

    if new_size >= @max_buffer_size do
      # Trigger immediate flush
      case do_flush(new_buffer) do
        :ok ->
          {:noreply, %{state | buffer: [], flush_count: state.flush_count + 1}}
        
        {:error, _reason} ->
          # Keep buffer for retry, but continue accepting new entries
          {:noreply, %{state | buffer: new_buffer, error_count: state.error_count + 1}}
      end
    else
      {:noreply, %{state | buffer: new_buffer}}
    end
  end

  @impl GenServer
  def handle_call(:flush, _from, %{buffer: buffer} = state) do
    case do_flush(buffer) do
      :ok ->
        {:reply, :ok, %{state | buffer: [], flush_count: state.flush_count + 1}}
      
      {:error, reason} ->
        {:reply, {:error, reason}, %{state | error_count: state.error_count + 1}}
    end
  end

  @impl GenServer
  def handle_call(:buffer_size, _from, %{buffer: buffer} = state) do
    {:reply, length(buffer), state}
  end

  @impl GenServer
  def handle_call(:peek, _from, %{buffer: buffer} = state) do
    {:reply, Enum.reverse(buffer), state}
  end

  @impl GenServer
  def handle_info(:scheduled_flush, %{buffer: buffer} = state) do
    new_state = 
      if buffer != [] do
        case do_flush(buffer) do
          :ok ->
            %{state | buffer: [], flush_count: state.flush_count + 1}
          
          {:error, _reason} ->
            %{state | error_count: state.error_count + 1}
        end
      else
        state
      end
    
    # Schedule the next flush regardless of success/failure
    schedule_flush()
    
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp schedule_flush do
    Process.send_after(self(), :scheduled_flush, @flush_interval_ms)
  end

  # Empty buffer - nothing to do
  defp do_flush([]), do: :ok
  
  defp do_flush(buffer) when is_list(buffer) do
    # Reverse to maintain chronological order
    entries = Enum.reverse(buffer)
    
    # Chunk into batches of 100 for efficient bulk inserts
    entries
    |> Enum.chunk_every(100)
    |> Enum.reduce_while(:ok, fn chunk, _acc ->
      case bulk_insert(chunk) do
        {:ok, _count} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp bulk_insert(entries) when is_list(entries) do
    # This will use the actual Repo module when available
    # For now, we delegate to a configurable repo module
    repo = Application.get_env(:fosm, :repo, Fosm.Repo)
    
    try do
      # Use insert_all for efficient bulk insert
      count = repo.insert_all(Fosm.TransitionLog, entries, 
        returning: false,
        on_conflict: :nothing
      )
      
      Logger.debug("TransitionBuffer flushed #{count} entries")
      {:ok, count}
    rescue
      e ->
        Logger.error("TransitionBuffer flush failed: #{Exception.message(e)}")
        {:error, e}
    end
  end
end
