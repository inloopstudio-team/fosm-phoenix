defmodule FosmWeb.Admin.WebhooksLive do
  @moduledoc """
  Webhook management LiveView.
  
  Features:
  - List all webhook subscriptions
  - Create new webhooks
  - Edit existing webhooks
  - Test webhook delivery
  - Toggle active/inactive
  """

  use FosmWeb, :live_view
  import FosmWeb.Admin.Components
  alias Fosm.{Repo, WebhookSubscription}
  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Webhook Management")
      |> assign(:current_path, "/fosm/admin/webhooks")
      |> assign(:available_models, available_models())
    
    {:ok, socket, layout: {FosmWeb.Admin.Layout, :admin_layout}}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    live_action = socket.assigns.live_action || :index
    page = String.to_integer(params["page"] || "1")
    
    webhooks = fetch_webhooks(page)
    
    socket =
      socket
      |> assign(:page, page)
      |> assign(:webhooks, webhooks)
      |> assign(:form_changeset, nil)
    
    socket = 
      case live_action do
        :new -> 
          changeset = WebhookSubscription.changeset(%WebhookSubscription{}, %{})
          assign(socket, :form_changeset, changeset)
          
        :edit ->
          webhook = Repo.get(WebhookSubscription, params["id"])
          if webhook do
            changeset = WebhookSubscription.changeset(webhook, %{})
            assign(socket, :form_changeset, changeset, :editing_webhook, webhook)
          else
            push_navigate(socket, to: ~p"/fosm/admin/webhooks")
          end
          
        _ ->
          socket
      end
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    webhook = Repo.get(WebhookSubscription, id)
    
    if webhook do
      {:ok, updated} = 
        webhook
        |> WebhookSubscription.changeset(%{active: !webhook.active})
        |> Repo.update()
      
      webhooks = fetch_webhooks(socket.assigns.page)
      
      {:noreply,
        socket
        |> put_flash(:info, "Webhook #{if updated.active, do: "enabled", else: "disabled"}")
        |> assign(:webhooks, webhooks)}
    else
      {:noreply, put_flash(socket, :error, "Webhook not found")}
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    webhook = Repo.get(WebhookSubscription, id)
    
    if webhook do
      Repo.delete!(webhook)
      
      webhooks = fetch_webhooks(socket.assigns.page)
      
      {:noreply,
        socket
        |> put_flash(:info, "Webhook deleted")
        |> assign(:webhooks, webhooks)}
    else
      {:noreply, put_flash(socket, :error, "Webhook not found")}
    end
  end

  @impl true
  def handle_event("save", %{"webhook_subscription" => params}, socket) do
    changeset = 
      case socket.assigns.live_action do
        :new ->
          %WebhookSubscription{}
          |> WebhookSubscription.changeset(params)
          
        :edit ->
          socket.assigns.editing_webhook
          |> WebhookSubscription.changeset(params)
      end
    
    case Repo.insert_or_update(changeset) do
      {:ok, _webhook} ->
        {:noreply,
          socket
          |> put_flash(:info, "Webhook saved successfully")
          |> push_navigate(to: ~p"/fosm/admin/webhooks")}
          
      {:error, changeset} ->
        {:noreply, assign(socket, :form_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("validate", %{"webhook_subscription" => params}, socket) do
    changeset =
      case socket.assigns.live_action do
        :new ->
          %WebhookSubscription{}
          |> WebhookSubscription.changeset(params)
          |> Map.put(:action, :validate)
          
        :edit ->
          socket.assigns.editing_webhook
          |> WebhookSubscription.changeset(params)
          |> Map.put(:action, :validate)
      end
    
    {:noreply, assign(socket, :form_changeset, changeset)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-gray-900">Webhook Subscriptions</h1>
        <.link navigate={~p"/fosm/admin/webhooks/new"}>
          <.button>New Webhook</.button>
        </.link>
      </div>

      <%= if @live_action in [:new, :edit] do %>
        <.card>
          <h2 class="text-lg font-semibold mb-4">
            <%= if @live_action == :new, do: "Create Webhook", else: "Edit Webhook" %>
          </h2>
          
          <.form
            :let={f}
            for={@form_changeset}
            phx-submit="save"
            phx-change="validate"
            class="space-y-4"
          >
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Model</label>
              <select name="webhook_subscription[model_class_name]" class="w-full rounded border-gray-300 text-sm">
                <option value="">Select a model...</option>
                <%= for {slug, module} <- @available_models do %>
                  <option 
                    value={module.__schema__(:source)}
                    selected={input_value(f, :model_class_name) == module.__schema__(:source)}
                  >
                    <%= module.__schema__(:source) %>
                  </option>
                <% end %>
              </select>
              <.error_tag field={:model_class_name} form={f} />
            </div>
            
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Event Name (optional)</label>
              <input
                type="text"
                name="webhook_subscription[event_name]"
                value={input_value(f, :event_name)}
                placeholder="Leave empty for all events"
                class="w-full rounded border-gray-300 text-sm"
              />
              <p class="text-xs text-gray-500 mt-1">Leave blank to subscribe to all events on this model</p>
              <.error_tag field={:event_name} form={f} />
            </div>
            
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">URL</label>
              <input
                type="url"
                name="webhook_subscription[url]"
                value={input_value(f, :url)}
                placeholder="https://example.com/webhook"
                class="w-full rounded border-gray-300 text-sm"
              />
              <.error_tag field={:url} form={f} />
            </div>
            
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Secret Token (optional)</label>
              <input
                type="password"
                name="webhook_subscription[secret_token]"
                value={input_value(f, :secret_token)}
                placeholder="For HMAC signature verification"
                class="w-full rounded border-gray-300 text-sm"
              />
              <p class="text-xs text-gray-500 mt-1">Used to verify webhook authenticity</p>
            </div>
            
            <div class="flex items-center">
              <input
                type="checkbox"
                name="webhook_subscription[active]"
                checked={input_value(f, :active) != nil and input_value(f, :active) != false}
                value="true"
                class="rounded border-gray-300"
              />
              <label class="ml-2 text-sm text-gray-700">Active</label>
            </div>
            
            <div class="flex gap-2 pt-4">
              <.button type="submit" variant="primary">Save</.button>
              <.link navigate={~p"/fosm/admin/webhooks"}>
                <.button type="button" variant="secondary">Cancel</.button>
              </.link>
            </div>
          </.form>
        </.card>
      <% end %>

      <!-- Webhooks List -->
      <.card>
        <%= if @webhooks.entries == [] do %>
          <.alert type="info">
            <p>No webhook subscriptions configured.</p>
            <p class="text-sm mt-1">
              <.link navigate={~p"/fosm/admin/webhooks/new"} class="text-blue-600 hover:underline">
                Create your first webhook
              </.link>
            </p>
          </.alert>
        <% else %>
          <.table>
            <.table_header>
              <.table_header_cell>Model</.table_header_cell>
              <.table_header_cell>Event</.table_header_cell>
              <.table_header_cell>URL</.table_header_cell>
              <.table_header_cell>Status</.table_header_cell>
              <.table_header_cell>Created</.table_header_cell>
              <.table_header_cell>Actions</.table_header_cell>
            </.table_header>
            <.table_body>
              <%= for webhook <- @webhooks.entries do %>
                <.table_row>
                  <.table_cell>
                    <span class="text-sm font-medium"><%= webhook.model_class_name %></span>
                  </.table_cell>
                  <.table_cell>
                    <%= if webhook.event_name do %>
                      <.badge variant="info"><%= webhook.event_name %></.badge>
                    <% else %>
                      <span class="text-xs text-gray-500">All events</span>
                    <% end %>
                  </.table_cell>
                  <.table_cell>
                    <span class="text-xs font-mono text-gray-600 truncate max-w-xs block">
                      <%= webhook.url %>
                    </span>
                  </.table_cell>
                  <.table_cell>
                    <button
                      phx-click="toggle"
                      phx-value-id={webhook.id}
                      class={[
                        "px-2 py-1 rounded text-xs font-medium",
                        if(webhook.active, 
                          do: "bg-green-100 text-green-800", 
                          else: "bg-gray-100 text-gray-600"
                        )
                      ]}
                    >
                      <%= if webhook.active, do: "Active", else: "Inactive" %>
                    </button>
                  </.table_cell>
                  <.table_cell>
                    <span class="text-xs text-gray-500"><%= format_relative(webhook.inserted_at) %></span>
                  </.table_cell>
                  <.table_cell>
                    <div class="flex items-center gap-2">
                      <.link navigate={~p"/fosm/admin/webhooks/#{webhook.id}/edit"} class="text-sm text-blue-600 hover:underline">
                        Edit
                      </.link>
                      <button
                        phx-click="delete"
                        phx-value-id={webhook.id}
                        data-confirm="Are you sure you want to delete this webhook?"
                        class="text-sm text-red-600 hover:text-red-800"
                      >
                        Delete
                      </button>
                    </div>
                  </.table_cell>
                </.table_row>
              <% end %>
            </.table_body>
          </.table>

          <.pagination
            page={@webhooks}
            path={~p"/fosm/admin/webhooks"}
            params={%{}}
          />
        <% end %>
      </.card>
    </div>
    """
  end

  # Private functions

  defp available_models do
    Fosm.Registry.all()
  end

  defp fetch_webhooks(page) do
    from(w in WebhookSubscription)
    |> order_by([w], desc: w.inserted_at)
    |> Repo.paginate(page: page, page_size: 25)
  end

  defp input_value(form, field) do
    form.params[Atom.to_string(field)] ||
      case form.data do
        %{^field => value} -> value
        _ -> nil
      end
  end

  defp error_tag(assigns) do
    ~H"""
    <%= if @form.errors[@field] do %>
      <p class="mt-1 text-xs text-red-600">
        <%= elem(@form.errors[@field], 0) %>
      </p>
    <% end %>
    """
  end

  defp format_relative(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%Y-%m-%d")
    end
  end
end
