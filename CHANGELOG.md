# Changelog

## Unreleased

The core, a REST API and pages, mounted with PhoenixMountable.

* `kunai/2`: the pages of an owner's endpoints, in the app's layout
  (`app_layout`, `eyebrow`): the list with the last day's deliveries, the
  form, the secret, a test, an endpoint's deliveries live with each in a
  drawer, and a delivery with its attempts.
* The pages' look as `--kunai-*` properties (`kunai.css`), with
  `kunai-daisyui.css` and `kunai-sumi.css`; `kunai.js` for copying.
* `Kunai.Components`, public: the pages' parts, for pages of an app's own.
* `Kunai.Stats`: deliveries by hour and state, the retrying apart.
* `emit!/3` in a transaction of the app's repo.
* `Kunai.recover/1` and `Kunai.Workers.Recover`: deliveries whose job was
  lost get a new one.
* Text through the app's Gettext backend (`:gettext`), from
  `priv/gettext/kunai.pot`.
* `mix kunai.gen.live`: Kunai's pages copied into the app, all or some.
  An endpoint's pages are under `/endpoints/:id`, so that no two routes
  match one path, and an app's route takes over one page only.
* `Kunai.catalog/0`, `payload/2`, `example_payload/0` and `subscribe/1`:
  what the pages call, for pages of an app's own.
* The Customizing guide: the tokens, the mappings, the frame, the words,
  a page of the app's own.
* `Kunai.Dev.Inbox`: endpoints that are the app itself, in development,
  each request shown live on the Inbox page, its signature verified, its
  answer chosen by its address (`?status=`, `?delay=`).
* `mix kunai.trigger`: an event of the catalog, from its example, sent
  now and watched; `--dry-run` prints the signed requests and a `curl`.
* `Kunai.Testing`: `assert_emitted`, `refute_emitted`, `deliver`,
  `respond`, `assert_delivered` and `refute_delivered`, with
  `Kunai.Testing.Transport`.
* The Testing guide.
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
