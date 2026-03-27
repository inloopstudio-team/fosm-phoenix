defmodule <%= @module %> do
  @moduledoc """
  Form component for creating and editing <%= @resource_name %> records.
  """

  use <%= @web_module %>, :live_component

  alias <%= @schema_module %>
  alias <%= @app_module %>.Repo

  import FosmWeb.CoreComponents

  @impl true
  def update(%{resource: resource, action: action} = assigns, socket) do
    changeset = <%= @schema_module %>.changeset(resource)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"resource" => resource_params}, socket) do
    changeset =
      socket.assigns.resource
      |> <%= @schema_module %>.changeset(resource_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"resource" => resource_params}, socket) do
    save_resource(socket, socket.assigns.action, resource_params)
  end

  defp save_resource(socket, :edit, resource_params) do
    resource = socket.assigns.resource

    case resource
         |> <%= @schema_module %>.changeset(resource_params)
         |> Repo.update() do
      {:ok, resource} ->
        notify_parent({:saved, resource})
        {:noreply,
         socket
         |> put_flash(:info, "<%= @resource_name %> updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_resource(socket, :new, resource_params) do
    # Ensure initial state is set
    resource_params = Map.put_new(resource_params, "state", "<%= Enum.find(@states, &(&1.type == :initial))[:name] %>")

    case %<%= @schema_module %>{}
         |> <%= @schema_module %>.changeset(resource_params)
         |> Repo.insert() do
      {:ok, resource} ->
        notify_parent({:saved, resource})
        {:noreply,
         socket
         |> put_flash(:info, "<%= @resource_name %> created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>
          <%= if @action == :new do %>
            Create a new <%= @resource_name %> in <%= Enum.find(@states, &(&1.type == :initial))[:name] %> state.
          <% else %>
            Edit <%= @resource_name %> attributes (state changes require events).
          <% end %>
        </:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="<%= @resource_path %>-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
<%= for {name, type} <- @fields do %><% type_str = case type do
  :string -> "text"
  :text -> "textarea"
  :integer -> "number"
  :float -> "number"
  :decimal -> "number"
  :boolean -> "checkbox"
  :date -> "date"
  :time -> "time"
  :datetime -> "datetime-local"
  :naive_datetime -> "datetime-local"
  :utc_datetime -> "datetime-local"
  :uuid -> "text"
  _ -> "text"
end %>        <.input
          field={@form[<%= inspect(name) %>]}
          type="<%= type_str %>"
          label="<%= name |> to_string() |> Macro.camelize() %>"
        />
<% end %>
        <%!-- State is displayed but not editable directly --%>
        <div class="flex items-center gap-2 py-2">
          <span class="text-sm font-medium text-gray-700">State:</span>
          <.badge color={state_color((@resource && @resource.state) || "draft")}>
            <%= (@resource && @resource.state) || "draft" %>
          </.badge>
          <span class="text-xs text-gray-500">
            <%= if @action == :new do %>
              (initial state)
            <% else %>
              (use events to change)
            <% end %>
          </span>
        </div>

        <:actions>
          <.button phx-disable-with="Saving...">Save <%= @resource_name %></.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp input_type(type) do
    case type do
      :string -> "text"
      :text -> "textarea"
      :integer -> "number"
      :float -> "number"
      :decimal -> "number"
      :boolean -> "checkbox"
      :date -> "date"
      :time -> "time"
      :datetime -> "datetime-local"
      :naive_datetime -> "datetime-local"
      :utc_datetime -> "datetime-local"
      :uuid -> "text"
      _ -> "text"
    end
  end

  defp state_color(state) do
    case state do
<%= for state <- @states do %>      "<%= state.name %>" -> <%= if state.type == :initial, do: ":info", else: if(state.type == :terminal, do: ":success", else: ":warning") %>
<% end %>      _ -> :gray
    end
  end
end
