defmodule Kunai.Live.InboxLive do
  @moduledoc false
  # The development inbox: the webhooks the app sent to itself, live, each
  # with whether its signature verifies (Kunai.Dev.Inbox).

  use Kunai.Live.Page

  alias Kunai.Dev.Inbox

  @impl true
  def mount(_params, _session, socket) do
    if Inbox.running?() do
      if connected?(socket), do: Inbox.subscribe()

      {:ok,
       assign(socket,
         page_title: t("Inbox"),
         requests: Inbox.list(),
         request: nil,
         origin: nil
       )}
    else
      {:ok, push_navigate(socket, to: socket.assigns.kunai.base)}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(uri)
    origin = %URI{scheme: scheme, host: host, port: port} |> URI.to_string()
    request = Enum.find(socket.assigns.requests, &(to_string(&1.id) == params["request"]))
    {:noreply, assign(socket, origin: origin, request: request)}
  end

  @impl true
  def handle_info({:kunai_inbox, request}, socket),
    do: {:noreply, update(socket, :requests, &Enum.take([request | &1], 200))}

  def handle_info(:kunai_inbox_cleared, socket),
    do: {:noreply, assign(socket, requests: [], request: nil)}

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("clear", _params, socket) do
    :ok = Inbox.clear()

    {:noreply,
     socket |> assign(requests: [], request: nil) |> push_patch(to: here(socket.assigns))}
  end

  def handle_event("close", _params, socket),
    do: {:noreply, push_patch(socket, to: here(socket.assigns))}

  defp here(assigns), do: "#{assigns.kunai.base}/inbox"

  defp inbox_url(origin, name), do: "#{origin}/dev/webhooks/inbox/#{name}"

  # Kunai refuses the app's own address unless development allows it.
  defp blocked?(origin) do
    egress = Kunai.Config.egress()
    %URI{scheme: scheme} = URI.parse(origin)
    (scheme == "http" and !egress[:allow_http]) or !egress[:allow_private]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page kunai={@kunai} flash={@flash}>
      <.header eyebrow={@kunai.eyebrow} title={t("Inbox")} back={@kunai.base} back_label={t("Webhooks")}>
        <:subtitle>{t("The webhooks this app sends to itself, in development, as they arrive.")}</:subtitle>
        <:actions>
          <.button :if={@requests != []} icon="trash" phx-click="clear">{t("Clear")}</.button>
        </:actions>
      </.header>

      <.notice :if={@origin && blocked?(@origin)} kind="warning" title={t("Kunai cannot send to this app yet")}>
        {t("Allow it in development: config :kunai, egress: [allow_http: true, allow_private: true]")}
      </.notice>

      <.card title={t("Send to the inbox")}>
        <:description>
          {t("An endpoint at an inbox's address receives into it. Any name makes an inbox.")}
        </:description>
        <div class="kunai-inbox-url">
          <span class="kunai-inline-copy">
            <span class="kunai-mono kunai-truncate">{inbox_url(@origin, "test")}</span>
            <.copy value={inbox_url(@origin, "test")} />
          </span>
          <.button
            size="sm"
            icon="plus"
            navigate={new_endpoint_path(@kunai.base) <> "?" <> URI.encode_query(url: inbox_url(@origin, "test"))}
          >
            {t("Add an endpoint here")}
          </.button>
        </div>
        <p class="kunai-hint">
          {t("Add ?status=503 to the address to answer with that status and watch the retries, or ?delay=2000 to answer late.")}
        </p>
      </.card>

      <.card flush title={t("Received")}>
        <.empty_state :if={@requests == []} icon="inbox" title={t("Nothing yet")}>
          <p>{t("Send a test event to an endpoint at the inbox, or make a change the app tells of.")}</p>
        </.empty_state>
        <div :if={@requests != []} class="kunai-table-wrap">
          <table class="kunai-table kunai-table--rows" id="kunai-inbox">
            <thead>
              <tr>
                <th>{t("Event")}</th>
                <th>{t("Inbox")}</th>
                <th>{t("Signature")}</th>
                <th>{t("Answered")}</th>
                <th class="kunai-col-when">{t("Received")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={request <- @requests} id={"request-#{request.id}"} class={[@request && @request.id == request.id && "is-selected"]}>
                <td>
                  <.link patch={here(assigns) <> "?request=#{request.id}"} class="kunai-row-link">
                    <span class="kunai-mono kunai-strong">{request.event_type || t("Not an event")}</span>
                  </.link>
                  <p class="kunai-mono kunai-faint kunai-small kunai-truncate">{request.webhook_id}</p>
                </td>
                <td class="kunai-mono">{request.inbox}</td>
                <td><.signature verified={request.verified} /></td>
                <td><.code_pill code={request.status} /></td>
                <td class="kunai-col-when kunai-muted"><.time at={request.received_at} /></td>
              </tr>
            </tbody>
          </table>
        </div>
      </.card>

      <div :if={@request} class="kunai-drawer-backdrop" phx-click="close"></div>
      <div
        :if={@request}
        class="kunai-drawer"
        role="dialog"
        aria-modal="true"
        aria-label={t("Request")}
        phx-window-keydown="close"
        phx-key="Escape"
      >
        <div class="kunai-delivery">
          <header class="kunai-delivery-head">
            <div>
              <p class="kunai-delivery-title">{@request.event_type || t("Not an event")}</p>
              <p class="kunai-muted kunai-small">
                {t("To the inbox")} <span class="kunai-mono">{@request.inbox}</span>
              </p>
            </div>
            <div class="kunai-actions">
              <.button size="sm" variant="ghost" icon="x" patch={here(assigns)} aria-label={t("Close")} />
            </div>
          </header>

          <.properties>
            <:item label={t("Signature")}><.signature verified={@request.verified} /></:item>
            <:item label={t("Answered")}><.code_pill code={@request.status} /></:item>
            <:item :if={@request.endpoint_id} label={t("Endpoint")}>
              <.link navigate={endpoint_path(@kunai.base, @request.endpoint_id)} class="kunai-mono">
                {@request.endpoint_id}
              </.link>
            </:item>
            <:item label={t("Received")}><.time at={@request.received_at} /></:item>
          </.properties>

          <section class="kunai-delivery-section">
            <h3 class="kunai-section-label">{t("Headers")}</h3>
            <dl class="kunai-headers">
              <div :for={{name, value} <- Enum.sort(@request.headers)}>
                <dt class="kunai-mono">{name}</dt>
                <dd class="kunai-mono">{value}</dd>
              </div>
            </dl>
          </section>

          <section class="kunai-delivery-section">
            <h3 class="kunai-section-label">{t("Body")}</h3>
            <.code value={body(@request.body)} id={"kunai-inbox-body-#{@request.id}"} />
          </section>
        </div>
      </div>
    </.page>
    """
  end

  defp body(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end

  attr(:verified, :any, required: true)

  defp signature(%{verified: :ok} = assigns) do
    ~H"""
    <span class="kunai-pill kunai-pill--ok">{t("Verified")}</span>
    """
  end

  defp signature(%{verified: :unknown_endpoint} = assigns) do
    ~H"""
    <span class="kunai-pill kunai-pill--muted" title={t("No endpoint has this address.")}>{t("No endpoint")}</span>
    """
  end

  defp signature(assigns) do
    ~H"""
    <span class="kunai-pill kunai-pill--fail" title={inspect(elem(@verified, 1))}>{t("Does not verify")}</span>
    """
  end
end
