defmodule Kunai.Live.Page do
  @moduledoc """
  What every page of Kunai's is built on, and what an app's own page of
  webhooks uses too:

      defmodule MyAppWeb.WebhooksLive do
        use Kunai.Live.Page, base: "/settings/webhooks", app_layout: {MyAppWeb.Layouts, :app}

        def mount(_params, _session, socket) do
          {:ok, assign(socket, page: Kunai.list_endpoints(socket.assigns.kunai_scope))}
        end

        def render(assigns) do
          ~H\"\"\"
          <.page kunai={@kunai} flash={@flash}>
            <.endpoints_table endpoints={@page.data} base={@kunai.base} />
          </.page>
          \"\"\"
        end
      end

  It is `Phoenix.LiveView`, with `Kunai.Components`, `Kunai.Icons` and
  `Kunai.Text` imported, and a hook that assigns `@kunai`: the scope of
  the person (`scope`, from `:current_scope`), where the pages are (`base`)
  and the app's layout component (`app_layout`). Mounted with
  `Kunai.Router`, they come from the mount; an app's page passes them:

    * `:base` - the path of the pages, for their links.
    * `:app_layout` - the app's layout component, `{module, function}`.
    * `:scope_assign` - where the app's hooks put the scope
      (`:current_scope`).
    * `:eyebrow` - a line above the pages' titles.

  `mix kunai.gen.live` copies Kunai's pages into the app, on this.
  """

  defstruct [:scope, :base, :app_layout, :eyebrow]

  @type t :: %__MODULE__{
          scope: term(),
          base: String.t(),
          app_layout: {module(), atom()} | nil,
          eyebrow: String.t() | nil
        }

  defmacro __using__(opts) do
    quote do
      use Phoenix.LiveView

      import Kunai.Components
      import Kunai.Icons
      import Kunai.Text, only: [t: 1, t: 2, tn: 3, tn: 4]

      on_mount({Kunai.Live.Page, unquote(opts)})
    end
  end

  @doc false
  def on_mount(opts, _params, _session, socket) do
    mount = socket.assigns[:mount]
    option = fn name -> opts[name] || (mount && mount.options[name]) end
    key = option.(:scope_assign) || :current_scope

    base =
      opts[:base] || (mount && mount.path) ||
        raise ArgumentError,
              "a page of Kunai's outside its mount needs :base, the path of the pages"

    case socket.assigns[key] do
      nil ->
        raise ArgumentError,
              "Kunai's pages found no @#{key}: mount them with the app's hook that assigns it, " <>
                "kunai \"/webhooks\", on_mount: [{MyAppWeb.UserAuth, :require_authenticated}]"

      scope ->
        kunai = %__MODULE__{
          scope: scope,
          base: String.trim_trailing(base, "/"),
          app_layout: option.(:app_layout),
          eyebrow: option.(:eyebrow)
        }

        {:cont, Phoenix.Component.assign(socket, kunai: kunai, kunai_scope: scope)}
    end
  end
end
