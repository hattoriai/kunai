defmodule Kunai.Live.Scope do
  @moduledoc false
  # The scope of the pages, where the app's hooks put it.

  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    case Kunai.Web.scope(socket) do
      {:ok, scope} ->
        {:cont, assign(socket, :kunai_scope, scope)}

      :error ->
        key = socket.assigns.mount.options[:scope_assign] || :current_scope

        raise ArgumentError,
              "Kunai's pages found no @#{key}: mount them with the app's hook that assigns it, " <>
                "kunai \"/webhooks\", on_mount: [{MyAppWeb.UserAuth, :require_authenticated}]"
    end
  end
end
