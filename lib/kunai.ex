defmodule Kunai do
  @moduledoc """
  Webhooks for Phoenix: your app's events, kept, signed, delivered and
  retried, to the endpoints your users give it.

      defmodule MyApp.Webhooks do
        use Kunai.Catalog

        event "page.published", scopes: ["pages:read"], schema: [id: :string, title: :string]

        @impl Kunai.Catalog
        def owner(%MyApp.Accounts.Scope{site: site}), do: "site:\#{site.id}"
      end

      # In the transaction of the change:
      require MyApp.Webhooks

      Ecto.Multi.new()
      |> Ecto.Multi.update(:page, Page.publish_changeset(page))
      |> MyApp.Webhooks.emit("page.published", & &1.page, scope: scope)
      |> Repo.transaction()

  An event is kept once (`Kunai.Event`), in the transaction of its change.
  Once that commits, it fans out (`Kunai.Dispatcher`): a delivery
  (`Kunai.Delivery`) for each endpoint of its owner that subscribes to it
  and may see it. Each delivery is signed as Standard Webhooks says
  (`Kunai.Signature`), sent to an address that was checked
  (`Kunai.Egress`), and tried again for about three days
  (`Kunai.RetryPolicy`); an endpoint that keeps failing is disabled, its
  owner told (`Kunai.Notifier`).

  The functions here take the scope of the person acting first, as a
  Phoenix 1.8 context does: what they reach is their owner's
  (`c:Kunai.Catalog.owner/1`), and the audit log says they did it. A
  string is an owner itself, and nil the app's own endpoints.

  See `Kunai.Config` for the configuration and `Kunai.Telemetry` for the
  events emitted.
  """

  import Ecto.Query

  alias Kunai.{Config, Deliveries, Endpoints, Events}

  @doc """
  Adds an event to a transaction, with the job of its fan-out: a change
  rolled back sends nothing, and a change committed always sends.

  `data` is the event's object, a map (or a struct JSON encodes), or a
  function of the transaction's changes so far. The catalog's
  `emit/4` macro calls this, after checking the name when the app
  compiles.

  Options:

    * `:scope` - whose change it is: gives the owner and the actor.
    * `:owner` and `:actor` - given, rather than from a scope.
    * `:previous` - the fields that changed, as they were before.
    * `:as` - the name of the step in the `Ecto.Multi`, which holds the
      `Kunai.Event`.

  The transaction must run in the repo of the app's Oban.
  """
  @spec emit(Ecto.Multi.t(), String.t(), map() | (map() -> map()), keyword()) :: Ecto.Multi.t()
  def emit(%Ecto.Multi{} = multi, type, data, opts \\ []),
    do: Events.emit(Config.catalog(), multi, type, data, opts)

  @doc false
  def emit(catalog, %Ecto.Multi{} = multi, type, data, opts),
    do: Events.emit(catalog, multi, type, data, opts)

  @doc """
  Emits an event in a transaction of its own: for a change that is not in
  the database. Gives the event, or raises.
  """
  @spec emit!(String.t(), map(), keyword()) :: Kunai.Event.t()
  def emit!(type, data, opts \\ []) do
    opts = Keyword.put(opts, :as, :event)

    case Ecto.Multi.new() |> emit(type, data, opts) |> Config.repo().transaction() do
      {:ok, %{event: event}} ->
        event

      {:error, _step, reason, _changes} ->
        raise ArgumentError, "Kunai could not emit #{type}: #{inspect(reason)}"
    end
  end

  # Endpoints

  defdelegate create_endpoint(scope, attrs, opts \\ []), to: Endpoints, as: :create
  defdelegate list_endpoints(scope, opts \\ []), to: Endpoints, as: :list
  defdelegate get_endpoint(scope, id), to: Endpoints, as: :get
  defdelegate update_endpoint(scope, endpoint, attrs), to: Endpoints, as: :update
  defdelegate delete_endpoint(scope, endpoint), to: Endpoints, as: :delete
  defdelegate enable_endpoint(scope, endpoint), to: Endpoints, as: :enable
  defdelegate disable_endpoint(scope, endpoint), to: Endpoints, as: :disable
  defdelegate roll_secret(scope, endpoint, opts \\ []), to: Endpoints
  defdelegate secret(endpoint), to: Endpoints

  # Events and deliveries

  defdelegate list_events(scope, opts \\ []), to: Events, as: :list
  defdelegate get_event(scope, id), to: Events, as: :get
  defdelegate list_deliveries(scope, opts \\ []), to: Deliveries, as: :list
  defdelegate get_delivery(scope, id), to: Deliveries, as: :get
  defdelegate retry_delivery(scope, delivery), to: Deliveries, as: :retry
  defdelegate replay(scope, endpoint, opts \\ []), to: Deliveries
  defdelegate send_test(scope, endpoint, type \\ "kunai.ping"), to: Deliveries
  defdelegate list_audit_log(scope, opts \\ []), to: Kunai.Audit, as: :list

  @doc """
  Deletes the events older than `days`, with their deliveries and
  attempts, and the attempts older than that of newer deliveries. The
  audit log is kept. The API's idempotency keys older than a day go too.
  Gives how many events and attempts (`Kunai.Workers.Prune`).
  """
  @spec prune(pos_integer()) :: {:ok, %{events: non_neg_integer(), attempts: non_neg_integer()}}
  def prune(days \\ Config.retention_days()) when is_integer(days) and days > 0 do
    before = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
    repo = Config.repo()

    {attempts, _rows} =
      Kunai.Attempt |> where([a], a.created_at < ^before) |> repo.delete_all(Config.repo_opts())

    {events, _rows} =
      Kunai.Event |> where([e], e.created_at < ^before) |> repo.delete_all(Config.repo_opts())

    # The API's idempotency keys are kept a day (Kunai.API.Idempotency).
    day_ago = DateTime.add(DateTime.utc_now(), -86_400, :second)

    Kunai.IdempotencyKey
    |> where([k], k.created_at < ^day_ago)
    |> repo.delete_all(Config.repo_opts())

    {:ok, %{events: events, attempts: attempts}}
  end
end
