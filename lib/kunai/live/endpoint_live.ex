defmodule Kunai.Live.EndpointLive do
  @moduledoc false
  # An endpoint: what it receives, its secret, a test, and its deliveries,
  # live.

  use Phoenix.LiveView
  use PhoenixMountable.Path, mountable: Kunai.Router

  import Kunai.Components

  @refresh 5_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Kunai.get_endpoint(socket.assigns.kunai_scope, id) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "That endpoint does not exist.") |> push_navigate(to: ~m"/")}

      endpoint ->
        # Live with Kunai's PubSub, else read again every few seconds.
        if connected?(socket) and Kunai.Broadcast.subscribe(endpoint.id) == :error,
          do: :timer.send_interval(@refresh, :refresh)

        {:ok,
         socket
         |> assign(
           page_title: endpoint.description || endpoint.url,
           endpoint: endpoint,
           secret: nil,
           test_types: test_types(endpoint)
         )
         |> load_deliveries()}
    end
  end

  # What a test can send: the events the endpoint receives, or a ping.
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

  defp load_deliveries(socket) do
    page =
      Kunai.list_deliveries(socket.assigns.kunai_scope,
        endpoint_id: socket.assigns.endpoint.id,
        limit: 25
      )

    assign(socket, deliveries: page.data, more?: page.has_more)
  end

  @impl true
  def handle_info({kind, _detail}, socket) when kind in [:kunai_attempt, :kunai_delivery] do
    {:noreply, socket |> reload_endpoint() |> load_deliveries()}
  end

  def handle_info(:refresh, socket),
    do: {:noreply, socket |> reload_endpoint() |> load_deliveries()}

  defp reload_endpoint(socket) do
    case Kunai.get_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint.id) do
      nil -> socket
      endpoint -> assign(socket, endpoint: endpoint)
    end
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
     |> put_flash(:info, "A new secret signs from now. The old one still signs for a day.")}
  end

  def handle_event("enable", _params, socket) do
    {:ok, endpoint} = Kunai.enable_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint)
    {:noreply, socket |> assign(endpoint: endpoint) |> put_flash(:info, "Endpoint enabled.")}
  end

  def handle_event("disable", _params, socket) do
    {:ok, endpoint} = Kunai.disable_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint)
    {:noreply, socket |> assign(endpoint: endpoint) |> put_flash(:info, "Endpoint disabled.")}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _endpoint} = Kunai.delete_endpoint(socket.assigns.kunai_scope, socket.assigns.endpoint)
    {:noreply, socket |> put_flash(:info, "Endpoint deleted.") |> push_navigate(to: ~m"/")}
  end

  def handle_event("test", %{"type" => type}, socket) do
    type = if type in socket.assigns.test_types, do: type, else: "kunai.ping"

    case Kunai.send_test(socket.assigns.kunai_scope, socket.assigns.endpoint, type) do
      {:ok, _delivery} ->
        {:noreply,
         socket |> load_deliveries() |> put_flash(:info, "A test #{type} is on its way.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The test could not be sent.")}
    end
  end

  def handle_event("replay", _params, socket) do
    {:ok, count} = Kunai.replay(socket.assigns.kunai_scope, socket.assigns.endpoint)

    message =
      case count do
        0 -> "No delivery failed in the last day."
        1 -> "One delivery is sent again."
        n -> "#{n} deliveries are sent again."
      end

    {:noreply, socket |> load_deliveries() |> put_flash(:info, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page mount={@mount} flash={@flash} scope={@kunai_scope}>
      <.header title={@endpoint.description || URI.parse(@endpoint.url).host} back={~m"/"}>
        <:subtitle><span class="kunai-mono">{@endpoint.url}</span></:subtitle>
        <:actions>
          <.button navigate={~m"/#{@endpoint.id}/edit"}>Edit</.button>
          <.button :if={Kunai.Endpoint.enabled?(@endpoint)} phx-click="disable">Disable</.button>
          <.button :if={not Kunai.Endpoint.enabled?(@endpoint)} variant="primary" phx-click="enable">Enable</.button>
          <.button variant="danger" phx-click="delete" data-confirm="Delete this endpoint and its deliveries?">
            Delete
          </.button>
        </:actions>
      </.header>

      <div :if={notice(@endpoint)} class={"kunai-notice kunai-notice--#{elem(notice(@endpoint), 0)}"} role="status">
        {elem(notice(@endpoint), 1)}
      </div>

      <dl class="kunai-details">
        <div>
          <dt>Status</dt>
          <dd><.status status={endpoint_status(@endpoint)} /></dd>
        </div>
        <div>
          <dt>Events</dt>
          <dd class="kunai-mono">{if @endpoint.events == ["*"], do: "All events", else: Enum.join(@endpoint.events, ", ")}</dd>
        </div>
        <div :if={@endpoint.scopes != []}>
          <dt>Access</dt>
          <dd class="kunai-mono">{Enum.join(@endpoint.scopes, ", ")}</dd>
        </div>
        <div>
          <dt>Payload</dt>
          <dd>{if @endpoint.payload == "thin", do: "The object's id", else: "The whole object"}</dd>
        </div>
        <div>
          <dt>Order</dt>
          <dd>{if @endpoint.ordered, do: "One at a time, in order", else: "As soon as they can"}</dd>
        </div>
        <div :if={@endpoint.api_version}>
          <dt>Version</dt>
          <dd class="kunai-mono">{@endpoint.api_version}</dd>
        </div>
        <div>
          <dt>Id</dt>
          <dd class="kunai-mono">{@endpoint.id}</dd>
        </div>
      </dl>

      <.section title="Signing secret">
        <:actions>
          <.button :if={is_nil(@secret)} phx-click="reveal">Reveal</.button>
          <.button :if={@secret} variant="quiet" phx-click="hide">Hide</.button>
          <.button
            phx-click="roll"
            data-confirm="Roll the secret? The old one still signs for a day, while the endpoint changes to the new one."
          >
            Roll
          </.button>
        </:actions>
        <.secret :if={@secret} id="kunai-secret" value={@secret} />
        <p :if={is_nil(@secret)} class="kunai-muted">Hidden.</p>
      </.section>

      <.section title="Send a test">
        <form id="kunai-test" class="kunai-inline" phx-submit="test">
          <select name="type" class="kunai-input" aria-label="Event">
            <option :for={type <- @test_types} value={type}>{type}</option>
          </select>
          <.button type="submit" phx-disable-with="Sending…">Send</.button>
        </form>
      </.section>

      <.section title="Deliveries" id="kunai-deliveries">
        <:actions>
          <.button variant="quiet" phx-click="replay" data-confirm="Send again the deliveries that failed in the last day?">
            Send failed again
          </.button>
        </:actions>
        <p :if={@deliveries == []} class="kunai-muted">None yet. Send a test, or wait for an event.</p>
        <table :if={@deliveries != []} class="kunai-table">
          <thead>
            <tr>
              <th>Event</th>
              <th>Status</th>
              <th>Attempts</th>
              <th>Last answer</th>
              <th>When</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={delivery <- @deliveries} id={delivery.id}>
              <td>
                <.link navigate={~m"/deliveries/#{delivery.id}"} class="kunai-link kunai-mono">{delivery.event_type}</.link>
              </td>
              <td><.status status={delivery.status} /></td>
              <td>{delivery.attempts}</td>
              <td class="kunai-mono">{answer(delivery)}</td>
              <td><.time at={delivery.inserted_at} /></td>
            </tr>
          </tbody>
        </table>
        <p :if={@more?} class="kunai-muted">The latest 25 are shown.</p>
      </.section>
    </.page>
    """
  end

  defp notice(%{status: "disabled", disabled_reason: "gone"}),
    do:
      {:fail,
       "Disabled: the endpoint answered 410 Gone. Enable it once it receives events again."}

  defp notice(%{status: "disabled", disabled_reason: "failing"}),
    do:
      {:fail,
       "Disabled: every delivery failed for days. Enable it once it answers, and send the failed ones again."}

  defp notice(%{status: "disabled"}),
    do: {:muted, "Disabled: it receives no events until it is enabled."}

  defp notice(%{failing_since: %DateTime{} = since}),
    do:
      {:wait,
       "Every delivery has failed since #{Kunai.Components.ago(since)}. It is disabled after three days of failing."}

  defp notice(_endpoint), do: nil

  defp answer(%{last_status_code: code}) when is_integer(code), do: Integer.to_string(code)
  defp answer(%{last_error: error}) when is_binary(error), do: error
  defp answer(_delivery), do: "—"
end
