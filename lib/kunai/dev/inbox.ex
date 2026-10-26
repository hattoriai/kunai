defmodule Kunai.Dev.Inbox do
  @moduledoc """
  A place in the app itself to send webhooks to, in development: no
  tunnel, no other service. An endpoint whose URL is the inbox's receives
  as any other, and each request is kept, shown live on the pages' Inbox
  (`/inbox` under the mount), with whether its signature verifies.

  Add the plug to the app's endpoint, where only development runs it, and
  let Kunai send to the app's own address:

      # lib/my_app_web/endpoint.ex
      if code_reloading? do
        # ...
        plug Kunai.Dev.Inbox
      end

      # config/dev.exs
      config :kunai, egress: [allow_http: true, allow_private: true]

  Then an endpoint at `http://localhost:4000/dev/webhooks/inbox/billing`
  receives into the inbox called `billing`. The URL says how it answers:

    * `?status=503` - with this status (200 unsaid), to watch the retries;
    * `?delay=2000` - after so many milliseconds (at most 30 000): past
      Kunai's timeout (`:timeouts`, 15 seconds), the attempt fails.

  The plug takes `at:`, the path of the inboxes (`"/dev/webhooks/inbox"`).
  The inbox keeps the last 200 requests, in memory, until the app stops.
  """

  @behaviour Plug

  import Ecto.Query
  import Plug.Conn

  alias Kunai.{Config, Endpoint}

  alias Kunai.Dev.Inbox.Store

  @max_body 1_000_000
  @max_delay 30_000

  @type request :: %{
          id: integer(),
          inbox: String.t(),
          received_at: DateTime.t(),
          headers: %{String.t() => String.t()},
          body: binary(),
          status: pos_integer(),
          event_type: String.t() | nil,
          webhook_id: String.t() | nil,
          endpoint_id: String.t() | nil,
          verified: :ok | {:error, atom()} | :unknown_endpoint
        }

  # The plug

  @impl Plug
  def init(opts),
    do: Keyword.get(opts, :at, "/dev/webhooks/inbox") |> String.split("/", trim: true)

  @impl Plug
  def call(%Plug.Conn{} = conn, at) do
    ensure_started()

    with "POST" <- conn.method,
         {^at, [inbox]} <- Enum.split(conn.path_info, length(at)) do
      receive_request(conn, inbox)
    else
      _other -> conn
    end
  end

  defp receive_request(conn, inbox) do
    {:ok, body, conn} = read_body(conn, length: @max_body)
    conn = fetch_query_params(conn)
    status = int(conn.query_params["status"], 200, 100..599)
    delay = int(conn.query_params["delay"], 0, 0..@max_delay)
    headers = Map.new(conn.req_headers)

    request =
      %{
        id: System.unique_integer([:positive, :monotonic]),
        inbox: inbox,
        received_at: DateTime.utc_now(),
        headers: headers,
        body: body,
        status: status,
        event_type: event_type(body),
        webhook_id: headers["webhook-id"]
      }
      |> Map.merge(verify(conn.request_path, body, headers))

    :ok = GenServer.call(Store, {:put, request})
    if delay > 0, do: Process.sleep(delay)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, ~s({"inbox":#{JSON.encode!(inbox)},"received":true}))
    |> halt()
  end

  defp int(nil, default, _range), do: default

  defp int(value, default, range) do
    case Integer.parse(value) do
      {n, ""} -> if n in range, do: n, else: default
      _other -> default
    end
  end

  defp event_type(body) do
    case JSON.decode(body) do
      {:ok, %{"type" => type}} when is_binary(type) -> type
      _other -> nil
    end
  end

  # The endpoints at this path, of any owner: the request is theirs when
  # one's secret verifies it.
  defp verify(path, body, headers) do
    endpoints =
      Endpoint
      |> where([e], like(e.url, ^"%#{path}%"))
      |> Config.repo().all(Config.repo_opts())
      |> Enum.filter(&(URI.parse(&1.url).path == path))

    results =
      for endpoint <- endpoints do
        secrets = Enum.reject([Kunai.secret(endpoint)], &is_nil/1)
        {endpoint.id, Kunai.Verifier.verify(body, headers, secrets)}
      end

    case Enum.find(results, &match?({_, :ok}, &1)) || List.first(results) do
      nil -> %{endpoint_id: nil, verified: :unknown_endpoint}
      {id, result} -> %{endpoint_id: id, verified: result}
    end
  end

  # What the pages read

  @doc "Whether the inbox runs: its plug is in the app's endpoint."
  @spec running?() :: boolean()
  def running?, do: is_pid(Process.whereis(Store))

  @doc "The requests received, newest first; of one inbox with `inbox:`."
  @spec list(keyword()) :: [request()]
  def list(opts \\ []) do
    if running?() do
      Store
      |> :ets.tab2list()
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&(is_nil(opts[:inbox]) or &1.inbox == opts[:inbox]))
      |> Enum.reverse()
    else
      []
    end
  end

  @doc "Forgets the requests received."
  @spec clear() :: :ok
  def clear, do: if(running?(), do: GenServer.call(Store, :clear), else: :ok)

  @doc """
  Subscribes the calling process to the requests received, on Kunai's
  `:pubsub`: `{:kunai_inbox, request}` for each.
  """
  @spec subscribe() :: :ok | {:error, :no_pubsub}
  def subscribe do
    case Config.pubsub() do
      nil -> {:error, :no_pubsub}
      pubsub -> Phoenix.PubSub.subscribe(pubsub, "kunai:inbox")
    end
  end

  @doc false
  defdelegate ensure_started, to: Store
end

defmodule Kunai.Dev.Inbox.Store do
  @moduledoc false
  # The inbox's requests, the last 200, in an ETS table of its own, and
  # their broadcast to the pages.

  use GenServer

  alias Kunai.Config

  @table __MODULE__
  @keep 200

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  # Started under Kunai's supervisor by the plug's first request, so the
  # plug is all an app adds.
  @doc false
  def ensure_started do
    unless Process.whereis(__MODULE__) do
      case Supervisor.start_child(Kunai.Supervisor, {__MODULE__, []}) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, :already_present} -> Supervisor.restart_child(Kunai.Supervisor, __MODULE__)
      end
    end

    :ok
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :ordered_set, :protected, read_concurrency: true])
    {:ok, nil}
  end

  @impl GenServer
  def handle_call({:put, request}, _from, state) do
    :ets.insert(@table, {request.id, request})

    if :ets.info(@table, :size) > @keep do
      oldest = :ets.first(@table)
      :ets.delete(@table, oldest)
    end

    if pubsub = Config.pubsub(),
      do: Phoenix.PubSub.broadcast(pubsub, "kunai:inbox", {:kunai_inbox, request})

    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table)

    if pubsub = Config.pubsub(),
      do: Phoenix.PubSub.broadcast(pubsub, "kunai:inbox", :kunai_inbox_cleared)

    {:reply, :ok, state}
  end
end
