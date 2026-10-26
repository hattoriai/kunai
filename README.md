# Kunai

![Kunai — Webhooks for Phoenix](https://raw.githubusercontent.com/hattoriai/kunai/main/media/banner.png)

**Webhooks for Phoenix: your app's events, kept, signed, delivered and
retried, to the endpoints your users give it.**

A page published, an invoice paid, a member invited. Your users give your
app a URL; your app tells it what happened. Kunai keeps each event once,
in the transaction of the change it tells of, and delivers it to every
endpoint that subscribes to it and may see it: signed as Standard
Webhooks says, to an address that was checked, tried again for about
three days, an endpoint that keeps failing disabled and its owner told.

> Early work. Before 1.0, a minor version may change the API.

## Your events

The app declares its events once, in a catalog. A name it does not
declare is a compile error where it is emitted:

```elixir
defmodule MyApp.Webhooks do
  use Kunai.Catalog

  event "page.published",
    doc: "A page was published.",
    scopes: ["pages:read"],
    schema: [id: :string, title: :string, published_at: :datetime],
    example: %{"id" => "page_1", "title" => "Hello"}

  event "member.invited", scopes: ["members:read"], redact: [:token]

  @impl Kunai.Catalog
  def owner(%MyApp.Accounts.Scope{site: site}), do: "site:#{site.id}"

  @impl Kunai.Catalog
  def actor(%MyApp.Accounts.Scope{user: user}), do: %{type: "user", id: to_string(user.id)}
end
```

```elixir
# config/config.exs
config :kunai, repo: MyApp.Repo, catalog: MyApp.Webhooks

# config/runtime.exs
config :kunai, vault: {Kunai.Vault.Cloak, vault: MyApp.Vault}

config :my_app, Oban,
  queues: [kunai: 20],
  plugins: [
    # Jobs stuck executing when a node stopped run again.
    Oban.Plugins.Lifeline,
    {Oban.Plugins.Cron,
     crontab: [
       # Deliveries whose job was lost get a new one.
       {"*/5 * * * *", Kunai.Workers.Recover},
       {"17 3 * * *", Kunai.Workers.Prune}
     ]}
  ]
```

The tables are a migration of yours, pinned to a version
(`mix kunai.gen.migration`, `Kunai.Migrations`), on PostgreSQL or
SQLite.

## Emitting

An event goes in the transaction of its change: rolled back, nothing is
sent; committed, it always is.

```elixir
require MyApp.Webhooks

Ecto.Multi.new()
|> Ecto.Multi.update(:page, Page.publish_changeset(page))
|> MyApp.Webhooks.emit("page.published", & &1.page, scope: scope, previous: %{title: page.title})
|> Repo.transaction()
```

Or, in a transaction of your repo's, `emit!`, which joins it:

```elixir
Repo.transact(fn ->
  with {:ok, page} <- Repo.update(Page.publish_changeset(page)) do
    MyApp.Webhooks.emit!("page.published", page, scope: scope)
    {:ok, page}
  end
end)
```

Each event is kept once (`Kunai.Event`), with who made the change (a
person, an agent, a bot or the system), the fields that changed, and
none of the fields its type redacts. Your users list and fetch events
through your API, so one whose endpoint missed some catches up.

## Endpoints

The functions take the scope of the person acting first, as a Phoenix
1.8 context does:

```elixir
{:ok, endpoint, secret} =
  Kunai.create_endpoint(scope, %{
    url: "https://example.com/webhooks",
    events: ["page.*"],
    scopes: ["pages:read"]
  })

# secret is "whsec_…", shown once
Kunai.send_test(scope, endpoint, "page.published")
{:ok, new_secret} = Kunai.roll_secret(scope, endpoint)
```

An endpoint subscribes to names, families (`"page.*"`) or `"*"`, and gets
an event only with the event's scopes (`Kunai.Authorizer`). It takes the
whole object, or its id only (`payload: "thin"`); events in any order, or
one at a time in order (`ordered: true`); payloads of the latest version,
or of one it is pinned to, downgraded for it (`Kunai.Versions`).

Every change is in the audit log with who made it, and `Kunai.Page`
lists everything newest first, with Stripe's cursors.

## Pages and an API, in your router

Kunai mounts in your app with
[PhoenixMountable](https://hexdocs.pm/phoenix_mountable), as a Rails
engine would: ordinary routes behind your own pipelines.

```elixir
import Kunai.Router

scope "/settings" do
  pipe_through [:browser, :require_authenticated_user]

  kunai "/webhooks",
    on_mount: [{MyAppWeb.UserAuth, :require_authenticated}],
    # Your layout component, given flash and current_scope, around the pages.
    app_layout: {MyAppWeb.Layouts, :app},
    # A line over each page's title.
    eyebrow: "Settings"
end

scope "/api/v1" do
  pipe_through [:api, :fetch_api_scope]
  kunai_api "/webhooks"
end
```

Both read the request's scope where your pipeline and hooks put it
(`:current_scope`), so a person sees their owner's endpoints only.

**The pages** (`kunai`) are your users' webhook settings: their
endpoints, the form of one (its events, its access, full or thin
payloads, order, version, signing), its secret to reveal and roll, a test
to send, its deliveries live over PubSub, and each delivery with its
attempts and its payload, to send again. Over them, the last day's
deliveries by hour and how they went (`Kunai.Stats`).

They render in your layout, styled by a style sheet you import, and a
script for copying, in your `app.js`:

```css
@import "../../deps/kunai/priv/static/kunai.css";
/* Your daisyUI theme's colours and radii: */
/* @import "../../deps/kunai/priv/static/kunai-daisyui.css"; */
```

```js
import "../../deps/kunai/priv/static/kunai.js"
```

Your app's look is a few lines of CSS: every face, size, colour, radius
and space of the pages is a `--kunai-*` property, set on `.kunai`, with
no specificity to fight. Kunai ships a neutral look; an app with a
serif face, ink buttons and square corners makes it its own with:

```css
.kunai, .kunai-flashes {
  --kunai-font-display: Palatino, Georgia, serif;
  --kunai-card-title-font: var(--kunai-font-display);
  --kunai-text: var(--ink);
  --kunai-accent: var(--accent);
  --kunai-primary-background: var(--ink);
  --kunai-radius: 0;
  --kunai-button-radius: 0;
}
```

The pages are made of `Kunai.Components` (cards, tables of endpoints and
deliveries, a delivery's attempts, the endpoint form, charts), public and
documented, so pages of your own can use them, or none: the context
functions under them (`Kunai`) are the same the pages call. Their text
goes through your Gettext backend when you name one
(`config :kunai, gettext: MyAppWeb.Gettext`, domain `"kunai"`).

**The API** (`kunai_api`) has Stripe's conventions: prefixed ids,
cursor lists (`starting_after`, `ending_before`), `Idempotency-Key` on
every write, `expand[]`, and one error format. Its OpenAPI document,
`GET /webhooks/openapi.json`, has each event under `webhooks`, with its
JSON Schema, so a client generates its receiver as well as its calls
(`Kunai.API`).

## Delivery

| Answer | What follows |
| --- | --- |
| 2xx | delivered |
| 410 Gone | the endpoint is disabled |
| anything else, or no answer | tried again: 12 attempts over about three days, a `Retry-After` obeyed |

* **The same `webhook-id` on every attempt**, so the receiver knows a
  retry from a new event.
* **One failure never disables an endpoint.** One failing every attempt
  for a day has its owner warned, for three days is disabled
  (`Kunai.Notifier`).
* **One endpoint never slows another.** Each attempt is a job and a
  connection of its own; an endpoint failing five times in a row is left
  alone for a while (`Kunai.CircuitBreaker`).
* **By hand:** send a delivery again, replay an endpoint's failed
  deliveries of a time, send a test.

## Security

* **Standard Webhooks signatures**: `webhook-id`, `webhook-timestamp`
  and `webhook-signature`, over the bytes sent, so the libraries of every
  language check them. HMAC-SHA256 (`whsec_`) by default, or Ed25519, the
  receiver keeping only a public key (`whpk_`).
* **Secrets encrypted at rest** (`Kunai.Vault`), prefixed so a secret
  scanner finds one that leaked, and rolled with the old one signing
  beside the new for a day.
* **No request to your own network.** HTTPS only; every address a name
  resolves to is checked, private, loopback, link-local, multicast,
  unique local, IPv4-mapped and NAT64 refused; the request goes to the
  address checked, with the name for TLS; no redirect followed; time and
  size limits (`Kunai.Egress`).

## Receiving

For an app of yours that receives webhooks, from Kunai or any sender of
Standard Webhooks:

```elixir
plug Kunai.Plug.Verify, secrets: {MyApp.Billing, :webhook_secrets, []}

def create(conn, _params) do
  %{"type" => type, "data" => %{"object" => object}} = conn.assigns.webhook
end
```

It compares in constant time, and refuses a timestamp more than five
minutes from now (`Kunai.Verifier`).

## Your own adapters

Each part is a behaviour with a default:

| Behaviour | Default |
| --- | --- |
| `Kunai.Authorizer` | by scopes |
| `Kunai.Serializer` | Elixir's `JSON` |
| `Kunai.Transport` | HTTP, with Mint |
| `Kunai.RetryPolicy` | about three days |
| `Kunai.Notifier` | the log |
| `Kunai.Vault` | Cloak |

Kunai needs Oban's open source engines, not Oban Pro, and emits
`:telemetry` spans for each event, fan-out, attempt and endpoint disabled
(`Kunai.Telemetry`).

## Roadmap

* **An admin's page** across every owner: the endpoints failing, the
  deliveries waiting, in a document of its own, as Oban Web's.
* **`mix kunai.listen`**: your events, live, to localhost in development,
  over a Phoenix channel, with no tunnel.
* **An installer** (`mix igniter.install kunai`), an endpoint verified by
  a signed challenge before it is enabled, a Sekisho authorizer, mTLS and
  an egress proxy for fixed addresses, and queues (SQS, EventBridge,
  Pub/Sub) as transports.

## Development

```sh
mix deps.get
mix test                    # PostgreSQL at DATABASE_URL, or a local one
KUNAI_DB=sqlite mix test    # SQLite
mix credo --strict
```

## License

MIT. See [LICENSE](https://github.com/hattoriai/kunai/blob/main/LICENSE).
