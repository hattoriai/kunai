defmodule Kunai.API.DeliveryController do
  @moduledoc false
  use Kunai.API, :controller

  plug Kunai.API.Idempotency

  def index(conn, params) do
    opts =
      page_opts(params, [{"endpoint", :endpoint_id}, {"event", :event_id}, {"status", :status}])

    expand = expand(params)
    list(conn, Kunai.list_deliveries(conn.assigns.kunai_scope, opts), &View.delivery(&1, expand))
  end

  def show(conn, %{"id" => id} = params) do
    case Kunai.get_delivery(conn.assigns.kunai_scope, id) do
      nil -> not_found(conn, "delivery")
      delivery -> respond(conn, View.delivery(delivery, expand(params)))
    end
  end

  def retry(conn, %{"id" => id}) do
    case Kunai.get_delivery(conn.assigns.kunai_scope, id) do
      nil ->
        not_found(conn, "delivery")

      delivery ->
        {:ok, delivery} = Kunai.retry_delivery(conn.assigns.kunai_scope, delivery)
        respond(conn, View.delivery(delivery))
    end
  end
end
