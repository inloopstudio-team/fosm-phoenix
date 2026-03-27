if Code.ensure_loaded?(Phoenix.Component) do
  defmodule FosmWeb.Layouts do
    @moduledoc """
    Layouts for FOSM Web.
    """
    use Phoenix.Component

    def root(assigns) do
      ~H"""
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
          <title>FOSM Admin</title>
          <script src="https://cdn.tailwindcss.com"></script>
        </head>
        <body class="bg-gray-100 antialiased">
          <%= render_slot(@inner_content) %>
        </body>
      </html>
      """
    end

    def app(assigns) do
      ~H"""
      <main class="container mx-auto px-4 py-6">
        <%= render_slot(@inner_content) %>
      </main>
      """
    end
  end
end
