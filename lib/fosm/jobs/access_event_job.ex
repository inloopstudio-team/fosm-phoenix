defmodule Fosm.Jobs.AccessEventJob do
  @moduledoc """
  Oban worker for async access event logging.

  Queues access control events (grants, revokes, auto-grants) for async
  insertion to avoid slowing down the main request flow.

  ## Usage

      Fosm.Jobs.AccessEventJob.new(%{
        action: "grant",
        user_type: "User",
        user_id: "42",
        resource_type: "Fosm.Invoice",
        resource_id: "123",
        role_name: "owner",
        performed_by_type: "User",
        performed_by_id: "1"
      })
      |> Oban.insert()

  ## Queue Configuration

  Configure in your Oban config:

      config :my_app, Oban,
        queues: [default: 10, fosm_logs: 5]
  """

  use Oban.Worker,
    queue: :fosm_logs,
    max_attempts: 3,
    unique: [period: 60]  # Dedupe within 60 seconds

  alias Fosm.AccessEvent

  @impl Oban.Worker
  def perform(%Oban.Job{args: event_data}) do
    # Create the access event
    AccessEvent.create!(event_data)

    :ok
  end

  @doc """
  Creates a job for an access event with standard fields.

  ## Examples

      Fosm.Jobs.AccessEventJob.from_grant(user, invoice, :owner, granted_by: admin)
  """
  def from_grant(user, resource, role_name, opts \\ []) do
    granted_by = opts[:granted_by] || :system
    {pb_type, pb_id} = extract_actor(granted_by)
    {u_type, u_id} = extract_actor(user)

    new(%{
      action: "grant",
      user_type: u_type,
      user_id: u_id,
      user_label: user_label(user),
      resource_type: resource.__struct__.__schema__(:source),
      resource_id: to_string(resource.id),
      role_name: to_string(role_name),
      performed_by_type: pb_type,
      performed_by_id: pb_id,
      metadata: opts[:metadata] || %{}
    })
  end

  @doc """
  Creates a job for a revocation event.
  """
  def from_revoke(user, resource, role_name, opts \\ []) do
    revoked_by = opts[:revoked_by] || :system
    {pb_type, pb_id} = extract_actor(revoked_by)
    {u_type, u_id} = extract_actor(user)

    new(%{
      action: "revoke",
      user_type: u_type,
      user_id: u_id,
      user_label: user_label(user),
      resource_type: resource.__struct__.__schema__(:source),
      resource_id: to_string(resource.id),
      role_name: to_string(role_name),
      performed_by_type: pb_type,
      performed_by_id: pb_id,
      metadata: opts[:metadata] || %{}
    })
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp extract_actor(actor) when is_struct(actor) do
    {to_string(actor.__struct__), to_string(actor.id)}
  end

  defp extract_actor(actor) when is_atom(actor) do
    {to_string(actor), "system"}
  end

  defp extract_actor(_actor) do
    {"Unknown", "0"}
  end

  defp user_label(user) when is_struct(user) do
    parts = []
    parts = if user[:email], do: [user.email | parts], else: parts
    parts = if user[:name], do: [user.name | parts], else: parts
    parts = if user[:username], do: [user.username | parts], else: parts

    case parts do
      [] -> "#{user.__struct__}:#{user.id}"
      _ -> Enum.join(parts, " — ")
    end
  end

  defp user_label(user), do: to_string(user)
end
