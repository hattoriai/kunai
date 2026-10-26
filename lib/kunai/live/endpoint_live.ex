defmodule Kunai.Live.EndpointLive do
  @moduledoc false
  # An endpoint: how its deliveries go, each one opened beside the list,
  # its details, its secret and a test. Live.

  use Kunai.Live.Page

  @refresh 5_000
  @statuses ~w(succeeded failed pending)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Kunai.get_endpoint(socket.assigns.kunai_scope, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, t("That endpoint does not exist."))
         |> push_navigate(to: socket.assigns.kunai.base)}

      endpoint ->
        # Live with Kunai's PubSub, else read again every few seconds.
        if connected?(socket) and Kunai.Broadcast.subscribe(endpoint.id) == :error,
          do: :timer.send_interval(@refresh, :refresh)

        {:ok,
         assign(socket,
           page_title: endpoint.description || URI.parse(endpoint.url).host,
           endpoint: endpoint,
           secret: nil,
           ed25519?: String.starts_with?(Kunai.secret(endpoint) || "", "whpk_"),
           test_types: test_types(endpoint),
           status: nil,
           delivery: nil,
           payload: nil
         )}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    status = if params["status"] in @statuses, do: params["status"]

    {:noreply,
     socket
     |> assign(status: status)
     |> load()
     |> open(params["delivery"])}
  end

  # What a test can send: the events the endpoint receives, and a ping.
  defp test_types(endpoint) do
    names =
      Kunai.Config.catalog().event_types()
      |> Enum.map(& &1.name)
      |> Enum.filter(fn name ->
        Enum.any?(endpoint.events, &Kunai.Subscriptions.matches?(&1, name))
      end)
      |> Enum.reject(&(&1 == "kunai.ping"))

    ["kunai.ping" | names]
  end

  defp load(socket) do
    %{kunai_scope: scope, endpoint: endpoint, status: status} = socket.assigns
    opts = [endpoint_id: endpoint.id, limit: 30] ++ if(status, do: [status: status], else: [])
    page = Kunai.list_deliveries(scope, opts)

    assign(socket,
      deliveries: page.data,
      more?: page.has_more,
      summary: Kunai.Stats.summary(scope, endpoint_id: endpoint.id)
    )
  end

  defp open(socket, nil), do: assign(socket, delivery: nil, payload: nil)

  defp open(socket, id) do
    scope = socket.assigns.kunai_scope
    endpoint = socket.assigns.endpoint

    case Kunai.get_delivery(scope, id) do
      %Kunai.Delivery{endpoint_id: endpoint_id} = delivery when endpoint_id == endpoint.id ->
        event = Kunai.get_event(scope, delivery.event_id)
        payload = event && Kunai.Payload.build(Kunai.Config.catalog(), event, endpoint)
        assign(socket, delivery: delivery, payload: payload)

      _missing ->
        assign(socket, delivery: nil, payload: nil)
    end
  end

  # This page's path, with its filter and the delivery opened.
  defp here(assigns, delivery \\ nil) do
    query =
      Enum.reject([status: assigns.status, delivery: delivery], fn {_key, value} ->
        is_nil(value)
      end)

    path = "#{assigns.kunai.base}/#{assigns.endpoint.id}"
    if query == [], do: path, else: path <> "?" <> URI.encode_query(query)
  end

  @impl true
  def handle_info({kind, _detail}, socket) when kind in [:kunai_attempt, :kunai_delivery],
    do: {:noreply, refresh(socket)}

  def handle_info(:refresh, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    socket =
      case Kunai.get_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint.id) do
        nil -> socket
        endpoint -> assign(socket, endpoint: endpoint)
      end

    socket |> load() |> open(socket.assigns.delivery && socket.assigns.delivery.id)
  end

  @impl true
  def handle_event("reveal", _params, socket),
    do:
      {:noreply,
       assign(socket, secret: socket.assigns.secret || Kunai.secret(socket.assigns.endpoint))}

  def handle_event("hide", _params, socket), do: {:noreply, assign(socket, secret: nil)}

  def handle_event("roll", _params, socket) do
    {:ok, secret} = Kunai.roll_secret(socket.assigns.kunai_scope, socket.assigns.endpoint)

    {:noreply,
     socket
     |> assign(secret: secret)
     |> put_flash(:info, t("A new secret signs from now. The old one still signs for a day."))}
  end

  def handle_event("enable", _params, socket) do
    {:ok, endpoint} = Kunai.enable_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint)
    {:noreply, socket |> assign(endpoint: endpoint) |> put_flash(:info, t("Endpoint enabled."))}
  end

  def handle_event("disable", _params, socket) do
    {:ok, endpoint} = Kunai.disable_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint)
    {:noreply, socket |> assign(endpoint: endpoint) |> put_flash(:info, t("Endpoint disabled."))}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _endpoint} = Kunai.delete_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint)

    {:noreply,
     socket
     |> put_flash(:info, t("Endpoint deleted."))
     |> push_navigate(to: socket.assigns.kunai.base)}
  end

  def handle_event("test", %{"type" => type}, socket) do
    type = if type in socket.assigns.test_types, do: type, else: "kunai.ping"

    case Kunai.send_test(socket.assigns.kunai_scope, socket.assigns.endpoint, type) do
      {:ok, delivery} ->
        {:noreply,
         socket
         |> put_flash(:info, t("A test %{type} is on its way.", type: type))
         |> push_patch(to: here(socket.assigns, delivery.id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, t("The test could not be sent."))}
    end
  end

  def handle_event("retry", _params, socket) do
    {:ok, _delivery} = Kunai.retry_delivery(socket.assigns.kunai_scope, socket.assigns.delivery)

    {:noreply,
     socket |> refresh() |> put_flash(:info, t("Sent again, with the same webhook-id."))}
  end

  def handle_event("replay", _params, socket) do
    {:ok, count} = Kunai.replay(socket.assigns.kunai_scope, socket.assigns.endpoint)

    message =
      case count do
        0 -> t("No delivery failed in the last day.")
        n -> tn("One delivery is sent again.", "%{count} deliveries are sent again.", n)
      end

    {:noreply, socket |> load() |> put_flash(:info, message)}
  end

  def handle_event("close", _params, socket),
    do: {:noreply, push_patch(socket, to: here(socket.assigns))}

  @impl true
  def render(assigns) do
    ~H"""
    <.page kunai={@kunai} flash={@flash}>
      <.header eyebrow={@kunai.eyebrow} title={@page_title} back={@kunai.base}>
        <:badge><.status status={endpoint_status(@endpoint)} /></:badge>
        <:subtitle>
          <span class="kunai-inline-copy">
            <span class="kunai-mono">{@endpoint.url}</span><.copy value={@endpoint.url} />
          </span>
        </:subtitle>
        <:actions>
          <.button
            :if={not Kunai.Endpoint.enabled?(@endpoint)}
            variant="primary"
            icon="play"
            phx-click="enable"
          >
            {t("Enable")}
          </.button>
          <.button icon="edit" navigate={"#{@kunai.base}/#{@endpoint.id}/edit"}>{t("Edit")}</.button>
          <.menu id="kunai-endpoint-menu">
            <:item :if={Kunai.Endpoint.enabled?(@endpoint)} click="disable" icon="pause">
              {t("Disable")}
            </:item>
            <:item
              click="replay"
              icon="refresh"
              confirm={t("Send again the deliveries that failed in the last day?")}
            >
              {t("Send failed again")}
            </:item>
            <:item
              click="roll"
              icon="key"
              confirm={t("Roll the secret? The old one still signs for a day, while the endpoint changes to the new one.")}
            >
              {t("Roll secret")}
            </:item>
            <:item click="delete" icon="trash" danger confirm={t("Delete this endpoint and its deliveries?")}>
              {t("Delete")}
            </:item>
          </.menu>
        </:actions>
      </.header>

      <.endpoint_notice endpoint={@endpoint} />

      <div class="kunai-layout">
        <div class="kunai-main">
          <.card title={t("Last 24 hours")}>
            <div class="kunai-overview">
              <div class="kunai-overview-numbers">
                <.metric label={t("Deliveries")} value={Integer.to_string(@summary.total)} />
                <.metric label={t("Delivered")} value={success_rate(@summary)} tone={if @summary.failed + @summary.retrying > 0, do: "wait"} />
                <.metric
                  label={t("Response time")}
                  value={if @summary.average_ms, do: t("%{ms} ms", ms: @summary.average_ms), else: "—"}
                />
              </div>
              <.bar_chart hours={@summary.hours} />
            </div>
          </.card>

          <.card title={t("Deliveries")} flush id="kunai-deliveries">
            <:actions>
              <nav class="kunai-segmented" aria-label={t("Filter")}>
                <.link patch={"#{@kunai.base}/#{@endpoint.id}"} class={["kunai-segment", is_nil(@status) && "is-active"]}>
                  {t("All")}
                </.link>
                <.link
                  :for={status <- ~w(succeeded failed pending)}
                  patch={"#{@kunai.base}/#{@endpoint.id}?status=#{status}"}
                  class={["kunai-segment", @status == status && "is-active"]}
                >
                  {status_label(status)}
                </.link>
              </nav>
            </:actions>
            <.deliveries_table
              :if={@deliveries != []}
              deliveries={@deliveries}
              base={@kunai.base}
              patch={"#{@kunai.base}/#{@endpoint.id}"}
              selected={@delivery && @delivery.id}
            />
            <.empty_state
              :if={@deliveries == []}
              title={if @status, do: t("None here"), else: t("No deliveries yet")}
              icon="send"
            >
              <p>
                {if @status,
                  do: t("No delivery has this status."),
                  else: t("Send a test event, or wait for the next event.")}
              </p>
            </.empty_state>
            <:footer :if={@more?}>{t("The latest 30 are shown.")}</:footer>
          </.card>
        </div>

        <div class="kunai-side">
          <.card title={t("Details")}>
            <.properties>
              <:item label={t("Events")}>
                <span :if={@endpoint.events == ["*"]}>{t("All events")}</span>
                <span :if={@endpoint.events != ["*"]} class="kunai-chips">
                  <span :for={event <- @endpoint.events} class="kunai-tag kunai-mono">{event}</span>
                </span>
              </:item>
              <:item :if={@endpoint.scopes != []} label={t("Access")}>
                <span class="kunai-chips">
                  <span :for={scope <- @endpoint.scopes} class="kunai-tag kunai-mono">{scope}</span>
                </span>
              </:item>
              <:item label={t("Payload")}>
                {if @endpoint.payload == "thin", do: t("Thin: the object's id"), else: t("Full: the whole object")}
              </:item>
              <:item label={t("Order")}>
                {if @endpoint.ordered, do: t("One at a time, in order"), else: t("As soon as they can")}
              </:item>
              <:item :if={@endpoint.api_version} label={t("Version")}>
                <span class="kunai-mono">{@endpoint.api_version}</span>
              </:item>
              <:item label={t("Endpoint id")}>
                <span class="kunai-inline-copy">
                  <span class="kunai-mono">{@endpoint.id}</span><.copy value={@endpoint.id} />
                </span>
              </:item>
              <:item label={t("Created")}><.time at={@endpoint.inserted_at} /></:item>
            </.properties>
          </.card>

          <.card title={t("Signing secret")}>
            <:actions>
              <.button :if={is_nil(@secret)} size="sm" icon="eye" phx-click="reveal">{t("Reveal")}</.button>
              <.button :if={@secret} size="sm" variant="ghost" icon="eye-off" phx-click="hide">{t("Hide")}</.button>
            </:actions>
            <.secret id="kunai-secret" value={@secret} prefix={if @ed25519?, do: "whpk_", else: "whsec_"} />
          </.card>

          <.card title={t("Send a test event")}>
            <form id="kunai-test" class="kunai-inline-form" phx-submit="test">
              <select name="type" class="kunai-input kunai-select" aria-label={t("Event")}>
                <option :for={type <- @test_types} value={type}>{type}</option>
              </select>
              <.button type="submit" icon="send" phx-disable-with={t("Sending…")}>{t("Send")}</.button>
            </form>
          </.card>

          <.card title={t("Verify signatures")}>
            <.verify_snippet ed25519={@ed25519?} />
          </.card>
        </div>
      </div>

      <div :if={@delivery} class="kunai-drawer-backdrop" phx-click="close"></div>
      <div
        :if={@delivery}
        class="kunai-drawer"
        role="dialog"
        aria-modal="true"
        aria-label={t("Delivery")}
        phx-window-keydown="close"
        phx-key="Escape"
      >
        <.delivery_detail delivery={@delivery} endpoint={@endpoint} payload={@payload}>
          <:actions>
            <.button size="sm" icon="refresh" phx-click="retry" phx-disable-with={t("Sending…")}>
              {t("Send again")}
            </.button>
            <.button size="sm" variant="ghost" icon="x" patch={here(assigns)} aria-label={t("Close")} />
          </:actions>
        </.delivery_detail>
      </div>
    </.page>
    """
  end

  attr(:endpoint, :map, required: true)

  defp endpoint_notice(%{endpoint: %{status: "disabled", disabled_reason: "gone"}} = assigns) do
    ~H"""
    <.notice kind="danger" title={t("Disabled: the endpoint answered 410 Gone")}>
      {t("It receives no events. Enable it once it is ready to, and send the failed deliveries again.")}
      <:actions><.button size="sm" phx-click="enable">{t("Enable")}</.button></:actions>
    </.notice>
    """
  end

  defp endpoint_notice(%{endpoint: %{status: "disabled", disabled_reason: "failing"}} = assigns) do
    ~H"""
    <.notice kind="danger" title={t("Disabled after days of failures")}>
      {t("Every delivery failed for three days. Enable it once it answers, and send the failed ones again.")}
      <:actions><.button size="sm" phx-click="enable">{t("Enable")}</.button></:actions>
    </.notice>
    """
  end

  defp endpoint_notice(%{endpoint: %{status: "disabled"}} = assigns) do
    ~H"""
    <.notice kind="info" title={t("Disabled")}>
      {t("It receives no events until it is enabled.")}
    </.notice>
    """
  end

  defp endpoint_notice(%{endpoint: %{failing_since: %DateTime{}}} = assigns) do
    ~H"""
    <.notice kind="warning" title={t("Failing since %{when}", when: ago(@endpoint.failing_since))}>
      {t("Every delivery has failed since then, and each is tried again. After three days of failures the endpoint is disabled.")}
    </.notice>
    """
  end

  defp endpoint_notice(assigns) do
    ~H"""
    """
  end
end
