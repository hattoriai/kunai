defmodule Kunai.Text do
  @moduledoc """
  Every word of Kunai's pages, through one function, so an app shows them
  in its own language and its own voice.

      config :kunai, gettext: MyAppWeb.Gettext

  looks each one up in the app's Gettext, in the `"kunai"` domain
  (`priv/gettext/<locale>/LC_MESSAGES/kunai.po`); without it, the English
  is shown. A message is its English, with `%{name}` for its values, as
  Gettext's are.

  Kunai's messages are in `priv/gettext/kunai.pot`: copy it into the app's
  `priv/gettext` and run `mix gettext.merge priv/gettext` for a `kunai.po`
  in each of its languages. A language is a process's, as Gettext's always
  is: the pages speak the one the app's `on_mount` hooks set, the hooks
  the mount runs (`kunai "/webhooks", on_mount: [...]`).
  """

  # Gettext is the app's: called only when it is configured.
  @compile {:no_warn_undefined, Gettext}

  @doc "A message, with its values."
  @spec t(String.t(), map() | keyword()) :: String.t()
  def t(message, bindings \\ %{}) do
    bindings = Map.new(bindings)

    case Application.get_env(:kunai, :gettext) do
      nil -> interpolate(message, bindings)
      backend -> Gettext.dgettext(backend, "kunai", message, bindings)
    end
  end

  @doc "A message that has a plural: the singular when `count` is 1."
  @spec tn(String.t(), String.t(), integer(), map() | keyword()) :: String.t()
  def tn(singular, plural, count, bindings \\ %{}) do
    bindings = bindings |> Map.new() |> Map.put(:count, count)

    case Application.get_env(:kunai, :gettext) do
      nil -> interpolate(if(count == 1, do: singular, else: plural), bindings)
      backend -> Gettext.dngettext(backend, "kunai", singular, plural, count, bindings)
    end
  end

  defp interpolate(message, bindings) do
    Enum.reduce(bindings, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
