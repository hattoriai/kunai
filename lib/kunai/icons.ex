defmodule Kunai.Icons do
  @moduledoc """
  The icons of Kunai's pages: inline SVG, 16 pixels on a 24 grid, drawn
  with `currentColor`, so they take the colour of their text. No icon
  font, no sprite, nothing for the app to install.
  """

  use Phoenix.Component

  @paths %{
    "plus" => ~s(<path d="M12 5v14M5 12h14"/>),
    "copy" =>
      ~s(<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>),
    "check" => ~s(<path d="M5 12.5l4.5 4.5L19 7.5"/>),
    "x" => ~s(<path d="M6 6l12 12M18 6L6 18"/>),
    "more" =>
      ~s(<circle cx="5" cy="12" r="1.25"/><circle cx="12" cy="12" r="1.25"/><circle cx="19" cy="12" r="1.25"/>),
    "chevron-right" => ~s(<path d="M9 6l6 6-6 6"/>),
    "chevron-down" => ~s(<path d="M6 9l6 6 6-6"/>),
    "arrow-left" => ~s(<path d="M19 12H5M11 6l-6 6 6 6"/>),
    "send" => ~s(<path d="M21 3L10 14M21 3l-7 18-4-7-7-4 18-7z"/>),
    "refresh" =>
      ~s(<path d="M20 11a8 8 0 0 0-14.9-3M4 4v4h4M4 13a8 8 0 0 0 14.9 3M20 20v-4h-4"/>),
    "key" => ~s(<circle cx="8" cy="15" r="4"/><path d="M11 12l9-9M17 6l3 3M14 9l2 2"/>),
    "eye" =>
      ~s(<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>),
    "eye-off" =>
      ~s(<path d="M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.4 0 10 7 10 7a17 17 0 0 1-3.2 4.1M6.6 6.6A17 17 0 0 0 2 12s3.6 7 10 7a9.6 9.6 0 0 0 5.4-1.6M9.9 9.9a3 3 0 0 0 4.2 4.2"/>),
    "alert" =>
      ~s(<path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9L2.4 17.5A2 2 0 0 0 4.1 20.5h15.8a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>),
    "pause" =>
      ~s(<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>),
    "play" => ~s(<path d="M7 5v14l11-7z"/>),
    "trash" =>
      ~s(<path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>),
    "edit" => ~s(<path d="M4 20h4L19 9l-4-4L4 16v4zM13.5 6.5l4 4"/>),
    "search" => ~s(<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>),
    "clock" => ~s(<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>),
    "hook" =>
      ~s(<path d="M15.5 3.5L9 10M15.5 3.5l3 .5.5 3M9 10a2.5 2.5 0 1 0 0 3.5M7.2 12.6L6 19a2.5 2.5 0 0 0 5 .6V18"/>),
    "code" => ~s(<path d="M8 8l-4 4 4 4M16 8l4 4-4 4M14 5l-4 14"/>)
  }

  @doc "The names of the icons."
  def names, do: Map.keys(@paths)

  @doc "An icon by name."
  attr(:name, :string, required: true)
  attr(:class, :any, default: nil)

  def icon(assigns) do
    assigns = assign(assigns, :paths, Map.fetch!(@paths, assigns.name))

    ~H"""
    <svg
      class={["kunai-icon", @class]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >{Phoenix.HTML.raw(@paths)}</svg>
    """
  end
end
