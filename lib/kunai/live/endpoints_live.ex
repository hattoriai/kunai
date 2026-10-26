defmodule Kunai.Live.EndpointsLive do
  @moduledoc false
  # An owner's endpoints, and how their deliveries went in the last day.

  use Kunai.Live.Page

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.kunai_scope
    page = Kunai.list_endpoints(scope, limit: 100)

    {:ok,
     assign(socket,
       page_title: t("Webhooks"),
       endpoints: page.data,
       more?: page.has_more,
       summary: Kunai.Stats.summary(scope),
       stats: Kunai.Stats.by_endpoint(scope),
       example: example()
     )}
  end

  # What an endpoint receives: the catalog's first event with an example.
  defp example do
    catalog = Kunai.Config.catalog()

    case Enum.find(catalog.event_types(), & &1.example) do
      nil ->
        nil

      type ->
        event = Kunai.Events.build(catalog, type, type.example, nil, [])

        Kunai.Payload.build(catalog, event, %Kunai.Endpoint{
          payload: "full",
          api_version: event.api_version
        })
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page kunai={@kunai} flash={@flash}>
      <.header eyebrow={@kunai.eyebrow} title={t("Webhooks")}>
        <:subtitle>{t("Send this account's events to your own systems, signed, as they happen.")}</:subtitle>
        <:actions>
          <.button :if={@endpoints != []} variant="primary" icon="plus" navigate={"#{@kunai.base}/new"}>
            {t("Add endpoint")}
          </.button>
        </:actions>
      </.header>

      <%= if @endpoints == [] do %>
        <div class="kunai-onboarding">
          <.card>
            <.empty_state title={t("Listen for this account's events")}>
              <p>
                {t("Give a URL and choose its events: each one is sent to it as it happens, signed, and tried again for three days if it fails.")}
              </p>
              <:actions>
                <.button variant="primary" icon="plus" navigate={"#{@kunai.base}/new"}>{t("Add endpoint")}</.button>
              </:actions>
            </.empty_state>
          </.card>
          <.card :if={@example} title={t("What an endpoint receives")}>
            <:description>{t("A POST of JSON, for each event, with Standard Webhooks' signature headers.")}</:description>
            <.code value={@example} id="kunai-example" />
          </.card>
        </div>
      <% else %>
        <div class="kunai-metrics">
          <.metric label={t("Deliveries")} value={Integer.to_string(@summary.total)} hint={t("Last 24 hours")}>
            <.bar_chart hours={@summary.hours} size="mini" />
          </.metric>
          <.metric label={t("Delivered")} value={success_rate(@summary)} hint={failures_hint(@summary)} />
          <.metric
            label={t("Response time")}
            value={if @summary.average_ms, do: t("%{ms} ms", ms: @summary.average_ms), else: "—"}
            hint={t("Average")}
          />
          <.metric
            label={t("Endpoints")}
            value={Integer.to_string(length(@endpoints))}
            hint={failing_hint(@endpoints)}
            tone={if failing_count(@endpoints) > 0, do: "wait"}
          />
        </div>

        <.card flush>
          <.endpoints_table endpoints={@endpoints} stats={@stats} base={@kunai.base} />
          <:footer :if={@more?}>{t("The first 100 endpoints are shown.")}</:footer>
        </.card>
      <% end %>
    </.page>
    """
  end

  defp failing_count(endpoints),
    do: Enum.count(endpoints, &(endpoint_status(&1) in ["failing", "disabled"]))

  defp failing_hint(endpoints) do
    case failing_count(endpoints) do
      0 -> t("All healthy")
      count -> tn("%{count} needs attention", "%{count} need attention", count)
    end
  end
end
