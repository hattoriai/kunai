defmodule KunaiTest.Auth do
  @moduledoc """
  The app's authentication, in the tests: the scope of a request from its
  `x-site` header (the API), or of a page from its session's `"site"`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_req_header(conn, "x-site") do
      [site] -> assign(conn, :current_scope, %{site: site, user: "api"})
      [] -> conn
    end
  end

  def on_mount(:default, _params, session, socket) do
    case session do
      %{"site" => site} ->
        # The app's language, as an app's hook sets it for its pages.
        if locale = session["locale"], do: Gettext.put_locale(KunaiTest.Gettext, locale)

        {:cont,
         Phoenix.Component.assign(socket, :current_scope, %{
           site: site,
           user: session["user"] || "u1"
         })}

      _signed_out ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end
end

defmodule KunaiTest.Layouts do
  @moduledoc "An app layout of the tests, as Phoenix 1.8's Layouts.app."
  use Phoenix.Component

  attr(:flash, :map)
  attr(:current_scope, :any)
  slot(:inner_block)

  def app(assigns) do
    ~H"""
    <main id="app-layout" data-site={@current_scope && @current_scope.site}>
      {render_slot(@inner_block)}
    </main>
    """
  end
end

defmodule KunaiTest.CustomEndpointLive do
  @moduledoc "An app's own endpoint page, on Kunai.Live.Page."
  use Kunai.Live.Page, base: "/custom/webhooks"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, assign(socket, endpoint: Kunai.get_endpoint(socket.assigns.kunai_scope, id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page kunai={@kunai} flash={@flash}>
      <.header title={"Ours: " <> @endpoint.url} back={@kunai.base} />
    </.page>
    """
  end
end

defmodule KunaiTest.Host do
  @moduledoc "An app that mounts Kunai's pages and API, for their tests."
  use PhoenixMountable.TestHost,
    otp_app: :kunai,
    mounts: [
      {Kunai.Router, "/webhooks", on_mount: [KunaiTest.Auth]},
      {Kunai.Router, "/settings/webhooks",
       as: :kunai_in_layout, on_mount: [KunaiTest.Auth], app_layout: {KunaiTest.Layouts, :app}}
    ],
    routes:
      (quote do
         import Kunai.Router

         pipeline :api do
           plug :accepts, ["json"]
           plug KunaiTest.Auth
         end

         scope "/api/v1" do
           pipe_through :api
           kunai_api("/webhooks")
         end

         # An app's own endpoint page, before the mount that keeps the rest.
         scope "/" do
           pipe_through :browser

           live_session :custom_endpoint, on_mount: [KunaiTest.Auth] do
             live "/custom/webhooks/endpoints/:id", KunaiTest.CustomEndpointLive, :show
           end

           kunai("/custom/webhooks", as: :kunai_custom, on_mount: [KunaiTest.Auth])
         end
       end)
end
