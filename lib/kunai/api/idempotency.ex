defmodule Kunai.API.Idempotency do
  @moduledoc """
  `Idempotency-Key` on the API's `POST`, `PATCH` and `DELETE`, as Stripe's:
  a client that lost a response sends the request again with the same key,
  and gets the same response, not a second endpoint.

    * The first request with a key is kept with its response, for a day
      (`Kunai.prune/1`), by owner: one owner's keys are not another's.
    * The same key again, with the same method, path and parameters, gives
      that response again, with `Idempotent-Replayed: true`.
    * The same key with other parameters is refused (`idempotency_error`,
      422); while the first is still running, the second waits its turn
      (409).
    * A response of 5xx is not kept: the request may be tried again.
  """

  @behaviour Plug

  import Ecto.Query
  import Plug.Conn

  alias Kunai.API.Helpers
  alias Kunai.{Config, IdempotencyKey, Owner}

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method} = conn, _opts) when method in ["POST", "PATCH", "DELETE"] do
    case get_req_header(conn, "idempotency-key") do
      [key | _rest] when byte_size(key) in 1..255 -> handle(conn, key)
      [_invalid | _rest] -> refuse(conn, 400, "An Idempotency-Key is 1 to 255 characters.")
      [] -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp handle(conn, key) do
    # A null owner is not unique in an index: the app's own is "".
    owner = Owner.of(conn.assigns.kunai_scope) || ""
    fingerprint = fingerprint(conn)

    row = %IdempotencyKey{
      id: Kunai.ID.generate("idk"),
      owner: owner,
      key: key,
      fingerprint: fingerprint,
      created_at: DateTime.utc_now()
    }

    changeset =
      row
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.unique_constraint([:owner, :key],
        name: :kunai_idempotency_keys_owner_key_index
      )

    case Config.repo().insert(changeset, Config.repo_opts()) do
      {:ok, row} -> register_before_send(conn, &keep(&1, row))
      {:error, _changeset} -> replay(conn, owner, key, fingerprint)
    end
  end

  defp replay(conn, owner, key, fingerprint) do
    existing =
      IdempotencyKey
      |> where([k], k.owner == ^owner and k.key == ^key)
      |> Config.repo().one(Config.repo_opts())

    cond do
      existing.fingerprint != fingerprint ->
        refuse(conn, 422, "This Idempotency-Key was used with other parameters.")

      is_nil(existing.status) ->
        refuse(conn, 409, "A request with this Idempotency-Key is still running.")

      true ->
        conn
        |> put_resp_header("idempotent-replayed", "true")
        |> put_resp_content_type("application/json")
        |> send_resp(existing.status, existing.response)
        |> halt()
    end
  end

  defp keep(conn, row) do
    repo = Config.repo()

    if conn.status >= 500 do
      repo.delete(row, Config.repo_opts())
    else
      row
      |> Ecto.Changeset.change(status: conn.status, response: IO.iodata_to_binary(conn.resp_body))
      |> repo.update(Config.repo_opts())
    end

    conn
  end

  defp fingerprint(conn) do
    params = :erlang.term_to_binary(conn.body_params, [:deterministic])

    :crypto.hash(:sha256, [conn.method, ?\s, conn.request_path, ?\s, params])
    |> Base.encode16(case: :lower)
  end

  defp refuse(conn, status, message) do
    conn
    |> Helpers.error(status, "idempotency_error", "idempotency_key_in_use", message)
    |> halt()
  end
end
