defmodule Kunai.API.OpenAPI do
  @moduledoc """
  The OpenAPI 3.1 document of the API, made from its routes and the app's
  catalog: the paths, the objects, and, under `webhooks`, each event an
  endpoint may receive with its JSON Schema, so a client generates the
  code of its receiver as well as of its calls.

  Served at `GET <mount>/openapi.json`.
  """

  alias Kunai.{Config, EventType}

  @doc "The document, for the API mounted at `path`."
  @spec document(String.t()) :: map()
  def document(path) do
    catalog = Config.catalog()
    types = catalog.event_types() |> Enum.reject(&(&1.name == "kunai.ping"))

    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => "Webhooks",
        "version" => catalog.latest_version() || "1",
        "description" => "Endpoints, the events they receive, and their deliveries."
      },
      "servers" => [%{"url" => path}],
      "paths" => paths(),
      "webhooks" => Map.new(types, &{&1.name, webhook(&1)}),
      "components" => %{
        "schemas" => schemas(types),
        "parameters" => parameters(),
        "responses" => %{
          "Error" => %{
            "description" => "An error.",
            "content" => json(ref("Error"))
          }
        }
      }
    }
  end

  defp paths do
    %{
      "/endpoints" => %{
        "get" => list_operation("listEndpoints", "Endpoint", ["status"]),
        "post" =>
          operation("createEndpoint", "Makes an endpoint; its secret is shown once.",
            body: "EndpointInput",
            response: {201, "Endpoint"},
            idempotent: true
          )
      },
      "/endpoints/{id}" => %{
        "parameters" => [ref_param("id")],
        "get" => operation("getEndpoint", "An endpoint.", response: "Endpoint"),
        "post" =>
          operation("updateEndpoint", "Changes an endpoint.",
            body: "EndpointInput",
            response: "Endpoint",
            idempotent: true
          ),
        "delete" =>
          operation("deleteEndpoint", "Deletes an endpoint and its deliveries.",
            response: "Deleted",
            idempotent: true
          )
      },
      "/endpoints/{id}/roll_secret" =>
        action(
          "rollEndpointSecret",
          "A new secret; the old one signs beside it until it expires.",
          "Endpoint",
          body: %{
            "type" => "object",
            "properties" => %{
              "expires_in" => %{
                "type" => "integer",
                "description" => "Seconds the old secret still signs."
              },
              "signing" => %{"enum" => ["hmac", "ed25519"]}
            }
          }
        ),
      "/endpoints/{id}/enable" => action("enableEndpoint", "Enables an endpoint.", "Endpoint"),
      "/endpoints/{id}/disable" => action("disableEndpoint", "Disables an endpoint.", "Endpoint"),
      "/endpoints/{id}/test" =>
        action("testEndpoint", "Sends a test event to this endpoint only.", "Delivery",
          body: %{"type" => "object", "properties" => %{"type" => %{"type" => "string"}}}
        ),
      "/endpoints/{id}/replay" =>
        action("replayEndpoint", "Sends again its deliveries of a time.", "Replay",
          body: %{
            "type" => "object",
            "properties" => %{
              "from" => %{"type" => "string", "format" => "date-time"},
              "to" => %{"type" => "string", "format" => "date-time"},
              "status" => %{"enum" => ["failed", "succeeded", "pending"]}
            }
          }
        ),
      "/events" => %{"get" => list_operation("listEvents", "Event", ["type"])},
      "/events/{id}" => %{
        "parameters" => [ref_param("id")],
        "get" => operation("getEvent", "An event.", response: "Event")
      },
      "/deliveries" => %{
        "get" =>
          list_operation("listDeliveries", "Delivery", ["endpoint", "event", "status", "expand"])
      },
      "/deliveries/{id}" => %{
        "parameters" => [ref_param("id")],
        "get" =>
          operation("getDelivery", "A delivery, with its attempts.",
            response: "Delivery",
            parameters: [ref_param("expand")]
          )
      },
      "/deliveries/{id}/retry" =>
        action("retryDelivery", "Sends a delivery again, now.", "Delivery"),
      "/event_types" => %{"get" => list_operation("listEventTypes", "EventType", [])}
    }
  end

  defp action(id, summary, response, opts \\ []) do
    %{
      "parameters" => [ref_param("id")],
      "post" =>
        operation(id, summary, Keyword.merge([response: response, idempotent: true], opts))
    }
  end

  defp list_operation(id, schema, filters) do
    params = Enum.map(["limit", "starting_after", "ending_before" | filters], &ref_param/1)

    %{
      "operationId" => id,
      "parameters" => params,
      "responses" => %{
        "200" => %{
          "description" => "A list, newest first.",
          "content" =>
            json(%{
              "allOf" => [
                ref("List"),
                %{"properties" => %{"data" => %{"type" => "array", "items" => ref(schema)}}}
              ]
            })
        },
        "default" => %{"$ref" => "#/components/responses/Error"}
      }
    }
  end

  defp operation(id, summary, opts) do
    {status, schema} =
      case opts[:response] do
        {status, schema} -> {status, schema}
        schema -> {200, schema}
      end

    params =
      Keyword.get(opts, :parameters, []) ++
        if(opts[:idempotent], do: [ref_param("idempotency_key")], else: [])

    %{
      "operationId" => id,
      "summary" => summary,
      "parameters" => params,
      "responses" => %{
        "#{status}" => %{"description" => summary, "content" => json(ref(schema))},
        "default" => %{"$ref" => "#/components/responses/Error"}
      }
    }
    |> then(fn op ->
      case opts[:body] do
        nil -> op
        name when is_binary(name) -> Map.put(op, "requestBody", %{"content" => json(ref(name))})
        schema -> Map.put(op, "requestBody", %{"content" => json(schema)})
      end
    end)
  end

  defp webhook(%EventType{} = type) do
    %{
      "post" => %{
        "summary" => type.doc || type.name,
        "parameters" =>
          for header <- ["webhook-id", "webhook-timestamp", "webhook-signature"] do
            %{
              "name" => header,
              "in" => "header",
              "required" => true,
              "schema" => %{"type" => "string"}
            }
          end,
        "requestBody" => %{
          "content" => json(EventType.json_schema(type) |> Map.delete("$schema"))
        },
        "responses" => %{
          "2XX" => %{
            "description" =>
              "Received. Any other answer is tried again; 410 disables the endpoint."
          }
        }
      }
    }
  end

  defp schemas(types) do
    time = %{"type" => ["string", "null"], "format" => "date-time"}
    strings = %{"type" => "array", "items" => %{"type" => "string"}}

    %{
      "Endpoint" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string", "pattern" => "^ep_"},
          "object" => %{"const" => "endpoint"},
          "url" => %{"type" => "string", "format" => "uri"},
          "description" => %{"type" => ["string", "null"]},
          "events" => strings,
          "scopes" => strings,
          "status" => %{"enum" => ["enabled", "disabled"]},
          "disabled_reason" => %{"enum" => ["manual", "gone", "failing", nil]},
          "payload" => %{"enum" => ["full", "thin"]},
          "ordered" => %{"type" => "boolean"},
          "api_version" => %{"type" => ["string", "null"]},
          "metadata" => %{"type" => "object"},
          "secret" => %{
            "type" => "string",
            "description" => "Only when it was just made or rolled."
          },
          "failing_since" => time,
          "created_at" => time,
          "updated_at" => time
        }
      },
      "EndpointInput" => %{
        "type" => "object",
        "required" => ["url", "events"],
        "properties" => %{
          "url" => %{"type" => "string", "format" => "uri"},
          "description" => %{"type" => "string"},
          "events" => %{"type" => "array", "items" => %{"enum" => ["*" | event_patterns(types)]}},
          "scopes" => strings,
          "payload" => %{"enum" => ["full", "thin"]},
          "ordered" => %{"type" => "boolean"},
          "api_version" => %{"type" => "string"},
          "metadata" => %{"type" => "object"},
          "signing" => %{"enum" => ["hmac", "ed25519"]}
        }
      },
      "Event" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string", "pattern" => "^evt_"},
          "object" => %{"const" => "event"},
          "type" => %{"enum" => Enum.map(types, & &1.name)},
          "created_at" => time,
          "api_version" => %{"type" => ["string", "null"]},
          "actor" => %{"type" => ["object", "null"]},
          "test" => %{"type" => "boolean"},
          "data" => %{"type" => "object"}
        }
      },
      "Delivery" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string", "pattern" => "^msg_"},
          "object" => %{"const" => "delivery"},
          "event" => %{"oneOf" => [%{"type" => "string"}, ref("Event")]},
          "endpoint" => %{"oneOf" => [%{"type" => "string"}, ref("Endpoint")]},
          "event_type" => %{"type" => "string"},
          "status" => %{"enum" => ["pending", "succeeded", "failed"]},
          "attempts" => %{"type" => "integer"},
          "next_attempt_at" => time,
          "last_attempt_at" => time,
          "completed_at" => time,
          "last_status_code" => %{"type" => ["integer", "null"]},
          "last_error" => %{"type" => ["string", "null"]},
          "attempt_log" => %{"type" => "array", "items" => ref("Attempt")},
          "created_at" => time
        }
      },
      "Attempt" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string"},
          "number" => %{"type" => "integer"},
          "status_code" => %{"type" => ["integer", "null"]},
          "duration_ms" => %{"type" => "integer"},
          "response_body" => %{"type" => ["string", "null"]},
          "error" => %{"type" => ["string", "null"]},
          "created_at" => time
        }
      },
      "EventType" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "description" => %{"type" => ["string", "null"]},
          "scopes" => strings,
          "schema" => %{"type" => "object"}
        }
      },
      "Replay" => %{
        "type" => "object",
        "properties" => %{
          "endpoint" => %{"type" => "string"},
          "deliveries" => %{"type" => "integer"}
        }
      },
      "Deleted" => %{
        "type" => "object",
        "properties" => %{"id" => %{"type" => "string"}, "deleted" => %{"const" => true}}
      },
      "List" => %{
        "type" => "object",
        "properties" => %{
          "object" => %{"const" => "list"},
          "url" => %{"type" => "string"},
          "has_more" => %{"type" => "boolean"},
          "data" => %{"type" => "array"}
        }
      },
      "Error" => %{
        "type" => "object",
        "properties" => %{
          "error" => %{
            "type" => "object",
            "properties" => %{
              "type" => %{"type" => "string"},
              "code" => %{"type" => "string"},
              "message" => %{"type" => "string"},
              "param" => %{"type" => "string"},
              "errors" => %{"type" => "object"}
            }
          }
        }
      }
    }
  end

  defp event_patterns(types) do
    families =
      types
      |> Enum.map(&(&1.name |> String.split(".") |> hd()))
      |> Enum.uniq()
      |> Enum.map(&(&1 <> ".*"))

    families ++ Enum.map(types, & &1.name)
  end

  defp parameters do
    query = fn name, schema, description ->
      %{"name" => name, "in" => "query", "schema" => schema, "description" => description}
    end

    %{
      "id" => %{
        "name" => "id",
        "in" => "path",
        "required" => true,
        "schema" => %{"type" => "string"}
      },
      "limit" =>
        query.(
          "limit",
          %{"type" => "integer", "minimum" => 1, "maximum" => 100},
          "How many (25)."
        ),
      "starting_after" =>
        query.("starting_after", %{"type" => "string"}, "The page after this id."),
      "ending_before" =>
        query.("ending_before", %{"type" => "string"}, "The page before this id."),
      "status" => query.("status", %{"type" => "string"}, "Only of this status."),
      "type" => query.("type", %{"type" => "string"}, "Only of this event type."),
      "endpoint" => query.("endpoint", %{"type" => "string"}, "Only to this endpoint."),
      "event" => query.("event", %{"type" => "string"}, "Only of this event."),
      "expand" =>
        query.(
          "expand[]",
          %{"type" => "array", "items" => %{"enum" => ["event", "endpoint"]}},
          "Given whole."
        ),
      "idempotency_key" => %{
        "name" => "Idempotency-Key",
        "in" => "header",
        "schema" => %{"type" => "string", "maxLength" => 255},
        "description" => "The same key gives the same response again, for a day."
      }
    }
  end

  defp ref_param(name), do: %{"$ref" => "#/components/parameters/#{name}"}
  defp ref(name), do: %{"$ref" => "#/components/schemas/#{name}"}
  defp json(schema), do: %{"application/json" => %{"schema" => schema}}
end
