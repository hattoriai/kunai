defmodule Kunai.Live.DeliveryLive do
  @moduledoc false
  # A delivery: its event as the endpoint got it, each attempt, and a
  # button to send it again.

  use Phoenix.LiveView
  use PhoenixMountable.Path, mountable: Kunai.Router

  import Kunai.Components

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.kunai_scope

    with %Kunai.Delivery{} = delivery <- Kunai.get_delivery(scope, id),
         %Kunai.Endpoint{} = endpoint <- Kunai.get_endpoint(scope, delivery.endpoint_id) do
      if connected?(socket), do: Kunai.Broadcast.subscribe(endpoint.id)
      event = Kunai.get_event(scope, delivery.event_id)

      {:ok,
       assign(socket,
         page_title: delivery.event_type,
         delivery: delivery,
         endpoint: endpoint,
         payload: event && Kunai.Payload.build(Kunai.Config.catalog(), event, endpoint)
       )}
    else
      _missing ->
        {:ok,
         socket |> put_flash(:error, "That delivery does not exist.") |> push_navigate(to: ~m"/")}
    end
  end

  @impl true
  def handle_info(
        {:kunai_attempt, %{delivery_id: id}},
        %{assigns: %{delivery: %{id: id}}} = socket
      ),
      do: {:noreply, reload(socket)}

  def handle_info(_other, socket), do: {:noreply, socket}

  defp reload(socket) do
    case Kunai.get_delivery(socket.assigns.kunai_scope, socket.assigns.delivery.id) do
      nil -> socket
      delivery -> assign(socket, delivery: delivery)
    end
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:ok, _delivery} = Kunai.retry_delivery(socket.assigns.kunai_scope, socket.assigns.delivery)
    {:noreply, socket |> reload() |> put_flash(:info, "Sent again, with the same webhook-id.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page mount={@mount} flash={@flash} scope={@kunai_scope}>
      <.header title={@delivery.event_type} back={~m"/#{@endpoint.id}"} back_label="Endpoint">
        <:subtitle>To <span class="kunai-mono">{@endpoint.url}</span></:subtitle>
        <:actions>
          <.button phx-click="retry" phx-disable-with="Sending…">Send again</.button>
        </:actions>
      </.header>

      <dl class="kunai-details">
        <div>
          <dt>Status</dt>
          <dd><.status status={@delivery.status} /></dd>
        </div>
        <div>
          <dt>Attempts</dt>
          <dd>{@delivery.attempts}</dd>
        </div>
        <div :if={@delivery.status == "pending" and @delivery.next_attempt_at}>
          <dt>Next attempt</dt>
          <dd><.time at={@delivery.next_attempt_at} /></dd>
        </div>
        <div>
          <dt>webhook-id</dt>
          <dd class="kunai-mono">{@delivery.id}</dd>
        </div>
        <div>
          <dt>Event</dt>
          <dd class="kunai-mono">{@delivery.event_id}</dd>
        </div>
      </dl>

      <.section title="Attempts" id="kunai-attempts">
        <p :if={@delivery.attempt_log == []} class="kunai-muted">Not tried yet.</p>
        <table :if={@delivery.attempt_log != []} class="kunai-table">
          <thead>
            <tr>
              <th>#</th>
              <th>Answer</th>
              <th>Time</th>
              <th>Response</th>
              <th>When</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={attempt <- Enum.reverse(@delivery.attempt_log)} id={attempt.id}>
              <td>{attempt.number}</td>
              <td>
                <.status
                  status={if attempt.status_code in 200..299, do: "succeeded", else: "failed"}
                  label={if attempt.status_code, do: Integer.to_string(attempt.status_code), else: attempt.error}
                />
              </td>
              <td>{attempt.duration_ms} ms</td>
              <td><code :if={attempt.response_body not in [nil, ""]} class="kunai-snippet">{attempt.response_body}</code></td>
              <td><.time at={attempt.created_at} /></td>
            </tr>
          </tbody>
        </table>
      </.section>

      <.section :if={@payload} title="Payload">
        <.code value={@payload} />
      </.section>
    </.page>
    """
  end
end
