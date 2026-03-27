if Code.ensure_loaded?(Phoenix.Component) do
  defmodule FosmWeb.CoreComponents do
    @moduledoc """
    Provides core UI components used across the FOSM Admin interface.
    """

    use Phoenix.Component

    alias Phoenix.LiveView.JS

    # Simple form component for LiveView
    attr :for, :any, required: true
    attr :phx_submit, :string, default: nil
    attr :phx_change, :string, default: nil
    attr :class, :string, default: nil
    slot :inner_block, required: true

    def simple_form(assigns) do
      ~H"""
      <.form
        :let={f}
        for={@for}
        phx-submit={@phx_submit}
        phx-change={@phx_change}
        class={@class}
      >
        <%= render_slot(@inner_block, f) %>
      </.form>
      """
    end

    # Simple input component
    attr :field, :any, required: true
    attr :type, :string, default: "text"
    attr :label, :string, default: nil
    attr :class, :string, default: nil

    def input(assigns) do
      ~H"""
      <div class={["mb-4", @class]}>
        <%= if @label do %>
          <label class="block text-sm font-medium text-gray-700 mb-1"><%= @label %></label>
        <% end %>
        <input
          type={@type}
          name={@field.name}
          value={@field.value}
          class="block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
        />
      </div>
      """
    end

    # Simple button component
    attr :type, :string, default: "button"
    attr :phx_disable_with, :string, default: nil
    attr :class, :string, default: nil
    slot :inner_block, required: true

    def btn(assigns) do
      ~H"""
      <button
        type={@type}
        class={["inline-flex justify-center rounded-md border border-transparent bg-blue-600 py-2 px-4 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2", @class]}
      >
        <%= render_slot(@inner_block) %>
      </button>
      """
    end

  end
end
