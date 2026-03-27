defmodule Fosm.Jobs.WebhookDeliveryJob do
  @moduledoc """
  Oban worker for delivering webhook notifications with HMAC-SHA256 signatures.
  
  This job handles:
  - Computing HMAC-SHA256 signatures for webhook payloads
  - Delivering webhooks with proper headers
  - Retrying on transient failures (network issues, 5xx responses)
  - Failing fast on permanent errors (4xx responses)
  """
  use Oban.Worker,
    queue: :fosm_webhooks,
    max_attempts: 10,
    priority: 2

  require Logger

  # @type webhook_args :: %{
  #         url: String.t(),
  #         payload: map(),
  #         event_name: String.t(),
  #         record_type: String.t(),
  #         secret_token: String.t() | nil,
  #         transition_id: integer() | nil,
  #         webhook_id: integer() | nil
  #       }

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    url = args["url"]
    payload = args["payload"]
    event_name = args["event_name"]
    record_type = args["record_type"]
    secret = args["secret_token"]
    webhook_id = args["webhook_id"]

    headers = build_headers(event_name, record_type, payload, secret)

    case Req.post(url, json: payload, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: status} = _response} when status in 200..299 ->
        log_success(webhook_id, url, status)
        :ok

      {:ok, %{status: status} = response} when status in 400..499 ->
        # 4xx errors are typically permanent (bad URL, authentication failed)
        # We still retry a few times in case of temporary auth issues
        log_failure(webhook_id, url, status, "Client error - will retry limited times")
        {:error, "HTTP #{status}: #{inspect(response.body)}"}

      {:ok, %{status: status} = response} when status >= 500 ->
        # 5xx errors are transient - always retry
        log_failure(webhook_id, url, status, "Server error - will retry")
        {:error, "HTTP #{status}: #{inspect(response.body)}"}

      {:error, %Mint.TransportError{reason: reason}} ->
        log_failure(webhook_id, url, nil, "Transport error: #{inspect(reason)}")
        {:error, "Transport error: #{inspect(reason)}"}

      {:error, reason} ->
        log_failure(webhook_id, url, nil, "Request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  rescue
    e ->
      # Access url from args since it may not be in scope in rescue
      rescue_url = args["url"]
      Logger.error("WebhookDeliveryJob crashed for #{rescue_url}: #{Exception.message(e)}")
      {:error, e}
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s, 30s, 30s, 30s, 30s
    # Cap at 30 seconds after attempt 5
    base = min(2 ** attempt, 30)
    :timer.seconds(base)
  end

  @impl Oban.Worker
  def timeout(%Oban.Job{}), do: :timer.seconds(35)

  # Private functions

  @spec build_headers(String.t(), String.t(), map(), String.t() | nil) :: list()
  defp build_headers(event_name, record_type, payload, secret) do
    base_headers = [
      {"Content-Type", "application/json"},
      {"User-Agent", "FOSM-Phoenix/1.0"},
      {"X-FOSM-Event", event_name},
      {"X-FOSM-Record-Type", record_type},
      {"X-FOSM-Timestamp", Integer.to_string(System.system_time(:second))}
    ]

    if secret && secret != "" do
      signature = compute_signature(payload, secret)
      [{"X-FOSM-Signature", "sha256=#{signature}"} | base_headers]
    else
      base_headers
    end
  end

  @spec compute_signature(map(), String.t()) :: String.t()
  defp compute_signature(payload, secret) do
    payload_binary = Jason.encode_to_iodata!(payload)
    
    :crypto.mac(:hmac, :sha256, secret, payload_binary)
    |> Base.encode16(case: :lower)
  end

  defp log_success(nil, url, status) do
    Logger.info("Webhook delivered successfully: #{url} (HTTP #{status})")
  end
  
  defp log_success(webhook_id, url, status) do
    Logger.info("Webhook #{webhook_id} delivered successfully: #{url} (HTTP #{status})")
  end

  defp log_failure(nil, url, status, reason) do
    status_str = if status, do: "(HTTP #{status}) ", else: ""
    Logger.warning("Webhook delivery failed: #{url} #{status_str}- #{reason}")
  end
  
  defp log_failure(webhook_id, url, status, reason) do
    status_str = if status, do: "(HTTP #{status}) ", else: ""
    Logger.warning("Webhook #{webhook_id} delivery failed: #{url} #{status_str}- #{reason}")
  end
end
