defmodule Kunai.API.EventController do
  @moduledoc false
  use Kunai.API, :controller

  def index(conn, params) do
    page = Kunai.list_events(conn.assigns.kunai_scope, page_opts(params, [{"type", :type}]))
    list(conn, page, &View.event/1)
  end

  def show(conn, %{"id" => id}) do
    case Kunai.get_event(conn.assigns.kunai_scope, id) do
      nil -> not_found(conn, "event")
      event -> respond(conn, View.event(event))
    end
  end
end
