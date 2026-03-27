defmodule FosmWeb.Live.InvoiceLive.FormComponent do
  @moduledoc """
  Form component for creating and editing Invoice records.
  """

  use FosmWeb, :live_component

  alias Fosm.Invoice
  alias Fosm.Repo


  @impl true
  def update(%{resource: resource, action: action} = assigns, socket) do
    changeset = Invoice.changeset(resource)

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
      |> Invoice.changeset(resource_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"resource" => resource_params}, socket) do
    save_resource(socket, socket.assigns.action, resource_params)
  end

  defp save_resource(socket, :edit, resource_params) do
    resource = socket.assigns.resource

    case resource
         |> Invoice.changeset(resource_params)
         |> Repo.update() do
      {:ok, resource} ->
        notify_parent({:saved, resource})
        {:noreply,
         socket
         |> put_flash(:info, "Invoice updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_resource(socket, :new, resource_params) do
    # Ensure initial state is set
    resource_params = Map.put_new(resource_params, "state", "draft")

    case %Invoice{}
         |> Invoice.changeset(resource_params)
         |> Repo.insert() do
      {:ok, resource} ->
        notify_parent({:saved, resource})
        {:noreply,
         socket
         |> put_flash(:info, "Invoice created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="mb-4">
        <h2 class="text-xl font-bold">
          <%= if @action == :new, do: "New Invoice", else: "Edit Invoice" %>
        </h2>
        <p class="text-sm text-gray-600">
          <%= if @action == :new do %>
            Create a new Invoice in draft state.
          <% end %>
        </p>
      </div>

      <.simple_form
        for={@form}
        id="invoice-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input
          field={@form[:number]}
          type="text"
          label="Number"
        />
        <.input
          field={@form[:amount]}
          type="number"
          label="Amount"
        />
        <.input
          field={@form[:due_date]}
          type="date"
          label="Due Date"
        />

        <div class="flex items-center gap-2 py-2">
          <span class="text-sm font-medium text-gray-700">State:</span>
          <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", state_color((@resource && @resource.state) || "draft")]}>
            <%= (@resource && @resource.state) || "draft" %>
          </span>
          <span class="text-xs text-gray-500">
            <%= if @action == :new, do: "(initial state)", else: "" %>
          </span>
        </div>

        <:actions>
          <.btn phx-disable-with="Saving...">Save Invoice</.btn>
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
      "draft" -> "bg-blue-100 text-blue-800"
      "sent" -> "bg-yellow-100 text-yellow-800"
      "paid" -> "bg-green-100 text-green-800"
      "void" -> "bg-gray-100 text-gray-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end
end
