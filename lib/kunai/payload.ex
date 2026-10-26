defmodule Kunai.Payload do
  @moduledoc """
  What an endpoint receives for an event:

      {
        "id": "evt_06fh2k4w1xg9h3z5c8m2q7v0rs",
        "object": "event",
        "type": "page.published",
        "created_at": "2026-10-26T09:00:00.000000Z",
        "api_version": "2026-10-01",
        "actor": {"type": "user", "id": "42", "name": "Ana"},
        "data": {
          "object": {"id": "page_1", "title": "Hello"},
          "previous": {"title": "Draft"}
        }
      }

  An endpoint with `payload: "thin"` gets the object's id only,
  `"data": {"object": {"id": "page_1"}}`, and asks the app's API for the
  rest: what it reads then is never out of date. A test event has
  `"test": true`.
  """

  alias Kunai.{Endpoint, Event, Versions}

  @doc "The payload of an event for an endpoint, in the endpoint's version."
  @spec build(module(), Event.t(), Endpoint.t()) :: map()
  def build(catalog, %Event{} = event, %Endpoint{} = endpoint) do
    data =
      case endpoint.payload do
        "thin" -> %{"object" => %{"id" => event.object_id}}
        _full -> %{"object" => event.data, "previous" => event.previous}
      end

    payload =
      %{
        "id" => event.id,
        "object" => "event",
        "type" => event.type,
        "created_at" => DateTime.to_iso8601(event.created_at),
        "api_version" => event.api_version,
        "actor" => event.actor,
        "data" => data
      }
      |> then(&if(event.test, do: Map.put(&1, "test", true), else: &1))

    Versions.downgrade(catalog, payload, event.api_version, endpoint.api_version)
  end
end
