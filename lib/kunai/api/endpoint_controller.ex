defmodule Kunai.API.EndpointController do
  @moduledoc false
  use Kunai.API, :controller

  plug Kunai.API.Idempotency

  @fields ~w(url description events scopes payload ordered api_version metadata)

  def index(conn, params) do
    page =
      Kunai.list_endpoints(conn.assigns.kunai_scope, page_opts(params, [{"status", :status}]))

    list(conn, page, &View.endpoint/1)
  end

  def create(conn, params) do
    signing = if params["signing"] == "ed25519", do: :ed25519, else: :hmac

    case Kunai.create_endpoint(conn.assigns.kunai_scope, Map.take(params, @fields),
           signing: signing
         ) do
      {:ok, endpoint, secret} -> respond(conn, 201, View.endpoint(endpoint, secret))
      {:error, changeset} -> invalid(conn, changeset)
    end
  end

  def show(conn, %{"id" => id}), do: with_endpoint(conn, id, &respond(conn, View.endpoint(&1)))

  def update(conn, %{"id" => id} = params) do
    with_endpoint(conn, id, fn endpoint ->
      case Kunai.update_endpoint(conn.assigns.kunai_scope, endpoint, Map.take(params, @fields)) do
        {:ok, endpoint} -> respond(conn, View.endpoint(endpoint))
        {:error, changeset} -> invalid(conn, changeset)
      end
    end)
  end

  def delete(conn, %{"id" => id}) do
    with_endpoint(conn, id, fn endpoint ->
      {:ok, _deleted} = Kunai.delete_endpoint(conn.assigns.kunai_scope, endpoint)
      respond(conn, %{"id" => endpoint.id, "object" => "endpoint", "deleted" => true})
    end)
  end

  def roll_secret(conn, %{"id" => id} = params) do
    with_endpoint(conn, id, fn endpoint ->
      opts =
        [expires_in: integer(params["expires_in"], nil), signing: signing(params["signing"])]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, secret} = Kunai.roll_secret(conn.assigns.kunai_scope, endpoint, opts)
      respond(conn, View.endpoint(endpoint, secret))
    end)
  end

  defp signing("hmac"), do: :hmac
  defp signing("ed25519"), do: :ed25519
  defp signing(_other), do: nil

  def enable(conn, %{"id" => id}) do
    with_endpoint(conn, id, fn endpoint ->
      {:ok, endpoint} = Kunai.enable_endpoint(conn.assigns.kunai_scope, endpoint)
      respond(conn, View.endpoint(endpoint))
    end)
  end

  def disable(conn, %{"id" => id}) do
    with_endpoint(conn, id, fn endpoint ->
      {:ok, endpoint} = Kunai.disable_endpoint(conn.assigns.kunai_scope, endpoint)
      respond(conn, View.endpoint(endpoint))
    end)
  end

  def test(conn, %{"id" => id} = params) do
    with_endpoint(conn, id, fn endpoint ->
      case Kunai.send_test(conn.assigns.kunai_scope, endpoint, params["type"] || "kunai.ping") do
        {:ok, delivery} ->
          respond(conn, 201, View.delivery(delivery))

        {:error, :unknown_event} ->
          error(
            conn,
            400,
            "invalid_request_error",
            "parameter_invalid",
            "type is not an event of the catalog",
            %{"param" => "type"}
          )
      end
    end)
  end

  def replay(conn, %{"id" => id} = params) do
    with_endpoint(conn, id, fn endpoint ->
      opts =
        [from: time(params["from"]), to: time(params["to"]), status: params["status"]]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      {:ok, count} = Kunai.replay(conn.assigns.kunai_scope, endpoint, opts)
      respond(conn, %{"object" => "replay", "endpoint" => endpoint.id, "deliveries" => count})
    end)
  end

  defp time(nil), do: nil

  defp time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  defp with_endpoint(conn, id, fun) do
    case Kunai.get_endpoint(conn.assigns.kunai_scope, id) do
      nil -> not_found(conn, "endpoint")
      endpoint -> fun.(endpoint)
    end
  end
end
