# Making the pages your app's

Kunai's pages ship with a look of their own, neutral and quiet, so that
they sit in an app before it has said anything about them. They are not
meant to stay that way. Each layer below changes more than the one before
it, and costs more to keep; take the first that does what you want.

1. [The tokens](#the-tokens): faces, colours, sizes, radii, spaces.
2. [A mapping](#a-mapping): the tokens from daisyUI's themes or Sumi's.
3. [The frame](#the-frame): your layout around the pages, a line over
   their titles.
4. [The words](#the-words): Kunai's messages in your languages and voice.
5. [Your own page](#your-own-page): one of Kunai's pages copied into your
   app, to change as yours.
6. [Pages of your own](#pages-of-your-own): Kunai's components, or none,
   over its functions.

Each layer leaves the others alone: a copied page still takes the tokens
and the words, and the tokens reach every page.

## The tokens

`kunai.css` draws everything from `--kunai-*` custom properties, declared
under `:where(:root)`, which has no specificity. Set any of them, on
`:root` or on `.kunai`, and yours wins, whatever order the files load in:

```css
@import "../../deps/kunai/priv/static/kunai.css";

.kunai, .kunai-flashes {
  --kunai-font-display: "Iowan Old Style", Georgia, serif;
  --kunai-card-title-font: var(--kunai-font-display);
  --kunai-text: var(--ink);
  --kunai-accent: var(--brand);
  --kunai-primary-background: var(--ink);
  --kunai-radius: 0;
  --kunai-button-radius: 0;
  --kunai-label-transform: uppercase;
  --kunai-label-tracking: 0.12em;
}
```

Point them at your app's own properties (`var(--ink)`) rather than copying
values, and the pages follow your app when it changes. `.kunai-flashes`
is the flash of a page shown without your layout.

Dark mode follows a `dark` class or `data-theme="dark"` on an ancestor, as
most apps switch it. To follow another switch, set the colour tokens under
your own selector.

### Faces and sizes

| Token | Default | What it sets |
| --- | --- | --- |
| `--kunai-font` | system sans-serif | The text of the pages. |
| `--kunai-font-display` | `--kunai-font` | The titles of the pages. |
| `--kunai-font-label` | `--kunai-font` | Labels, column heads, the eyebrow. |
| `--kunai-mono` | system monospace | URLs, ids, event names, code. |
| `--kunai-font-size` | `0.875rem` | The text. |
| `--kunai-small` | `0.8125rem` | Hints and secondary lines. |
| `--kunai-line-height` | `1.5` | The text. |
| `--kunai-title-size` | `1.75rem` | A page's title. |
| `--kunai-title-weight` | `650` | A page's title. |
| `--kunai-title-tracking` | `-0.02em` | A page's title. |
| `--kunai-card-title-font` | `--kunai-font` | A card's title. |
| `--kunai-card-title-size` | `0.9375rem` | A card's title. |
| `--kunai-card-title-weight` | `600` | A card's title. |
| `--kunai-label-size` | `0.75rem` | Labels, column heads, the eyebrow. |
| `--kunai-label-weight` | `500` | Labels. |
| `--kunai-label-transform` | `none` | Labels: `uppercase` for small capitals. |
| `--kunai-label-tracking` | `0` | Labels' letter spacing. |
| `--kunai-eyebrow` | `--kunai-accent` | The colour of the line over a title. |

### Colours

| Token | Default | What it sets |
| --- | --- | --- |
| `--kunai-text` | `#1a1f36` | The text. |
| `--kunai-muted` | `#596780` | Secondary text. |
| `--kunai-faint` | `#8792a2` | Hints, empty values, icons. |
| `--kunai-background` | `transparent` | Behind the pages: your app's, unless set. |
| `--kunai-surface` | `#f6f8fa` | Wells: filters, a delivery's details. |
| `--kunai-raised` | `#ffffff` | Cards, menus, the drawer. |
| `--kunai-border` | `#e3e8ee` | Cards and fields. |
| `--kunai-rule` | `#ebeef1` | Lines inside cards, between rows. |
| `--kunai-hover` | `#f6f8fa` | A row or item under the pointer. |
| `--kunai-selected` | `#f5f4ff` | A row or option chosen. |
| `--kunai-accent` | `#5b5bd6` | Links, focus, active tabs, the primary button. |
| `--kunai-accent-text` | `#ffffff` | Text on the accent. |
| `--kunai-accent-soft` | `#eeeefd` | Chosen chips and options. |
| `--kunai-ok` | `#0e7a44` | Delivered, enabled: text. |
| `--kunai-ok-soft` | `#e3f6ea` | Delivered, enabled: pills. |
| `--kunai-ok-chart` | `#3fb87a` | Delivered: chart bars. |
| `--kunai-wait` | `#a3570a` | Pending, retrying, failing: text. |
| `--kunai-wait-soft` | `#fdf1df` | Pending, retrying, failing: pills, notices. |
| `--kunai-wait-chart` | `#f0ac4b` | Retrying: chart bars. |
| `--kunai-fail` | `#c7302b` | Failed, disabled, danger: text. |
| `--kunai-fail-soft` | `#fdecea` | Failed, disabled: pills, notices. |
| `--kunai-fail-chart` | `#e8584f` | Failed: chart bars. |
| `--kunai-code-background` | `#f6f8fa` | Payloads and code. |
| `--kunai-code-text` | `--kunai-text` | Payloads and code. |

### Shapes

| Token | Default | What it sets |
| --- | --- | --- |
| `--kunai-radius` | `10px` | Cards, the drawer, menus. |
| `--kunai-radius-field` | `7px` | Fields, wells, code. |
| `--kunai-radius-pill` | `999px` | Status pills and chips. |
| `--kunai-border-width` | `1px` | Every border. |
| `--kunai-shadow` | a faint one | Cards. |
| `--kunai-shadow-pop` | a deeper one | Menus and the drawer. |
| `--kunai-focus` | an accent ring | Focused fields and buttons. |

### Buttons

| Token | Default | What it sets |
| --- | --- | --- |
| `--kunai-button-height` | `2.125rem` | Every button. |
| `--kunai-button-radius` | `--kunai-radius-field` | Every button. |
| `--kunai-button-weight` | `550` | Every button's text. |
| `--kunai-button-transform` | `none` | Every button's text. |
| `--kunai-button-tracking` | `0` | Every button's letter spacing. |
| `--kunai-primary-background` | `--kunai-accent` | The primary button. |
| `--kunai-primary-text` | `--kunai-accent-text` | The primary button. |
| `--kunai-primary-hover` | the accent, darker | The primary button under the pointer. |
| `--kunai-secondary-background` | `--kunai-raised` | Other buttons. |
| `--kunai-secondary-border` | `--kunai-border` | Other buttons. |

### Space

| Token | Default | What it sets |
| --- | --- | --- |
| `--kunai-space` | `0.25rem` | The small unit inside parts. |
| `--kunai-gap` | `1.25rem` | Between cards and sections. |
| `--kunai-card-padding` | `1.25rem` | Inside cards. |
| `--kunai-max-width` | `76rem` | The pages' width, inside your layout. |
| `--kunai-drawer-width` | `36rem` | A delivery opened beside its list. |
| `--kunai-transition` | `140ms`, eased | Hovers, the drawer, the chevrons. |

The pages lay themselves out by the room your layout gives them, not by
the window's: in a narrow settings column, an endpoint's side cards go
under its deliveries.

## A mapping

Two files set the tokens from a design system your app already has. Import
one after `kunai.css`:

```css
@import "../../deps/kunai/priv/static/kunai.css";
@import "../../deps/kunai/priv/static/kunai-daisyui.css";
```

* `kunai-daisyui.css` reads daisyUI 5's theme (`--color-base-100`,
  `--color-primary`, `--radius-box`, …): the pages change with your theme,
  dark ones included.
* `kunai-sumi.css` reads Sumi's tokens (`--sumi-ink`, `--sumi-accent`,
  `--sumi-font`, …).

Set tokens after the mapping to change it further.

## The frame

The mount puts the pages inside your app, as your own pages are:

```elixir
kunai "/settings/webhooks",
  on_mount: [{MyAppWeb.UserAuth, :require_authenticated}, MyAppWeb.Locale],
  app_layout: {MyAppWeb.Layouts, :settings},
  eyebrow: "Settings"
```

* `app_layout` is a component of yours, given `flash`, `current_scope`
  and the page as its inner block: your header and navigation, your
  settings' sidebar, your flash. Without it, the pages render in your
  root layout alone, with a flash of their own.
* `eyebrow` is the line over each page's title, as your other settings
  pages have one.
* `on_mount` runs your hooks before the pages: the scope, and anything
  else your pages set, such as the locale.

## The words

Every message of the pages goes through `Kunai.Text`. Name your Gettext
backend and they are looked up in its `kunai` domain:

```elixir
config :kunai, gettext: MyAppWeb.Gettext
```

```sh
cp deps/kunai/priv/gettext/kunai.pot priv/gettext/
mix gettext.merge priv/gettext
```

Each language then has a `kunai.po` to translate. English needs none,
unless you want other words: a `priv/gettext/en/LC_MESSAGES/kunai.po` that
says "Destinations" where Kunai says "Endpoints" changes them. A message
left untranslated stays Kunai's.

The language is the one your `on_mount` hooks set for the page's process
(`Gettext.put_locale/2`), as for your own LiveViews.

## Your own page

When a page should have other parts, in another order, copy it into your
app:

```sh
mix kunai.gen.live --only show --path /settings/webhooks \
  --layout MyAppWeb.Layouts.settings --eyebrow Settings
```

`lib/my_app_web/live/webhooks_live/show.ex` is then yours: an ordinary
LiveView on `Kunai.Live.Page`, built of `Kunai.Components`, calling
`Kunai`'s functions. Route it before the mount, which keeps the other
pages:

```elixir
live_session :webhooks, on_mount: [{MyAppWeb.UserAuth, :require_authenticated}] do
  live "/settings/webhooks/endpoints/:id", MyAppWeb.WebhooksLive.Show, :show
end

kunai "/settings/webhooks", on_mount: [{MyAppWeb.UserAuth, :require_authenticated}]
```

No two of Kunai's routes match the same path, so yours takes over that
page and no other, wherever it sits before the mount. The pages link to
each other through `Kunai.Components.endpoint_path/2` and its siblings,
so your page and Kunai's still find each other.

What was copied is the page, not Kunai: its functions, components and
tokens are still Kunai's, and upgrades still reach them. After an
upgrade, the CHANGELOG says when a page changed, should you want to copy
it again (`--force`).

Without `--only`, all four pages are copied: `index`, `show`, `form` and
`delivery`.

## Pages of your own

The pages are made of `Kunai.Components`, public and documented: the
endpoints table, the deliveries table, a delivery with its attempts, the
endpoint form, charts, cards, buttons. A page of yours can use them on
`Kunai.Live.Page`, which assigns `@kunai` (the scope, where the pages are,
your layout) and imports them:

```elixir
defmodule MyAppWeb.IntegrationsLive do
  use Kunai.Live.Page, base: "/settings/webhooks", app_layout: {MyAppWeb.Layouts, :app}

  def mount(_params, _session, socket) do
    scope = socket.assigns.kunai_scope

    {:ok,
     assign(socket,
       endpoints: Kunai.list_endpoints(scope).data,
       stats: Kunai.Stats.by_endpoint(scope)
     )}
  end

  def render(assigns) do
    ~H"""
    <.page kunai={@kunai} flash={@flash}>
      <.header title="Integrations" />
      <.card flush>
        <.endpoints_table endpoints={@endpoints} stats={@stats} base={@kunai.base} />
      </.card>
    </.page>
    """
  end
end
```

Or none of them: everything the pages do is a function of `Kunai`
(`list_endpoints/2`, `create_endpoint/3`, `list_deliveries/2`,
`retry_delivery/2`, `send_test/3`, `roll_secret/3`, `subscribe/1`,
`Kunai.Stats`, …), the same the pages and the REST API call, so pages in
your own components, or a React app over the API, are as able as Kunai's.
