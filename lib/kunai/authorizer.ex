defmodule Kunai.Authorizer do
  @moduledoc """
  Which endpoint may receive which event. Asked for each endpoint
  subscribed to an event, when the event fans out: an endpoint that may
  not see it gets no delivery.

    * `Kunai.Authorizer.Scopes` - by scopes, the default.
    * A module of the app's, of this behaviour: with Sekisho, an endpoint
      gets an event only when its owner may read the event's object.
  """

  alias Kunai.{Endpoint, Event, EventType}

  @doc "Whether the endpoint may receive the event."
  @callback allow?(Endpoint.t(), Event.t(), EventType.t(), opts :: keyword()) :: boolean()
end

defmodule Kunai.Authorizer.Scopes do
  @moduledoc """
  An endpoint receives an event when it has every scope the event's type
  declares (`:scopes` of `Kunai.Catalog.event/2`). The app gives an
  endpoint its scopes when it is made, those the person making it holds,
  so an endpoint never sees more than its owner may.
  """

  @behaviour Kunai.Authorizer

  @impl Kunai.Authorizer
  def allow?(endpoint, _event, type, _opts), do: Enum.all?(type.scopes, &(&1 in endpoint.scopes))
end
