defmodule <%= @module %> do
  @moduledoc """
  LiveView for listing <%= @plural %>.
  """

  use <%= @web_module %>, :live_view

  alias <%= @schema_module %>
  alias <%= @app_module %>.Repo

  import FosmWeb.CoreComponents
  import FosmWeb.Gettext

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      page_title: "<%= @plural |> Macro.camelize() %>",
      <%= @plural %>: list_<%= @plural %>(),
      selected_state: nil
    )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    <%= @resource_path %> = get_<%= @resource_path %>!(id)

    socket
    |> assign(:page_title, "Edit <%= @resource_name %>")
    |> assign(:<%= @resource_path %>, <%= @resource_path %>)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New <%= @resource_name %>")
    |> assign(:<%= @resource_path %>, %<%= @schema_module %>{state: "<%= Enum.find(@states, &(&1.type == :initial))[:name] %>"})
  end

  defp apply_action(socket, :index, params) do
    state_filter = params["state"]
    <%= @plural %> = if state_filter, do: list_<%= @plural %>(state: state_filter), else: list_<%= @plural %>()

    socket
    |> assign(:page_title, "<%= @plural |> Macro.camelize() %>")
    |> assign(:<%= @plural %>, <%= @plural %>)
    |> assign(:selected_state, state_filter)
    |> assign(:<%= @resource_path %>, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    <%= @resource_path %> = get_<%= @resource_path %>!(id)
    {:ok, _} = Repo.delete(<%= @resource_path %>)

    {:noreply, stream_delete(socket, :<%= @plural %>, <%= @resource_path %>)}
  end

  def handle_event("filter_state", %{"state" => state}, socket) do
    {:noreply, push_patch(socket, to: ~p"/<%= @plural %>?state=#{state}")}
  end

  def handle_event("clear_filter", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/<%= @plural %>")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex justify-between items-center">
        <h1 class="text-2xl font-bold"><%= @plural |> Macro.camelize() %></h1>
        <.link patch={~p"/<%= @plural %>/new"} class="btn-primary">
          New <%= @resource_name %>
        </.link>
      </div>

      <%!-- State Filter --%>
      <div class="flex gap-2 items-center">
        <span class="text-sm text-gray-600">Filter by state:</span>
        <%= for state <- @states do %>
          <button
            phx-click={if @selected_state == "#{state.name}", do: "clear_filter", else: "filter_state"}
            phx-value-state={state.name}
            class={[
              "px-3 py-1 rounded text-sm",
              @selected_state == "#{state.name}" && "bg-blue-500 text-white",
              @selected_state != "#{state.name}" && "bg-gray-200 hover:bg-gray-300"
            ]}
          >
            <%= state.name %>
          </button>
        <% end %>
        <%= if @selected_state do %>
          <button phx-click="clear_filter" class="text-sm text-blue-600 hover:underline">
            Clear filter
          </button>
        <% end %>
      </div>

      <%!-- Table --%>
      <.table id="<%= @plural %>" rows={@<%= @plural %>} row_click={fn <%= @resource_path %> -> JS.navigate(~p"/<%= @plural %>/#{<%= @resource_path %>.id}") end}>
        <:col :let={<%= @resource_path %>} label="ID"><%= <%= @resource_path %>.id %></:col>
<%= for {name, _type} <- @fields do %>        <:col :let={<%= @resource_path %>} label="<%= name |> to_string() |> Macro.camelize() %>"><%= <%= @resource_path %>.<%= name %> %></:col>
<% end %>
        <:col :let={<%= @resource_path %>} label="State">
          <.badge color={state_color(<%= @resource_path %>.state)}>
            <%= <%= @resource_path %>.state %>
          </.badge>
        </:col>
        <:col :let={<%= @resource_path %>} label="Created"><%= <%= @resource_path %>.inserted_at %></:col>

        <:action :let={<%= @resource_path %>}>
          <div class="sr-only">
            <.link navigate={~p"/<%= @plural %>/#{<%= @resource_path %>.id}">Show</.link>
          </div>
          <.link patch={~p"/<%= @plural %>/#{<%= @resource_path %>.id}/edit"}>Edit</.link>
        </:action>
        <:action :let={<%= @resource_path %>}>
          <.link phx-click={JS.push("delete", value: %{id: <%= @resource_path %>.id}) |> hide("##{@plural}-#{<%= @resource_path %>.id}")} data-confirm="Are you sure?">
            Delete
          </.link>
        </:action>
      </.table>
    </div>

    <%!-- Modal for new/edit --%>
    <.modal :if={@live_action in [:new, :edit]} id="<%= @resource_path %>-modal" show on_cancel={JS.patch(~p"/<%= @plural %>")}>
      <.live_component
        module={<%= @live_form_module %>}
        id={@<%= @resource_path %>.id || :new}
        title={@page_title}
        action={@live_action}
        <%= @resource_path %>={@<%= @resource_path %>}
        patch={~p"/<%= @plural %>"}
      />
    </.modal>
    """
  end

  defp list_<%= @plural %>(opts \\ []) do
    query = <%= @schema_module %>

    query = if opts[:state] do
      from(q in query, where: q.state == ^opts[:state])
    else
      query
    end

    query
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  defp get_<%= @resource_path %>!(id), do: Repo.get!(<%= @schema_module %>, id)

  defp state_color(state) do
    case state do
<%= for state <- @states do %>      "<%= state.name %>" -> <%= if state.type == :initial, do: ":info", else: if(state.type == :terminal, do: ":success", else: ":warning") %>
<% end %>      _ -> :gray
    end
  end
end
