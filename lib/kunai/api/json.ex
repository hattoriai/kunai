defmodule Kunai.API.JSON do
  @moduledoc """
  The objects of the API, as JSON: each has its `"object"`, and its times
  in ISO 8601.
  """

  alias Kunai.{Attempt, Delivery, Endpoint, Event, EventType, Payload}

  @doc "An endpoint, with its `secret` when it was just made or rolled."
  @spec endpoint(Endpoint.t(), String.t() | nil) :: map()
  def endpoint(%Endpoint{} = endpoint, secret \\ nil) do
    %{
      "id" => endpoint.id,
      "object" => "endpoint",
      "url" => endpoint.url,
      "description" => endpoint.description,
      "events" => endpoint.events,
      "scopes" => endpoint.scopes,
      "status" => endpoint.status,
      "disabled_reason" => endpoint.disabled_reason,
      "payload" => endpoint.payload,
      "ordered" => endpoint.ordered,
      "api_version" => endpoint.api_version,
      "metadata" => endpoint.metadata,
      "failing_since" => time(endpoint.failing_since),
      "created_at" => time(endpoint.inserted_at),
      "updated_at" => time(endpoint.updated_at)
    }
    |> then(&if(secret, do: Map.put(&1, "secret", secret), else: &1))
  end

  @doc "An event, as an endpoint of the latest version receives it."
  @spec event(Event.t()) :: map()
  def event(%Event{} = event) do
    latest = %Endpoint{payload: "full", api_version: event.api_version}
    Kunai.Config.catalog() |> Payload.build(event, latest) |> Map.put("test", event.test)
  end

  @doc "A delivery: its event and endpoint by id, or whole when expanded."
  @spec delivery(Delivery.t(), [String.t()]) :: map()
  def delivery(%Delivery{} = delivery, expand \\ []) do
    %{
      "id" => delivery.id,
      "object" => "delivery",
      "event" => expanded(delivery.event_id, "event" in expand, &event/1, Event),
      "endpoint" => expanded(delivery.endpoint_id, "endpoint" in expand, &endpoint/1, Endpoint),
      "event_type" => delivery.event_type,
      "status" => delivery.status,
      "attempts" => delivery.attempts,
      "next_attempt_at" => time(delivery.status == "pending" && delivery.next_attempt_at),
      "last_attempt_at" => time(delivery.last_attempt_at),
      "completed_at" => time(delivery.completed_at),
      "last_status_code" => delivery.last_status_code,
      "last_error" => delivery.last_error,
      "created_at" => time(delivery.inserted_at)
    }
    |> then(fn json ->
      case delivery.attempt_log do
        attempts when is_list(attempts) ->
          Map.put(json, "attempt_log", Enum.map(attempts, &attempt/1))

        _not_loaded ->
          json
      end
    end)
  end

  defp expanded(id, false, _fun, _schema), do: id

  defp expanded(id, true, fun, schema) do
    case Kunai.Config.repo().get(schema, id, Kunai.Config.repo_opts()) do
      nil -> id
      row -> fun.(row)
    end
  end

  @doc "An attempt of a delivery."
  @spec attempt(Attempt.t()) :: map()
  def attempt(%Attempt{} = attempt) do
    %{
      "id" => attempt.id,
      "object" => "attempt",
      "number" => attempt.number,
      "status_code" => attempt.status_code,
      "duration_ms" => attempt.duration_ms,
      "response_body" => attempt.response_body,
      "error" => attempt.error,
      "created_at" => time(attempt.created_at)
    }
  end

  @doc "An event of the catalog, with its JSON Schema."
  @spec event_type(EventType.t()) :: map()
  def event_type(%EventType{} = type) do
    %{
      "object" => "event_type",
      "name" => type.name,
      "description" => type.doc,
      "scopes" => type.scopes,
      "schema" => EventType.json_schema(type)
    }
  end

  defp time(nil), do: nil
  defp time(false), do: nil
  defp time(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
