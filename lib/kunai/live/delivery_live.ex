defmodule Kunai.Live.DeliveryLive do
  @moduledoc false
  # A delivery on a page of its own: its event as the endpoint got it, each
  # attempt, and a button to send it again. Live.

  use Kunai.Live.Page

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
         socket
         |> put_flash(:error, t("That delivery does not exist."))
         |> push_navigate(to: socket.assigns.kunai.base)}
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
    {:noreply, socket |> reload() |> put_flash(:info, t("Sent again, with the same webhook-id."))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page kunai={@kunai} flash={@flash} class="kunai-narrow">
      <nav class="kunai-crumbs" aria-label={t("Breadcrumb")}>
        <.link navigate={"#{@kunai.base}/#{@endpoint.id}"} class="kunai-crumb">
          <.icon name="arrow-left" />{@endpoint.description || URI.parse(@endpoint.url).host}
        </.link>
      </nav>
      <.card>
        <.delivery_detail delivery={@delivery} endpoint={@endpoint} payload={@payload}>
          <:actions>
            <.button size="sm" icon="refresh" phx-click="retry" phx-disable-with={t("Sending…")}>
              {t("Send again")}
            </.button>
          </:actions>
        </.delivery_detail>
      </.card>
    </.page>
    """
  end
end
