defmodule Kunai.Web do
  @moduledoc false
  # The scope of a request or a LiveView, where the app's own pipeline or
  # hooks put it: the mount's `:scope_assign` (`:current_scope`).

  def scope(%Plug.Conn{assigns: assigns}), do: fetch(assigns)
  def scope(%Phoenix.LiveView.Socket{assigns: assigns}), do: fetch(assigns)

  defp fetch(%{mount: mount} = assigns) do
    key = mount.options[:scope_assign] || :current_scope

    case Map.fetch(assigns, key) do
      {:ok, scope} when not is_nil(scope) -> {:ok, scope}
      _missing -> :error
    end
  end

  defp fetch(_assigns), do: :error

  # A changeset's error as a sentence: its message with its values.
  def error_message({message, values}) do
    Enum.reduce(values, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
