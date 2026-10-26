defmodule Kunai.API.EventTypeController do
  @moduledoc false
  use Kunai.API, :controller

  alias Kunai.API.OpenAPI

  def index(conn, _params) do
    types = Kunai.Config.catalog().event_types() |> Enum.reject(&(&1.name == "kunai.ping"))

    respond(conn, %{
      "object" => "list",
      "url" => conn.request_path,
      "has_more" => false,
      "data" => Enum.map(types, &View.event_type/1)
    })
  end

  def openapi(conn, _params) do
    respond(conn, OpenAPI.document(conn.assigns.mount.path))
  end
end
