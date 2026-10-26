defmodule Kunai.Router do
  @moduledoc """
  Mounts Kunai in the app's router: the pages of its users' endpoints,
  and the REST API.

      import Kunai.Router

      scope "/settings" do
        pipe_through [:browser, :require_authenticated_user]

        kunai "/webhooks",
          on_mount: [{MyAppWeb.UserAuth, :require_authenticated}],
          app_layout: {MyAppWeb.Layouts, :app}
      end

      scope "/api/v1" do
        pipe_through [:api, :fetch_api_scope]
        kunai_api "/webhooks"
      end

  `kunai/2` mounts the pages: an owner's endpoints, the form of one, its
  secret, a test, its deliveries live, and each delivery with its event and
  attempts, to send again. They render inside the app's root layout, and
  inside its app layout when `:app_layout` names it (Phoenix 1.8's
  `Layouts.app`, given `flash` and `current_scope`), styled by
  `kunai.css`, which the app imports:

      @import "../../deps/kunai/priv/static/kunai.css";
      /* @import "../../deps/kunai/priv/static/kunai-sumi.css"; */

  `kunai_api/2` mounts the API (`Kunai.API.Router`, `Kunai.API`).

  Both read the scope of the request where the app's pipeline and hooks
  put it, `:current_scope` (or the mount's `:scope_assign`): what they show
  is that scope's owner's (`c:Kunai.Catalog.owner/1`), and the audit log
  says who did it. Each is a library mounted with
  [PhoenixMountable](https://hexdocs.pm/phoenix_mountable): ordinary routes
  in the app's router, behind its own scopes and pipelines, which also
  take `:as`, `:on_mount`, `:socket_path`, `:transport`,
  `:csp_nonce_assign_key`, `:asset_host` and `:pubsub`.
  """

  alias Kunai.API.Router, as: API

  use PhoenixMountable,
    otp_app: :kunai,
    macro: :kunai,
    title: "Webhooks",
    layout: :host,
    schema: Kunai.Migrations

  options(
    scope_assign: [
      type: :atom,
      default: :current_scope,
      doc: "The assign that holds the scope, set by the app's `on_mount` hooks."
    ],
    eyebrow: [
      type: :string,
      doc: "A line above the pages' titles, as the app's other pages have (`\"Settings\"`)."
    ],
    app_layout: [
      type: {:tuple, [:atom, :atom]},
      doc:
        "The app's layout component, `{MyAppWeb.Layouts, :app}`: the pages render in it, with `flash` and `current_scope`."
    ]
  )

  routes do
    live "/", Kunai.Live.EndpointsLive, :index
    live "/new", Kunai.Live.EndpointFormLive, :new
    live "/deliveries/:id", Kunai.Live.DeliveryLive, :show
    live "/:id", Kunai.Live.EndpointLive, :show
    live "/:id/edit", Kunai.Live.EndpointFormLive, :edit
  end

  @impl PhoenixMountable
  def repo(_mount), do: Application.get_env(:kunai, :repo)

  @doc """
  Mounts Kunai's REST API at `path`: see `Kunai.API.Router` for the
  options, and `Kunai.API` for the routes.
  """
  defmacro kunai_api(path, opts \\ []) do
    quote do
      require unquote(API)
      unquote(API).kunai_api(unquote(path), unquote(opts))
    end
  end
end
