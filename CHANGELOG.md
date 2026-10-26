# Changelog

## Unreleased

The core, headless: context functions, no API or pages yet.

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
