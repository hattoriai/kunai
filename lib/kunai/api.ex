defmodule Kunai.API do
  @moduledoc """
  The REST API (`Kunai.API.Router`), with Stripe's conventions:

    * **Ids** with a prefix that says what they are (`ep_`, `evt_`, `msg_`).
    * **Lists** newest first, `{"object": "list", "data": [...],
      "has_more": bool, "url": ...}`, with `limit` (1 to 100, 25),
      `starting_after` and `ending_before`.
    * **`Idempotency-Key`** on a `POST`, `PATCH` or `DELETE`: the same key
      gives the same response again for a day, with `Idempotent-Replayed:
      true`; the same key with other parameters is refused.
    * **`expand[]`**: a delivery's `event` and `endpoint` given whole.
    * **One error format**: `{"error": {"type", "code", "message",
      "param"}}`, with `"errors"` by field when the parameters are invalid.

  ## The routes

    * `GET /endpoints`, `POST /endpoints` - the endpoints; a new one comes
      with its `secret`, shown once.
    * `GET /endpoints/:id`, `POST /endpoints/:id` (or `PATCH`),
      `DELETE /endpoints/:id`.
    * `POST /endpoints/:id/roll_secret` - `expires_in` (seconds the old
      secret still signs, a day) and `signing` (`hmac`, `ed25519`): the new
      `secret`.
    * `POST /endpoints/:id/enable`, `POST /endpoints/:id/disable`.
    * `POST /endpoints/:id/test` - `type` (`kunai.ping`): a test event to
      that endpoint only, and its delivery.
    * `POST /endpoints/:id/replay` - `from` and `to` (ISO 8601) and
      `status` (`failed`): its deliveries of that time sent again.
    * `GET /events` (`type`), `GET /events/:id`.
    * `GET /deliveries` (`endpoint`, `event`, `status`),
      `GET /deliveries/:id` (with its `attempt_log`),
      `POST /deliveries/:id/retry`.
    * `GET /event_types` - the catalog, each with its JSON Schema.
    * `GET /openapi.json` - the OpenAPI document of these routes and of the
      webhooks themselves.
  """

  @doc false
  defmacro __using__(:controller) do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn
      import Kunai.API.Helpers

      alias Kunai.API.JSON, as: View

      plug :require_scope
    end
  end
end
