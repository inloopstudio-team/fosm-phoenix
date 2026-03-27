defmodule Fosm.WebhookSubscription do
  @moduledoc """
  Webhook subscriptions for FOSM events.
  Supports system-wide, per-record-type, and per-record webhooks.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @delivery_modes [:sync, :async]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "fosm_webhook_subscriptions" do
    field(:url, :string)
    field(:events, {:array, :string}, default: [])
    field(:record_type, :string)
    field(:record_id, :string)
    field(:secret_token, :string)
    field(:active, :boolean, default: true)
    field(:delivery_mode, :string, default: "async")
    field(:retry_count, :integer, default: 0)
    field(:last_delivery_at, :utc_datetime)
    field(:last_delivery_status, :string)
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime)
  end

  @required_fields [:url]
  @optional_fields [
    :events,
    :record_type,
    :record_id,
    :secret_token,
    :active,
    :delivery_mode,
    :retry_count,
    :last_delivery_at,
    :last_delivery_status,
    :metadata
  ]

  @doc """
  Creates a changeset for a new webhook subscription.
  """
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:url, ~r/^https?:\/\/.+/, message: "must be a valid URL")
    |> validate_length(:url, max: 2000)
    |> validate_length(:record_type, max: 255)
    |> validate_length(:record_id, max: 255)
    |> validate_length(:secret_token, max: 500)
    |> validate_inclusion(:delivery_mode, ["sync", "async"])
    |> validate_events()
    |> unique_constraint([:url, :record_type, :record_id],
      name: :webhook_subscriptions_unique_idx,
      message: "Webhook already registered for this target"
    )
  end

  defp validate_events(changeset) do
    events = get_field(changeset, :events) || []

    if events == [] do
      # Empty events means subscribe to all - valid
      changeset
    else
      # Validate each event is a string
      if Enum.all?(events, &is_binary/1) do
        changeset
      else
        add_error(changeset, :events, "must be a list of strings")
      end
    end
  end

  @doc """
  Creates a new webhook subscription. Raises on error.
  """
  def create!(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Fosm.Repo.insert!()
  end

  @doc """
  Updates a webhook subscription.
  """
  def update!(subscription, attrs) do
    subscription
    |> changeset(attrs)
    |> Fosm.Repo.update!()
  end

  @doc """
  Deletes a webhook subscription.
  """
  def delete!(subscription) do
    Fosm.Repo.delete!(subscription)
  end

  # Query Scopes

  @doc """
  Scope: Only active subscriptions.
  """
  def active(query \\ __MODULE__) do
    where(query, [s], s.active == true)
  end

  @doc """
  Scope: Filter by event.
  Returns subscriptions that either:
  - Subscribe to all events (empty events array)
  - Explicitly include this event
  """
  def for_event(query \\ __MODULE__, event_name) do
    where(
      query,
      [s],
      fragment(
        "? = ANY(?) OR array_length(?, 1) IS NULL OR array_length(?, 1) = 0",
        ^to_string(event_name),
        s.events,
        s.events,
        s.events
      )
    )
  end

  @doc """
  Scope: Filter by record type.
  """
  def for_record_type(query \\ __MODULE__, record_type) do
    where(query, [s], s.record_type == ^record_type)
  end

  @doc """
  Scope: Filter by specific record.
  """
  def for_record(query \\ __MODULE__, record_type, record_id) do
    where(query, [s], s.record_type == ^record_type and s.record_id == ^to_string(record_id))
  end

  @doc """
  Scope: System-wide subscriptions (no record_type specified).
  """
  def system_wide(query \\ __MODULE__) do
    where(query, [s], is_nil(s.record_type))
  end

  @doc """
  Scope: Per-record-type subscriptions.
  """
  def per_type(query \\ __MODULE__) do
    where(query, [s], not is_nil(s.record_type) and is_nil(s.record_id))
  end

  @doc """
  Scope: Per-record subscriptions.
  """
  def per_record(query \\ __MODULE__) do
    where(query, [s], not is_nil(s.record_id))
  end

  @doc """
  Scope: Subscriptions needing retry.
  """
  def needs_retry(query \\ __MODULE__, max_retries \\ 10) do
    where(query, [s], s.retry_count < ^max_retries and not is_nil(s.last_delivery_status))
  end

  @doc """
  Get all subscriptions that should receive a specific event.
  Returns: system-wide + per-type + per-record subscriptions.
  """
  def matching_subscriptions(event_name, record_type, record_id) do
    system_wide =
      __MODULE__
      |> active()
      |> system_wide()
      |> for_event(event_name)
      |> Fosm.Repo.all()

    per_type =
      __MODULE__
      |> active()
      |> for_record_type(record_type)
      |> per_type()
      |> for_event(event_name)
      |> Fosm.Repo.all()

    per_record =
      __MODULE__
      |> active()
      |> for_record(record_type, record_id)
      |> for_event(event_name)
      |> Fosm.Repo.all()

    Enum.uniq_by(system_wide ++ per_type ++ per_record, & &1.id)
  end

  @doc """
  Update delivery status after attempting delivery.
  """
  def record_delivery!(subscription, status) do
    subscription
    |> changeset(%{
      last_delivery_at: DateTime.utc_now(),
      last_delivery_status: status,
      retry_count: subscription.retry_count + if(status == "success", do: 0, else: 1)
    })
    |> Fosm.Repo.update!()
  end

  @doc """
  Reset retry count after successful delivery.
  """
  def reset_retries!(subscription) do
    subscription
    |> changeset(%{retry_count: 0, last_delivery_status: "success"})
    |> Fosm.Repo.update!()
  end

  @doc """
  Generate signature for webhook payload.
  """
  def generate_signature(payload, secret_token) when is_map(payload) do
    json = Jason.encode!(payload)
    generate_signature(json, secret_token)
  end

  def generate_signature(payload, secret_token) when is_binary(payload) do
    :crypto.mac(:hmac, :sha256, secret_token, payload)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Verify webhook signature.
  """
  def verify_signature?(payload, secret_token, signature) do
    expected = generate_signature(payload, secret_token)
    Plug.Crypto.secure_compare(expected, signature)
  end
end
