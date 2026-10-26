defmodule Kunai.API.Router do
  @moduledoc """
  Kunai's REST API, mounted with `kunai_api/2` (imported with
  `Kunai.Router`):

      scope "/api/v1" do
        pipe_through [:api, :fetch_api_scope]
        kunai_api "/webhooks"
      end

  Mount it behind the app's own API pipeline, which authenticates the
  request and assigns its scope (`:current_scope`, or the mount's
  `:scope_assign`): what the API reaches is that scope's owner's
  (`c:Kunai.Catalog.owner/1`). See `Kunai.API` for the routes and their
  conventions, and `GET <mount>/openapi.json` for the document.
  """

  use PhoenixMountable, otp_app: :kunai, macro: :kunai_api, schema: Kunai.Migrations

  options(
    scope_assign: [
      type: :atom,
      default: :current_scope,
      doc: "The assign of the conn that holds the request's scope, set by the app's pipeline."
    ]
  )

  routes do
    get "/endpoints", Kunai.API.EndpointController, :index, as: :endpoints
    post "/endpoints", Kunai.API.EndpointController, :create, as: :endpoints
    get "/endpoints/:id", Kunai.API.EndpointController, :show, as: :endpoints
    post "/endpoints/:id", Kunai.API.EndpointController, :update, as: :endpoints
    patch "/endpoints/:id", Kunai.API.EndpointController, :update, as: :endpoints
    delete "/endpoints/:id", Kunai.API.EndpointController, :delete, as: :endpoints
    post "/endpoints/:id/roll_secret", Kunai.API.EndpointController, :roll_secret, as: :endpoints
    post "/endpoints/:id/enable", Kunai.API.EndpointController, :enable, as: :endpoints
    post "/endpoints/:id/disable", Kunai.API.EndpointController, :disable, as: :endpoints
    post "/endpoints/:id/test", Kunai.API.EndpointController, :test, as: :endpoints
    post "/endpoints/:id/replay", Kunai.API.EndpointController, :replay, as: :endpoints
    get "/events", Kunai.API.EventController, :index, as: :events
    get "/events/:id", Kunai.API.EventController, :show, as: :events
    get "/deliveries", Kunai.API.DeliveryController, :index, as: :deliveries
    get "/deliveries/:id", Kunai.API.DeliveryController, :show, as: :deliveries
    post "/deliveries/:id/retry", Kunai.API.DeliveryController, :retry, as: :deliveries
    get "/event_types", Kunai.API.EventTypeController, :index, as: :event_types
    get "/openapi.json", Kunai.API.EventTypeController, :openapi, as: :openapi
  end

  @impl PhoenixMountable
  def repo(_mount), do: Application.get_env(:kunai, :repo)
end
