# Testing webhooks

Webhooks are hard to try by hand: the receiver is somewhere else, the
events come from changes that take a while to make, and a failure shows
up three retries later. Kunai gives each of those a shortcut.

* [The inbox](#the-inbox): in development, endpoints that are your app
  itself, each request shown live, with whether its signature verifies.
* [`mix kunai.trigger`](#mix-kunai-trigger): an event of your catalog,
  sent now, without making the change it tells of.
* [`Kunai.Testing`](#in-your-tests): assertions for your app's tests.

## The inbox

Add the plug to your endpoint, where only development runs it, and let
Kunai send to your app's own address:

```elixir
# lib/my_app_web/endpoint.ex
if code_reloading? do
  # ...
  plug Kunai.Dev.Inbox
end
```

```elixir
# config/dev.exs
config :kunai, egress: [allow_http: true, allow_private: true]
```

The pages then have an **Inbox**, beside the endpoints. An endpoint at
`http://localhost:4000/dev/webhooks/inbox/<name>` receives into the
inbox called `<name>`; the Inbox page adds one for you. Each request is
listed as it arrives: its event, its inbox, whether its signature
verifies with the endpoint's secret, what the inbox answered, and, opened,
its headers and body as they came.

The address says how the inbox answers, to watch what your users' failures
look like:

* `?status=503` answers with that status: the delivery is tried again,
  with the same `webhook-id`, and each try arrives in the inbox.
* `?delay=2000` answers late; past Kunai's timeout (15 seconds,
  `?delay=20000`), the attempt fails as a slow receiver's would.

The inbox keeps the last 200 requests in memory, until the app stops.
Without the plug, there is no Inbox page.

## `mix kunai.trigger`

```sh
$ mix kunai.trigger page.updated --data '{"title": "Porto trip"}'
page.updated evt_01m5wxvwfn000pvyvzb18rf9kr, for notebook
  → http://localhost:4000/dev/webhooks/inbox/search-index  200, delivered
  → http://localhost:4000/dev/webhooks/inbox/archive?status=503  503, tried again later
```

The event is your catalog's example for its type, with `--data` merged
over it, and the system as its actor, to the endpoints that receive it.
When those are several owners', `--owner` says whose. The task shows each
delivery once it has an answer, for up to `--wait` seconds (10): your
app's Oban sends them, in the task or in your running server.

`--dry-run` stores and sends nothing: it prints each request, signed, as
it would go, and a `curl` that sends it, to try a receiver anywhere.

## In your tests

`Kunai.Testing` reads the events your changes emit, in the test's
transaction, and catches the requests Kunai would send:

```elixir
# config/test.exs
config :kunai, transport: Kunai.Testing.Transport
```

```elixir
defmodule MyApp.PagesTest do
  use MyApp.DataCase
  import Kunai.Testing

  test "renaming a page tells the endpoints" do
    {:ok, page} = Pages.update(scope, page, %{title: "Porto trip"})

    event = assert_emitted "page.updated", %{title: "Porto trip"}
    assert event.previous == %{"title" => "Lisbon trip"}
    refute_emitted "page.archived"

    deliver()
    payload = assert_delivered "page.updated", to: endpoint
    assert payload["data"]["object"]["title"] == "Porto trip"
  end

  test "a receiver that fails is tried again" do
    respond(endpoint, [503, 200])
    Pages.archive(scope, page)

    deliver()
    assert_delivered "page.archived", to: endpoint
    deliver(retries: true)
    assert_delivered "page.archived", to: endpoint
  end
end
```

* `assert_emitted/3` and `refute_emitted/3` match an event by its type and
  some of its object's fields; `emitted/2` lists them.
* `deliver/1` runs Kunai's jobs in the test's process; `retries: true`
  makes the deliveries waiting for a retry due first.
* `respond/2` says what an endpoint answers, in turn: statuses,
  `{status, headers}` or `{:error, reason}`.
* `assert_delivered/2` gives a request's payload, decoded; given the
  endpoint (`to:`), it verifies the request's signature with its secret,
  as its receiver would. `refute_delivered/1` asserts none was sent.
