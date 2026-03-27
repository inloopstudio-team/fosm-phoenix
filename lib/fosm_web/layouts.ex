defmodule FosmWeb.Layouts do
  @moduledoc """
  Layouts for FOSM Web.
  """
  use FosmWeb, :html

  embed_templates "layouts/*"

  def app(assigns) do
    ~H"""
    <main class="container mx-auto px-4 py-6">
      <%= @inner_content %>
    </main>
    """
  end
end
