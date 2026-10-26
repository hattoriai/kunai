# Changelog

## Unreleased

The core, a REST API and pages, mounted with PhoenixMountable.

* `kunai/2`: the pages of an owner's endpoints, in the app's layout,
  styled by `kunai.css` (and `kunai-sumi.css`): the list, the form, the
  secret, a test, the deliveries live, and a delivery with its attempts.
* `kunai_api/2`: the REST API, with prefixed ids, cursor lists,
  `Idempotency-Key`, `expand[]`, one error format, and an OpenAPI document
  with the webhooks themselves.

* A catalog of events (`Kunai.Catalog`), checked when the app compiles,
  with JSON Schemas, redaction and versions.
* Events emitted in the transaction of their change, kept apart from
  their deliveries, with their actor and previous fields.
* Endpoints with subscriptions, scopes, full or thin payloads, order,
  versions, an audit log, and secrets encrypted at rest, rolled with an
  overlap, HMAC or Ed25519.
* Delivery in Oban jobs: Standard Webhooks signatures, about three days
  of retries, `Retry-After`, 410 disabling, endpoints warned and disabled
  after days of failing, a circuit breaker, attempts claimed in the
  database.
* An egress guard against requests to the app's own network.
* A verifier and a plug for receivers.
* Tables on PostgreSQL and SQLite (`Kunai.Migrations`), and pruning.
