defmodule <%= @module %> do
  @moduledoc """
  Form component for creating and editing <%= @resource_name %> records.
  """

  use <%= @web_module %>, :live_component

  alias <%= @schema_module %>
  alias <%= @app_module %>.Repo

  import FosmWeb.CoreComponents

  @impl true
  def update(%{<%= @resource_path %>: <%= @resource_path %>, action: action} = assigns, socket) do
    changeset = <%= @schema_module %>.changeset(<%= @resource_path %>)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"<%= @resource_path %>" => <%= @resource_path %>_params}, socket) do
    changeset =
      socket.assigns.<%= @resource_path %>
      |> <%= @schema_module %>.changeset(<%= @resource_path %>_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"<%= @resource_path %>" => <%= @resource_path %>_params}, socket) do
    save_<%= @resource_path %>(socket, socket.assigns.action, <%= @resource_path %>_params)
  end

  defp save_<%= @resource_path %>(socket, :edit, <%= @resource_path %>_params) do
    <%= @resource_path %> = socket.assigns.<%= @resource_path %>

    case <%= @resource_path %>
         |> <%= @schema_module %>.changeset(<%= @resource_path %>_params)
         |> Repo.update() do
      {:ok, <%= @resource_path %>} ->
        notify_parent({:saved, <%= @resource_path %>})
        {:noreply,
         socket
         |> put_flash(:info, "<%= @resource_name %> updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_<%= @resource_path %>(socket, :new, <%= @resource_path %>_params) do
    # Ensure initial state is set
    <%= @resource_path %>_params = Map.put_new(<%= @resource_path %>_params, "state", "<%= Enum.find(@states, &(&1.type == :initial))[:name] %>")

    case %<%= @schema_module %>{}
         |> <%= @schema_module %>.changeset(<%= @resource_path %>_params)
         |> Repo.insert() do
      {:ok, <%= @resource_path %>} ->
        notify_parent({:saved, <%= @resource_path %>})
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
<%= for {name, type} <- @fields do %>        <.input
          field={@form[<%= inspect(name) %>]}
          type="<%= input_type(type) %>"
          label="<%= name |> to_string() |> Macro.camelize() %>"
        />
<% end %>
        <%!-- State is displayed but not editable directly --%>
        <div class="flex items-center gap-2 py-2">
          <span class="text-sm font-medium text-gray-700">State:</span>
          <.badge color={state_color(@<%= @resource_path %>.state || "<%= Enum.find(@states, &(&1.type == :initial))[:name] %>")}>
            <%= @<%= @resource_path %>.state || "<%= Enum.find(@states, &(&1.type == :initial))[:name] %>" %>
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
