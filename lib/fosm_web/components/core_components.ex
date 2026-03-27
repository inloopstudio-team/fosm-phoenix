defmodule FosmWeb.CoreComponents do
  @moduledoc """
  Provides core UI components used across the FOSM Admin interface.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # Simple link component
  attr :navigate, :string, required: true
  slot :inner_block, required: true

  def link(assigns) do
    ~H"""
    <a href={@navigate} data-phx-link="redirect" data-phx-link-state="push">
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  # Simple form component for LiveView
  attr :for, :any, required: true
  attr :phx_submit, :string, default: nil
  attr :phx_change, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def form(assigns) do
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

  # Core icon component
  attr :name, :string, required: true
  attr :class, :string, default: ""

  def icon(assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d={icon_path(@name)} />
    </svg>
    """
  end

  defp icon_path("home"), do: "M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"
  defp icon_path(_), do: "M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
end
