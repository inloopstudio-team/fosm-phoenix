defmodule Fosm.Jobs.TransitionLogJob do
  @moduledoc """
  Oban worker for creating transition log records asynchronously.
  
  This job handles persisting state transition logs to the database.
  It includes proper error handling and retry logic with exponential backoff.
  """
  use Oban.Worker,
    queue: :fosm_logs,
    max_attempts: 5,
    priority: 1

  alias Fosm.TransitionLog

  @impl Oban.Worker
  def perform(%Oban.Job{args: log_data}) do
    # Normalize string keys to atom keys for Ecto
    normalized_args = normalize_keys(log_data)
    
    case TransitionLog.create(normalized_args) do
      {:ok, _log} ->
        :ok
        
      {:error, changeset} ->
        # Log the error details for debugging
        require Logger
        Logger.error("TransitionLogJob failed: #{inspect(changeset.errors)}")
        
        # For validation errors, we don't want to retry indefinitely
        # Mark as discardable after max_attempts
        {:error, changeset}
    end
  rescue
    e ->
      require Logger
      Logger.error("TransitionLogJob crashed: #{Exception.message(e)}")
      {:error, e}
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff with jitter: 1s, 2s, 4s, 8s, 16s
    :timer.seconds(2 ** attempt)
  end

  # Private functions

  defp normalize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_binary(key) ->
        Map.put(acc, String.to_existing_atom(key), normalize_keys(value))
      
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, normalize_keys(value))
    end)
  end
  
  defp normalize_keys(list) when is_list(list) do
    Enum.map(list, &normalize_keys/1)
  end
  
  defp normalize_keys(value), do: value
end
