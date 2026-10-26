defmodule Kunai.Plug.Verify do
  @moduledoc """
  A plug for the app that receives webhooks: it checks a request's
  signature (`Kunai.Verifier`) and gives its event, or answers 400.

      pipeline :webhooks do
        plug :accepts, ["json"]
      end

      scope "/webhooks" do
        pipe_through :webhooks
        post "/acme", MyAppWeb.AcmeWebhookController, :create
      end

      # in the controller
      plug Kunai.Plug.Verify, secrets: {MyApp.Acme, :webhook_secrets, []}

      def create(conn, _params) do
        %{"type" => type, "data" => data} = conn.assigns.webhook
        ...
      end

  The signature is of the body as it was sent, before `Plug.Parsers`
  read it: give the endpoint's parsers `PhoenixMountable.RawBody` as
  their body reader, as Kunai's installer does, or put the body in
  `conn.assigns.raw_body` with a reader of yours.

  Options:

    * `:secrets` - required: a list (`["whsec_…"]`), or an `{m, f, a}` or
      a function of the conn that gives one, read at each request.
    * `:tolerance` - seconds a timestamp may be from now (300).
    * `:max_bytes` - the largest body read (1 MB).
    * `:assign` - where the event goes (`:webhook`), decoded.
  """

  @behaviour Plug

  use PhoenixMountable.RawBody

  import Plug.Conn

  @impl Plug
  def init(opts) do
    unless Keyword.has_key?(opts, :secrets),
      do: raise(ArgumentError, "Kunai.Plug.Verify needs :secrets")

    opts
  end

  @impl Plug
  def call(conn, opts) do
    with {:ok, body, conn} <- raw_body(conn, Keyword.get(opts, :max_bytes, 1_000_000)),
         :ok <- Kunai.Verifier.verify(body, conn.req_headers, secrets(conn, opts[:secrets]), opts),
         {:ok, event} <- decode(body) do
      assign(conn, Keyword.get(opts, :assign, :webhook), event)
    else
      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, JSON.encode!(%{error: to_string(reason)}))
        |> halt()
    end
  end

  defp raw_body(%Plug.Conn{assigns: %{raw_body: body}} = conn, _max) when is_binary(body),
    do: {:ok, body, conn}

  defp raw_body(conn, max) do
    case PhoenixMountable.RawBody.fetch(conn, max) do
      {:ok, body, conn} -> {:ok, body, conn}
      _error -> {:error, :body_not_kept}
    end
  end

  defp secrets(_conn, secrets) when is_list(secrets), do: secrets
  defp secrets(conn, fun) when is_function(fun, 1), do: fun.(conn)
  defp secrets(_conn, {m, f, a}), do: apply(m, f, a)

  defp decode(body) do
    case JSON.decode(body) do
      {:ok, event} -> {:ok, event}
      {:error, _error} -> {:error, :invalid_json}
    end
  end
end
