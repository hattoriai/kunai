defmodule Kunai.Components do
  @moduledoc """
  The pieces of Kunai's pages, for an app's own pages too.

  Kunai's pages are these components and little else (`Kunai.Live.Page`):
  an app that wants its own page of webhooks puts them in its own
  LiveView, in its own order, beside its own markup, or copies Kunai's
  pages to change them (`mix kunai.gen.live`).

  They are styled by `kunai.css` (`.kunai-*` classes), every colour,
  face, size, radius and shadow a `--kunai-*` property the app may set
  (see the Theming guide). Words go through `Kunai.Text`.

  ## Pieces

    * Layout: `page/1`, `header/1`, `card/1`, `properties/1`,
      `notice/1`, `empty_state/1`.
    * Controls: `button/1`, `menu/1`, `copy/1`, `tabs/1`.
    * Values: `status/1`, `metric/1`, `bar_chart/1`, `time/1`,
      `secret/1`, `code/1`.
    * Webhooks: `endpoints_table/1`, `deliveries_table/1`,
      `delivery_detail/1`, `attempts/1`, `endpoint_form/1`,
      `verify_snippet/1`.
  """

  use Phoenix.Component

  import Kunai.Icons
  import Kunai.Text

  alias Phoenix.LiveView.JS

  # Layout

  @doc """
  A page: in the app's layout component when there is one (`@kunai`'s
  `app_layout`), given `flash` and `current_scope`.
  """
  attr(:kunai, Kunai.Live.Page, required: true)
  attr(:flash, :map, default: %{})
  attr(:class, :any, default: nil)
  slot(:inner_block, required: true)

  def page(assigns) do
    ~H"""
    <%= case @kunai.app_layout do %>
      <% {module, fun} -> %>
        {apply(module, fun, [
          %{
            __changed__: nil,
            flash: @flash,
            current_scope: @kunai.scope,
            inner_block: [%{__slot__: :inner_block, inner_block: fn _changed, _arg -> body(assigns) end}]
          }
        ])}
      <% nil -> %>
        <.flash_group flash={@flash} />
        {body(assigns)}
    <% end %>
    """
  end

  defp body(assigns) do
    ~H"""
    <div class={["kunai", @class]}>{render_slot(@inner_block)}</div>
    """
  end

  @doc "The flash of a page, when the app's layout does not show it."
  attr(:flash, :map, required: true)

  def flash_group(assigns) do
    ~H"""
    <div :if={@flash != %{}} class="kunai kunai-flashes">
      <p
        :for={{kind, message} <- @flash}
        class={"kunai-flash kunai-flash--#{kind}"}
        role={if kind == "error", do: "alert", else: "status"}
        phx-click={JS.push("lv:clear-flash", value: %{key: kind}) |> JS.hide()}
      >
        <.icon name={if kind == "error", do: "alert", else: "check"} />
        <span>{message}</span>
      </p>
    </div>
    """
  end

  @doc "The head of a page: a line above (the eyebrow), its title, a line under it, its actions."
  attr(:title, :string, required: true)
  attr(:eyebrow, :string, default: nil)
  attr(:back, :string, default: nil)
  attr(:back_label, :string, default: nil)
  slot(:subtitle)
  slot(:badge)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class="kunai-header">
      <nav :if={@back} class="kunai-crumbs" aria-label={t("Breadcrumb")}>
        <.link navigate={@back} class="kunai-crumb">
          <.icon name="arrow-left" />{@back_label || t("Webhooks")}
        </.link>
      </nav>
      <div class="kunai-header-row">
        <div class="kunai-header-text">
          <p :if={@eyebrow} class="kunai-eyebrow">{@eyebrow}</p>
          <div class="kunai-title-row">
            <h1 class="kunai-title">{@title}</h1>
            {render_slot(@badge)}
          </div>
          <div :if={@subtitle != []} class="kunai-subtitle">{render_slot(@subtitle)}</div>
        </div>
        <div :if={@actions != []} class="kunai-actions">{render_slot(@actions)}</div>
      </div>
    </header>
    """
  end

  @doc "A card: a titled box of a page."
  attr(:title, :string, default: nil)
  attr(:id, :string, default: nil)
  attr(:class, :any, default: nil)
  attr(:flush, :boolean, default: false, doc: "its content to its edges (a table)")
  slot(:description)
  slot(:actions)
  slot(:inner_block, required: true)
  slot(:footer)

  def card(assigns) do
    ~H"""
    <section class={["kunai-card", @flush && "kunai-card--flush", @class]} id={@id}>
      <div :if={@title || @actions != []} class="kunai-card-head">
        <div>
          <h2 :if={@title} class="kunai-card-title">{@title}</h2>
          <p :if={@description != []} class="kunai-card-description">{render_slot(@description)}</p>
        </div>
        <div :if={@actions != []} class="kunai-actions">{render_slot(@actions)}</div>
      </div>
      <div class="kunai-card-body">{render_slot(@inner_block)}</div>
      <div :if={@footer != []} class="kunai-card-foot">{render_slot(@footer)}</div>
    </section>
    """
  end

  @doc "Labelled values, in a column (a card's details)."
  slot :item, required: true do
    attr(:label, :string, required: true)
  end

  def properties(assigns) do
    ~H"""
    <dl class="kunai-properties">
      <div :for={item <- @item} class="kunai-property">
        <dt>{item.label}</dt>
        <dd>{render_slot(item)}</dd>
      </div>
    </dl>
    """
  end

  @doc "A line that asks for attention: `info`, `warning` or `danger`."
  attr(:kind, :string, default: "info", values: ~w(info warning danger))
  attr(:title, :string, default: nil)
  slot(:inner_block, required: true)
  slot(:actions)

  def notice(assigns) do
    ~H"""
    <div class={"kunai-notice kunai-notice--#{@kind}"} role={if @kind == "danger", do: "alert", else: "status"}>
      <.icon name={if @kind == "info", do: "clock", else: "alert"} class="kunai-notice-icon" />
      <div class="kunai-notice-text">
        <p :if={@title} class="kunai-notice-title">{@title}</p>
        <p>{render_slot(@inner_block)}</p>
      </div>
      <div :if={@actions != []} class="kunai-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc "What a page shows when it has nothing yet."
  attr(:title, :string, required: true)
  attr(:icon, :string, default: "hook")
  slot(:inner_block)
  slot(:actions)

  def empty_state(assigns) do
    ~H"""
    <div class="kunai-empty">
      <span class="kunai-empty-icon"><.icon name={@icon} /></span>
      <p class="kunai-empty-title">{@title}</p>
      <div :if={@inner_block != []} class="kunai-empty-text">{render_slot(@inner_block)}</div>
      <div :if={@actions != []} class="kunai-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  # Controls

  @doc """
  A button, or a link that looks like one with `navigate`, `patch` or
  `href`. `variant`: `primary`, `secondary` (the default), `danger` or
  `ghost`; `size`: `md` or `sm`.
  """
  attr(:variant, :string, default: "secondary", values: ~w(primary secondary danger ghost))
  attr(:size, :string, default: "md", values: ~w(md sm))
  attr(:icon, :string, default: nil)
  attr(:navigate, :string, default: nil)
  attr(:patch, :string, default: nil)
  attr(:href, :string, default: nil)
  attr(:class, :any, default: nil)
  attr(:type, :string, default: "button")
  attr(:rest, :global, include: ~w(disabled form name value data-confirm phx-disable-with))
  slot(:inner_block)

  def button(assigns) do
    assigns =
      assign(assigns, :classes, [
        "kunai-button",
        "kunai-button--#{assigns.variant}",
        assigns.size == "sm" && "kunai-button--sm",
        assigns.inner_block == [] && "kunai-button--icon",
        assigns.class
      ])

    if assigns.navigate || assigns.patch || assigns.href do
      ~H"""
      <.link navigate={@navigate} patch={@patch} href={@href} class={@classes} {@rest}>
        <.icon :if={@icon} name={@icon} />{render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button type={@type} class={@classes} {@rest}>
        <.icon :if={@icon} name={@icon} />{render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  A menu of actions behind a button. Each item takes `navigate`, or
  `click` (an event or a `Phoenix.LiveView.JS`), `confirm` and `danger`.
  """
  attr(:id, :string, required: true)
  attr(:label, :string, default: nil)

  slot :item, required: true do
    attr(:navigate, :string)
    attr(:click, :any)
    attr(:confirm, :string)
    attr(:danger, :boolean)
    attr(:icon, :string)
  end

  def menu(assigns) do
    ~H"""
    <div
      class="kunai-menu"
      id={@id}
      phx-click-away={JS.hide(to: "##{@id}-list")}
      phx-window-keydown={JS.hide(to: "##{@id}-list")}
      phx-key="Escape"
    >
      <button
        type="button"
        class="kunai-button kunai-button--secondary kunai-button--icon"
        aria-haspopup="menu"
        aria-label={@label || t("More actions")}
        phx-click={JS.toggle(to: "##{@id}-list")}
      >
        <.icon name="more" />
      </button>
      <div id={"#{@id}-list"} class="kunai-menu-list" role="menu" style="display: none">
        <%= for item <- @item do %>
          <.link
            :if={item[:navigate]}
            navigate={item[:navigate]}
            class={["kunai-menu-item", item[:danger] && "kunai-menu-item--danger"]}
            role="menuitem"
          >
            <.icon :if={item[:icon]} name={item[:icon]} />{render_slot(item)}
          </.link>
          <button
            :if={!item[:navigate]}
            type="button"
            class={["kunai-menu-item", item[:danger] && "kunai-menu-item--danger"]}
            role="menuitem"
            phx-click={item[:click] && item[:click] |> to_js() |> JS.hide(to: "##{@id}-list")}
            data-confirm={item[:confirm]}
          >
            <.icon :if={item[:icon]} name={item[:icon]} />{render_slot(item)}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp to_js(%JS{} = js), do: js
  defp to_js(event) when is_binary(event), do: JS.push(event)

  @doc """
  A button that copies its value. It shows once `kunai.js` is in the
  app's JavaScript (`import "../../deps/kunai/priv/static/kunai.js"`).
  """
  attr(:value, :string, required: true)
  attr(:label, :string, default: nil)

  def copy(assigns) do
    ~H"""
    <button
      type="button"
      class="kunai-copy"
      data-copy={@value}
      phx-click={JS.dispatch("kunai:copy")}
      aria-label={@label || t("Copy")}
      title={@label || t("Copy")}
    >
      <.icon name="copy" class="kunai-copy-idle" /><.icon name="check" class="kunai-copy-done" />
      <span :if={@label}>{@label}</span>
    </button>
    """
  end

  @doc "Tabs over panels, switched in the browser."
  attr(:id, :string, required: true)

  slot :tab, required: true do
    attr(:label, :string, required: true)
  end

  def tabs(assigns) do
    assigns = assign(assigns, :count, length(assigns.tab))

    ~H"""
    <div class="kunai-tabs" id={@id}>
      <div class="kunai-tab-list" role="tablist">
        <button
          :for={{tab, index} <- Enum.with_index(@tab)}
          type="button"
          role="tab"
          id={"#{@id}-tab-#{index}"}
          class={["kunai-tab", index == 0 && "is-active"]}
          phx-click={select_tab(@id, index, @count)}
        >
          {tab.label}
        </button>
      </div>
      <div
        :for={{tab, index} <- Enum.with_index(@tab)}
        id={"#{@id}-panel-#{index}"}
        class="kunai-tab-panel"
        role="tabpanel"
        style={index != 0 && "display: none"}
      >
        {render_slot(tab)}
      </div>
    </div>
    """
  end

  defp select_tab(id, selected, count) do
    Enum.reduce(0..(count - 1), %JS{}, fn index, js ->
      if index == selected do
        js
        |> JS.show(to: "##{id}-panel-#{index}")
        |> JS.add_class("is-active", to: "##{id}-tab-#{index}")
      else
        js
        |> JS.hide(to: "##{id}-panel-#{index}")
        |> JS.remove_class("is-active", to: "##{id}-tab-#{index}")
      end
    end)
  end

  # Values

  @doc "The status of an endpoint or a delivery, as a pill."
  attr(:status, :string, required: true)
  attr(:label, :string, default: nil)

  def status(assigns) do
    ~H"""
    <span class={"kunai-pill kunai-pill--#{tone(@status)}"}>{@label || status_label(@status)}</span>
    """
  end

  @doc """
  The paths of the pages under `base` (`@kunai.base`): every route is its
  own, so an app's route for one, before the mount, takes it over.
  """
  def new_endpoint_path(base), do: "#{base}/new"

  @doc "The path of an endpoint's page. See `new_endpoint_path/1`."
  def endpoint_path(base, %{id: id}), do: endpoint_path(base, id)
  def endpoint_path(base, id) when is_binary(id), do: "#{base}/endpoints/#{id}"

  @doc "The path of an endpoint's form. See `new_endpoint_path/1`."
  def edit_endpoint_path(base, endpoint), do: endpoint_path(base, endpoint) <> "/edit"

  @doc "The path of a delivery's page. See `new_endpoint_path/1`."
  def delivery_path(base, %{id: id}), do: "#{base}/deliveries/#{id}"

  @doc "The tone of a status, for its pill and colours: `ok`, `wait`, `fail` or `muted`."
  def tone(status) when status in ["enabled", "succeeded"], do: "ok"
  def tone(status) when status in ["pending", "failing"], do: "wait"
  def tone(status) when status in ["disabled", "failed"], do: "fail"
  def tone(_status), do: "muted"

  @doc "The words for a status, an endpoint's or a delivery's."
  def status_label("enabled"), do: t("Enabled")
  def status_label("disabled"), do: t("Disabled")
  def status_label("succeeded"), do: t("Delivered")
  def status_label("pending"), do: t("Pending")
  def status_label("failed"), do: t("Failed")
  def status_label("failing"), do: t("Failing")
  def status_label(other), do: other

  @doc """
  An endpoint's status as the pages show it: `failing` when it is enabled
  but its deliveries fail, else its own.
  """
  def endpoint_status(%{status: "enabled", failing_since: %DateTime{}}), do: "failing"
  def endpoint_status(endpoint), do: endpoint.status

  @doc "A number with its label, and a chart under it."
  attr(:label, :string, required: true)
  attr(:value, :string, required: true)
  attr(:hint, :string, default: nil)
  attr(:tone, :string, default: nil)
  slot(:inner_block)

  def metric(assigns) do
    ~H"""
    <div class="kunai-metric">
      <p class="kunai-metric-label">{@label}</p>
      <p class={["kunai-metric-value", @tone && "kunai-metric-value--#{@tone}"]}>{@value}</p>
      <p :if={@hint} class="kunai-metric-hint">{@hint}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  The deliveries of each hour as bars (`Kunai.Stats`): delivered, failed,
  retrying and not tried yet, stacked. `size`: `mini` (a row's) or `full`, with its
  hours under it.
  """
  attr(:hours, :list, required: true)
  attr(:size, :string, default: "full", values: ~w(mini full))
  attr(:label, :string, default: nil)

  def bar_chart(assigns) do
    {bar, gap, height} = if assigns.size == "mini", do: {4, 2, 24}, else: {14, 6, 96}

    top =
      assigns.hours
      |> Enum.map(&(&1.succeeded + &1.failed + &1.retrying + &1.pending))
      |> Enum.max(fn -> 0 end)
      |> max(1)

    scale = fn count -> if count > 0, do: max(round(count / top * height), 2), else: 0 end

    bars =
      assigns.hours
      |> Enum.with_index()
      |> Enum.map(fn {hour, index} ->
        ok = scale.(hour.succeeded)
        failed = scale.(hour.failed)
        retrying = scale.(hour.retrying)
        pending = scale.(hour.pending)

        %{
          x: index * (bar + gap),
          title: hour_title(hour),
          parts: [
            {"kunai-chart-ok", height - ok, ok},
            {"kunai-chart-fail", height - ok - failed, failed},
            {"kunai-chart-wait", height - ok - failed - retrying, retrying},
            {"kunai-chart-pending", height - ok - failed - retrying - pending, pending}
          ]
        }
      end)

    assigns =
      assign(assigns,
        bars: bars,
        bar: bar,
        height: height,
        width: max(length(assigns.hours) * (bar + gap) - gap, 1),
        ticks: ticks(assigns.hours)
      )

    ~H"""
    <figure class={["kunai-chart", "kunai-chart--#{@size}"]}>
      <svg
        viewBox={"0 0 #{@width} #{@height}"}
        preserveAspectRatio="none"
        role="img"
        aria-label={@label || t("Deliveries by hour")}
      >
        <g :for={bar <- @bars}>
          <title>{bar.title}</title>
          <rect class="kunai-chart-track" x={bar.x} y="0" width={@bar} height={@height} rx="1.5" />
          <%= for {class, y, h} <- bar.parts, h > 0 do %>
            <rect class={class} x={bar.x} y={y} width={@bar} height={h} rx="1.5" />
          <% end %>
        </g>
      </svg>
      <figcaption :if={@size == "full"} class="kunai-chart-ticks">
        <span :for={tick <- @ticks}>{tick}</span>
      </figcaption>
    </figure>
    """
  end

  defp ticks([]), do: []

  defp ticks(hours) do
    [clock(hd(hours).at), clock(Enum.at(hours, div(length(hours), 2)).at), t("Now")]
  end

  defp hour_title(hour) do
    t("%{time}: %{ok} delivered, %{failed} failed, %{retrying} retrying, %{pending} pending",
      time: clock(hour.at),
      ok: hour.succeeded,
      failed: hour.failed,
      retrying: hour.retrying,
      pending: hour.pending
    )
  end

  defp clock(at), do: Calendar.strftime(at, "%H:00")

  @doc "A time, relative to now, its full value on hover."
  attr(:at, :any, required: true)

  def time(%{at: nil} = assigns) do
    ~H"""
    <span class="kunai-faint">—</span>
    """
  end

  def time(assigns) do
    ~H"""
    <time datetime={DateTime.to_iso8601(@at)} title={Calendar.strftime(@at, "%Y-%m-%d %H:%M:%S UTC")}>
      {ago(@at)}
    </time>
    """
  end

  @doc ~s(A time relative to now: "3m ago", "in 4m".)
  def ago(at) do
    seconds = DateTime.diff(DateTime.utc_now(), at)

    cond do
      seconds < 0 -> t("in %{span}", span: span(-seconds))
      seconds < 45 -> t("just now")
      true -> t("%{span} ago", span: span(seconds))
    end
  end

  defp span(s) when s < 90, do: "#{max(s, 1)}s"
  defp span(s) when s < 5_400, do: "#{div(s, 60)}m"
  defp span(s) when s < 129_600, do: "#{div(s, 3_600)}h"
  defp span(s), do: "#{div(s, 86_400)}d"

  @doc "A secret: shown with a button to copy it, or hidden, its prefix and dots."
  attr(:id, :string, required: true)
  attr(:value, :string, default: nil)
  attr(:prefix, :string, default: "whsec_")

  def secret(assigns) do
    ~H"""
    <div class="kunai-secret" id={@id}>
      <code :if={@value} class="kunai-secret-value">{@value}</code>
      <code :if={!@value} class="kunai-secret-value kunai-secret-value--hidden" aria-label={t("Hidden")}>
        {@prefix}••••••••••••••••••••••••
      </code>
      <.copy :if={@value} value={@value} />
    </div>
    """
  end

  @doc "A JSON value, indented, with a button to copy it."
  attr(:value, :any, required: true)
  attr(:id, :string, default: nil)

  def code(assigns) do
    assigns = assign(assigns, :json, Kunai.Pretty.json(assigns.value))

    ~H"""
    <div class="kunai-code" id={@id}>
      <.copy value={@json} />
      <pre><code>{@json}</code></pre>
    </div>
    """
  end

  # Webhooks

  @doc """
  An owner's endpoints, each with its deliveries of the last day (the
  map of `Kunai.Stats.by_endpoint/2`), each row a link to its page under
  `base`.
  """
  attr(:endpoints, :list, required: true)
  attr(:stats, :map, default: %{})
  attr(:base, :string, required: true)
  attr(:id, :string, default: "kunai-endpoints")

  def endpoints_table(assigns) do
    ~H"""
    <div class="kunai-table-wrap">
      <table class="kunai-table kunai-table--rows" id={@id}>
        <thead>
          <tr>
            <th>{t("Endpoint")}</th>
            <th>{t("Status")}</th>
            <th>{t("Events")}</th>
            <th class="kunai-col-chart">{t("Last 24 hours")}</th>
            <th class="kunai-col-end"><span class="kunai-sr">{t("Open")}</span></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={endpoint <- @endpoints} id={endpoint.id}>
            <td>
              <.link navigate={endpoint_path(@base, endpoint)} class="kunai-row-link">
                <span class="kunai-mono kunai-strong">{endpoint.url}</span>
              </.link>
              <p :if={endpoint.description} class="kunai-muted kunai-small">{endpoint.description}</p>
            </td>
            <td><.status status={endpoint_status(endpoint)} /></td>
            <td class="kunai-muted">{events_summary(endpoint.events)}</td>
            <td class="kunai-col-chart"><.endpoint_activity stats={@stats[endpoint.id]} /></td>
            <td class="kunai-col-end"><.icon name="chevron-right" class="kunai-faint" /></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:stats, :map, default: nil)

  defp endpoint_activity(%{stats: nil} = assigns) do
    ~H"""
    <span class="kunai-faint kunai-small">{t("No deliveries")}</span>
    """
  end

  defp endpoint_activity(assigns) do
    ~H"""
    <div class="kunai-activity">
      <.bar_chart hours={@stats.hours} size="mini" />
      <span class={["kunai-activity-rate", @stats.failed + @stats.retrying > 0 && "kunai-text-fail"]}>
        {error_rate(@stats)}
      </span>
    </div>
    """
  end

  @doc "The share of deliveries tried that did not succeed (`Kunai.Stats`), as words."
  def error_rate(%{success_rate: nil}), do: "—"

  def error_rate(%{success_rate: rate}),
    do: t("%{rate}% errors", rate: format_number(Float.round((1 - rate) * 100, 1)))

  @doc "How many deliveries failed or are retrying (`Kunai.Stats`), as words."
  def failures_hint(%{failed: 0, retrying: 0}), do: t("None failed")

  def failures_hint(%{failed: failed, retrying: 0}),
    do: tn("%{count} failed", "%{count} failed", failed)

  def failures_hint(%{failed: 0, retrying: retrying}),
    do: tn("%{count} retrying", "%{count} retrying", retrying)

  def failures_hint(%{failed: failed, retrying: retrying}),
    do: t("%{failed} failed, %{retrying} retrying", failed: failed, retrying: retrying)

  @doc "The share of deliveries tried that succeeded (`Kunai.Stats`), as a percentage."
  def success_rate(%{success_rate: nil}), do: "—"
  def success_rate(%{success_rate: rate}), do: "#{format_number(Float.round(rate * 100, 1))}%"

  defp format_number(float) when float == trunc(float), do: Integer.to_string(trunc(float))
  defp format_number(float), do: :erlang.float_to_binary(float, decimals: 1)

  @doc "An endpoint's `:events`, in a few words."
  def events_summary(["*"]), do: t("All events")
  def events_summary([one]), do: one
  def events_summary(events), do: tn("%{count} event", "%{count} events", length(events))

  @doc """
  Deliveries, newest first. Each row opens the delivery: patched to
  `?delivery=<id>` with `patch` (a panel of the same page), else its page
  under `base`.
  """
  attr(:deliveries, :list, required: true)
  attr(:base, :string, required: true)
  attr(:patch, :string, default: nil, doc: "the path the rows patch to, with ?delivery=")
  attr(:selected, :string, default: nil)
  attr(:id, :string, default: "kunai-deliveries-table")

  def deliveries_table(assigns) do
    ~H"""
    <div class="kunai-table-wrap">
      <table class="kunai-table kunai-table--rows" id={@id}>
        <thead>
          <tr>
            <th>{t("Event")}</th>
            <th>{t("Status")}</th>
            <th>{t("Response")}</th>
            <th class="kunai-col-num">{t("Attempts")}</th>
            <th class="kunai-col-when">{t("Created")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={delivery <- @deliveries} id={delivery.id} class={[@selected == delivery.id && "is-selected"]}>
            <td>
              <.link :if={@patch} patch={"#{@patch}?delivery=#{delivery.id}"} class="kunai-row-link">
                <span class="kunai-mono kunai-strong">{delivery.event_type}</span>
              </.link>
              <.link :if={!@patch} navigate={delivery_path(@base, delivery)} class="kunai-row-link">
                <span class="kunai-mono kunai-strong">{delivery.event_type}</span>
              </.link>
              <p class="kunai-mono kunai-faint kunai-small kunai-truncate">{delivery.event_id}</p>
            </td>
            <td><.status status={delivery.status} /></td>
            <td><.response_code delivery={delivery} /></td>
            <td class="kunai-col-num">{delivery.attempts}</td>
            <td class="kunai-col-when kunai-muted"><.time at={delivery.inserted_at} /></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr(:delivery, :map, required: true)

  defp response_code(%{delivery: %{last_status_code: code}} = assigns) when is_integer(code) do
    ~H"""
    <.code_pill code={@delivery.last_status_code} />
    """
  end

  defp response_code(%{delivery: %{last_error: error}} = assigns) when is_binary(error) do
    ~H"""
    <span class="kunai-text-fail kunai-small kunai-mono">{@delivery.last_error}</span>
    """
  end

  defp response_code(assigns) do
    ~H"""
    <span class="kunai-faint">—</span>
    """
  end

  attr(:code, :integer, required: true)

  defp code_pill(assigns) do
    ~H"""
    <span class={["kunai-code-pill", if(@code in 200..299, do: "kunai-code-pill--ok", else: "kunai-code-pill--fail")]}>
      {@code}
    </span>
    """
  end

  @doc """
  A delivery: what it is, each attempt, and the request and response of the
  latest. `payload` is what the endpoint received (`Kunai.Payload.build/3`).
  The `actions` slot holds its buttons (Send again).
  """
  attr(:delivery, :map, required: true)
  attr(:endpoint, :map, required: true)
  attr(:payload, :map, default: nil)
  attr(:id, :string, default: "kunai-delivery")
  slot(:actions)

  def delivery_detail(assigns) do
    assigns = assign(assigns, :latest, List.last(assigns.delivery.attempt_log || []))

    ~H"""
    <article class="kunai-delivery" id={@id}>
      <header class="kunai-delivery-head">
        <div>
          <div class="kunai-title-row">
            <h2 class="kunai-delivery-title kunai-mono">{@delivery.event_type}</h2>
            <.status status={@delivery.status} />
          </div>
          <p class="kunai-muted kunai-small">
            {t("To")} <span class="kunai-mono">{@endpoint.url}</span>
          </p>
        </div>
        <div :if={@actions != []} class="kunai-actions">{render_slot(@actions)}</div>
      </header>

      <.properties>
        <:item label="webhook-id">
          <span class="kunai-inline-copy">
            <span class="kunai-mono kunai-truncate">{@delivery.id}</span><.copy value={@delivery.id} />
          </span>
        </:item>
        <:item label={t("Event")}>
          <span class="kunai-inline-copy">
            <span class="kunai-mono kunai-truncate">{@delivery.event_id}</span><.copy value={@delivery.event_id} />
          </span>
        </:item>
        <:item :if={@delivery.status == "pending" and @delivery.next_attempt_at} label={t("Next attempt")}>
          <.time at={@delivery.next_attempt_at} />
        </:item>
        <:item label={t("Created")}><.time at={@delivery.inserted_at} /></:item>
      </.properties>

      <section class="kunai-delivery-section">
        <h3 class="kunai-section-label">{t("Attempts")}</h3>
        <.attempts
          attempts={@delivery.attempt_log || []}
          next={@delivery.status == "pending" && @delivery.next_attempt_at}
        />
      </section>

      <section class="kunai-delivery-section">
        <.tabs id={"#{@id}-exchange"}>
          <:tab label={t("Request")}>
            <.request_headers delivery={@delivery} attempt={@latest} />
            <.code :if={@payload} value={@payload} id={"#{@id}-payload"} />
          </:tab>
          <:tab label={t("Response")}>
            <p :if={is_nil(@latest)} class="kunai-muted">{t("Not tried yet.")}</p>
            <div :if={@latest} class="kunai-response">
              <p class="kunai-response-line">
                <.code_pill :if={@latest.status_code} code={@latest.status_code} />
                <span :if={@latest.error} class="kunai-text-fail">{@latest.error}</span>
                <span class="kunai-muted">{t("in %{ms} ms", ms: @latest.duration_ms)}</span>
              </p>
              <pre :if={@latest.response_body not in [nil, ""]} class="kunai-pre">{@latest.response_body}</pre>
              <p :if={@latest.response_body in [nil, ""]} class="kunai-muted">{t("No body.")}</p>
            </div>
          </:tab>
        </.tabs>
      </section>
    </article>
    """
  end

  attr(:delivery, :map, required: true)
  attr(:attempt, :any, default: nil)

  defp request_headers(assigns) do
    timestamp = if assigns.attempt, do: DateTime.to_unix(assigns.attempt.created_at), else: "—"

    assigns =
      assign(assigns, :headers, [
        {"content-type", "application/json"},
        {"webhook-id", assigns.delivery.id},
        {"webhook-timestamp", to_string(timestamp)},
        {"webhook-signature", "v1,…"}
      ])

    ~H"""
    <dl class="kunai-headers">
      <div :for={{name, value} <- @headers}>
        <dt class="kunai-mono">{name}</dt>
        <dd class="kunai-mono">{value}</dd>
      </div>
    </dl>
    """
  end

  @doc "A delivery's attempts, newest first, as a timeline, with the next one to come."
  attr(:attempts, :list, required: true)
  attr(:next, :any, default: nil)

  def attempts(assigns) do
    ~H"""
    <ol class="kunai-timeline">
      <li :if={@next} class="kunai-timeline-item kunai-timeline-item--next">
        <span class="kunai-timeline-dot"></span>
        <div class="kunai-timeline-body">
          <p>{t("Next attempt")} <span class="kunai-muted"><.time at={@next} /></span></p>
        </div>
      </li>
      <li
        :for={attempt <- Enum.reverse(@attempts)}
        class={["kunai-timeline-item", "kunai-timeline-item--#{attempt_tone(attempt)}"]}
      >
        <span class="kunai-timeline-dot"></span>
        <div class="kunai-timeline-body">
          <p>
            <span class="kunai-strong">{t("Attempt %{n}", n: attempt.number)}</span>
            <.code_pill :if={attempt.status_code} code={attempt.status_code} />
            <span :if={attempt.error} class="kunai-text-fail kunai-small kunai-mono">{attempt.error}</span>
          </p>
          <p class="kunai-muted kunai-small">
            <.time at={attempt.created_at} /> · {t("%{ms} ms", ms: attempt.duration_ms)}
          </p>
        </div>
      </li>
      <li :if={@attempts == [] and !@next} class="kunai-timeline-item">
        <span class="kunai-timeline-dot"></span>
        <div class="kunai-timeline-body"><p class="kunai-muted">{t("Not tried yet.")}</p></div>
      </li>
    </ol>
    """
  end

  defp attempt_tone(%{status_code: code}) when code in 200..299, do: "ok"
  defp attempt_tone(_attempt), do: "fail"

  @doc """
  How the receiver checks a request's signature, in the languages of
  Standard Webhooks' libraries.
  """
  attr(:id, :string, default: "kunai-verify")
  attr(:ed25519, :boolean, default: false)

  def verify_snippet(assigns) do
    ~H"""
    <.tabs id={@id}>
      <:tab label="Elixir">
        <pre class="kunai-pre"><code>{elixir_snippet()}</code></pre>
      </:tab>
      <:tab label="Node.js">
        <pre class="kunai-pre"><code>{node_snippet()}</code></pre>
      </:tab>
      <:tab label="Python">
        <pre class="kunai-pre"><code>{python_snippet()}</code></pre>
      </:tab>
    </.tabs>
    <p class="kunai-hint">
      {if @ed25519,
        do:
          t(
            "Signed with Ed25519: verify with the public key (whpk_), with Kunai.Verifier or another library that supports v1a."
          ),
        else:
          t(
            "Requests follow Standard Webhooks: its libraries verify them in any language. Verify the raw body, before parsing it."
          )}
    </p>
    """
  end

  defp elixir_snippet do
    ~S"""
    # A plug for the webhook's route:
    plug Kunai.Plug.Verify,
      secrets: [System.fetch_env!("WEBHOOK_SECRET")]

    # or by hand, with the raw body:
    :ok = Kunai.Verifier.verify(raw_body, conn.req_headers, [secret])
    """
  end

  defp node_snippet do
    ~S"""
    import { Webhook } from "standardwebhooks";

    const wh = new Webhook(process.env.WEBHOOK_SECRET);
    const event = wh.verify(rawBody, request.headers);
    """
  end

  defp python_snippet do
    ~S"""
    from standardwebhooks.webhooks import Webhook

    wh = Webhook(os.environ["WEBHOOK_SECRET"])
    event = wh.verify(raw_body, request.headers)
    """
  end

  @doc """
  The form of an endpoint. `form` is of a `Kunai.Endpoint` changeset (as
  `:endpoint`); `families` the catalog's events by family; `query` the
  words that filter them. The parent handles `"validate"` and `"save"`.
  """
  attr(:form, Phoenix.HTML.Form, required: true)
  attr(:families, :list, required: true)
  attr(:grantable, :list, default: [])
  attr(:versions, :list, default: [])
  attr(:signing, :string, default: "hmac")
  attr(:new?, :boolean, default: true)
  attr(:query, :string, default: "")
  attr(:cancel, :string, required: true)
  attr(:id, :string, default: "kunai-endpoint-form")

  def endpoint_form(assigns) do
    assigns =
      assign(assigns,
        events: List.wrap(assigns.form[:events].value),
        shown: filter_families(assigns.families, assigns.query)
      )

    ~H"""
    <.form for={@form} id={@id} class="kunai-form" phx-change="validate" phx-submit="save">
      <.card title={t("Endpoint")}>
        <div class="kunai-fields">
          <.field
            label={t("URL")}
            for={"#{@id}-url"}
            errors={errors(@form[:url])}
            hint={t("HTTPS, on an address the internet can reach.")}
          >
            <input
              id={"#{@id}-url"}
              type="url"
              name={@form[:url].name}
              value={@form[:url].value}
              class="kunai-input kunai-mono"
              placeholder="https://example.com/webhooks"
              autocomplete="off"
              phx-debounce="300"
            />
          </.field>
          <.field label={t("Description")} for={"#{@id}-description"} errors={errors(@form[:description])} optional>
            <input
              id={"#{@id}-description"}
              type="text"
              name={@form[:description].name}
              value={@form[:description].value}
              class="kunai-input"
              placeholder={t("What it is for, for the people who look after it")}
              phx-debounce="300"
            />
          </.field>
        </div>
      </.card>

      <.card title={t("Events to send")} flush>
        <:description>
          {t("The endpoint receives these, and the events added later to a family it chose.")}
        </:description>
        <:actions><span class="kunai-count">{selected_count(@events)}</span></:actions>
        <div class="kunai-picker">
          <p :for={error <- errors(@form[:events])} class="kunai-error kunai-picker-error">{error}</p>
          <input type="hidden" name="endpoint[events][]" value="" />
          <label class="kunai-option kunai-option--all">
            <input type="checkbox" name="endpoint[events][]" value="*" checked={"*" in @events} />
            <span class="kunai-option-text">
              <span class="kunai-strong">{t("All events")}</span>
              <span class="kunai-muted">{t("Every event, those added later too.")}</span>
            </span>
          </label>
          <div :if={"*" not in @events} class="kunai-picker-search">
            <.icon name="search" class="kunai-faint" />
            <input
              type="search"
              name="q"
              value={@query}
              placeholder={t("Find an event")}
              class="kunai-input kunai-input--bare"
              phx-debounce="150"
              autocomplete="off"
            />
          </div>
          <div :for={{family, types} <- @shown} :if={"*" not in @events} class="kunai-family">
            <label class="kunai-option kunai-option--family">
              <input
                type="checkbox"
                name="endpoint[events][]"
                value={family <> ".*"}
                checked={(family <> ".*") in @events}
              />
              <span class="kunai-option-text">
                <span class="kunai-mono kunai-strong">{family}.*</span>
                <span class="kunai-muted">{tn("%{count} event", "%{count} events", length(types))}</span>
              </span>
            </label>
            <label
              :for={type <- types}
              :if={(family <> ".*") not in @events}
              class="kunai-option kunai-option--event"
            >
              <input type="checkbox" name="endpoint[events][]" value={type.name} checked={type.name in @events} />
              <span class="kunai-option-text">
                <span class="kunai-mono">{type.name}</span>
                <span :if={type.doc} class="kunai-muted">{type.doc}</span>
              </span>
            </label>
          </div>
          <p :if={"*" not in @events and @shown == []} class="kunai-muted kunai-picker-none">
            {t("No event matches.")}
          </p>
        </div>
      </.card>

      <.card :if={@grantable != []} title={t("Access")}>
        <:description>{t("An event reaches the endpoint only when it has the event's access.")}</:description>
        <p :for={error <- errors(@form[:scopes])} class="kunai-error">{error}</p>
        <input type="hidden" name="endpoint[scopes][]" value="" />
        <div class="kunai-chips">
          <label :for={scope <- @grantable} class="kunai-chip">
            <input
              type="checkbox"
              name="endpoint[scopes][]"
              value={scope}
              checked={scope in scopes(@form, @grantable)}
            />
            <span class="kunai-mono">{scope}</span>
          </label>
        </div>
      </.card>

      <details
        class="kunai-card kunai-advanced"
        open={@form[:payload].value == "thin" or @form[:ordered].value in [true, "true"]}
      >
        <summary class="kunai-card-head">
          <h2 class="kunai-card-title">{t("Advanced")}</h2>
          <.icon name="chevron-down" class="kunai-faint kunai-advanced-chevron" />
        </summary>
        <div class="kunai-card-body kunai-fields">
          <fieldset class="kunai-fieldset">
            <legend class="kunai-label">{t("Payload")}</legend>
            <label class="kunai-radio">
              <input type="radio" name="endpoint[payload]" value="full" checked={@form[:payload].value != "thin"} />
              <span>
                <span class="kunai-strong">{t("Full")}</span>
                <span class="kunai-muted">{t("The whole object, as it was when it changed.")}</span>
              </span>
            </label>
            <label class="kunai-radio">
              <input type="radio" name="endpoint[payload]" value="thin" checked={@form[:payload].value == "thin"} />
              <span>
                <span class="kunai-strong">{t("Thin")}</span>
                <span class="kunai-muted">{t("Its id only: the receiver asks the API for the rest.")}</span>
              </span>
            </label>
          </fieldset>

          <fieldset class="kunai-fieldset">
            <legend class="kunai-label">{t("Order")}</legend>
            <input type="hidden" name="endpoint[ordered]" value="false" />
            <label class="kunai-radio">
              <input
                type="checkbox"
                name="endpoint[ordered]"
                value="true"
                checked={@form[:ordered].value in [true, "true"]}
              />
              <span>
                <span class="kunai-strong">{t("One at a time, in order")}</span>
                <span class="kunai-muted">
                  {t("Otherwise events arrive as soon as they can, and one failing holds up no other.")}
                </span>
              </span>
            </label>
          </fieldset>

          <.field
            :if={length(@versions) > 1}
            label={t("Version")}
            for={"#{@id}-version"}
            hint={t("The version of the payloads it receives.")}
          >
            <select id={"#{@id}-version"} name="endpoint[api_version]" class="kunai-input kunai-select">
              <option
                :for={version <- Enum.reverse(@versions)}
                value={version}
                selected={version == @form[:api_version].value}
              >
                {version}
              </option>
            </select>
          </.field>

          <fieldset :if={@new?} class="kunai-fieldset">
            <legend class="kunai-label">{t("Signing")}</legend>
            <label class="kunai-radio">
              <input type="radio" name="signing" value="hmac" checked={@signing != "ed25519"} />
              <span>
                <span class="kunai-strong">HMAC-SHA256</span>
                <span class="kunai-muted">{t("A secret the endpoint shares.")}</span>
              </span>
            </label>
            <label class="kunai-radio">
              <input type="radio" name="signing" value="ed25519" checked={@signing == "ed25519"} />
              <span>
                <span class="kunai-strong">Ed25519</span>
                <span class="kunai-muted">{t("A key pair: the endpoint keeps only a public key.")}</span>
              </span>
            </label>
          </fieldset>
        </div>
      </details>

      <div class="kunai-form-actions">
        <.button variant="ghost" navigate={@cancel}>{t("Cancel")}</.button>
        <.button variant="primary" type="submit" phx-disable-with={t("Saving…")}>
          {if @new?, do: t("Add endpoint"), else: t("Save changes")}
        </.button>
      </div>
    </.form>
    """
  end

  defp filter_families(families, query) when query in [nil, ""], do: families

  defp filter_families(families, query) do
    query = String.downcase(query)

    families
    |> Enum.map(fn {family, types} ->
      {family, Enum.filter(types, &matches_query?(&1, query))}
    end)
    |> Enum.reject(fn {_family, types} -> types == [] end)
  end

  defp matches_query?(type, query),
    do:
      String.contains?(type.name, query) or
        String.contains?(String.downcase(type.doc || ""), query)

  defp selected_count(events) do
    case Enum.reject(events, &(&1 == "")) do
      ["*"] -> t("All events")
      [] -> t("None chosen")
      chosen -> tn("%{count} chosen", "%{count} chosen", length(chosen))
    end
  end

  # A new endpoint gets every scope its maker may give, unless they choose.
  defp scopes(form, grantable) do
    case form[:scopes].value do
      [] -> if form.source.data.id, do: [], else: grantable
      nil -> grantable
      scopes -> scopes
    end
  end

  attr(:label, :string, required: true)
  attr(:for, :string, default: nil)
  attr(:hint, :string, default: nil)
  attr(:optional, :boolean, default: false)
  attr(:errors, :list, default: [])
  slot(:inner_block, required: true)

  defp field(assigns) do
    ~H"""
    <div class={["kunai-field", @errors != [] && "kunai-field--invalid"]}>
      <label class="kunai-label" for={@for}>
        {@label} <span :if={@optional} class="kunai-faint">{t("Optional")}</span>
      </label>
      {render_slot(@inner_block)}
      <p :for={error <- @errors} class="kunai-error">{error}</p>
      <p :if={@hint && @errors == []} class="kunai-hint">{@hint}</p>
    </div>
    """
  end

  @doc "A form field's errors, as text, once it was changed or submitted."
  def errors(%Phoenix.HTML.FormField{} = field) do
    if Phoenix.Component.used_input?(field),
      do: Enum.map(field.errors, &Kunai.Web.error_message/1),
      else: []
  end
end
