defmodule Kunai.API.Helpers do
  @moduledoc false
  # What every controller of the API does: the scope, lists, errors.

  import Plug.Conn

  @doc false
  def require_scope(conn, _opts) do
    case Kunai.Web.scope(conn) do
      {:ok, scope} ->
        assign(conn, :kunai_scope, scope)

      :error ->
        conn
        |> error(
          401,
          "authentication_error",
          "unauthenticated",
          "No scope was found for this request."
        )
        |> halt()
    end
  end

  @doc false
  def respond(conn, status \\ 200, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Kunai.Config.serializer().encode!(body))
  end

  @doc false
  def list(conn, %Kunai.Page{} = page, fun) do
    respond(conn, %{
      "object" => "list",
      "url" => conn.request_path,
      "has_more" => page.has_more,
      "data" => Enum.map(page.data, fun)
    })
  end

  @doc false
  def error(conn, status, type, code, message, extra \\ %{}) do
    respond(conn, status, %{
      "error" => Map.merge(%{"type" => type, "code" => code, "message" => message}, extra)
    })
  end

  @doc false
  def not_found(conn, what),
    do: error(conn, 404, "invalid_request_error", "resource_missing", "No such #{what}.")

  @doc false
  def invalid(conn, %Ecto.Changeset{} = changeset) do
    errors = Ecto.Changeset.traverse_errors(changeset, &Kunai.Web.error_message/1)

    {param, [message | _rest]} =
      Enum.min_by(errors, fn {field, _messages} -> to_string(field) end)

    error(conn, 400, "invalid_request_error", "parameter_invalid", "#{param} #{message}", %{
      "param" => to_string(param),
      "errors" => errors
    })
  end

  @doc false
  # The options of a list: limit and cursors, and its filters.
  def page_opts(params, filters \\ []) do
    base = [
      limit: integer(params["limit"], 25),
      starting_after: params["starting_after"],
      ending_before: params["ending_before"]
    ]

    filters = for {param, key} <- filters, value = params[param], do: {key, value}
    Enum.reject(base ++ filters, fn {_key, value} -> is_nil(value) end)
  end

  @doc false
  def integer(nil, default), do: default
  def integer(value, _default) when is_integer(value), do: value

  def integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end

  def integer(_value, default), do: default

  @doc false
  def expand(params) do
    case params["expand"] do
      list when is_list(list) -> list
      one when is_binary(one) -> [one]
      _none -> []
    end
  end
end
