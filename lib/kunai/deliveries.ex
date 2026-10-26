defmodule Kunai.Deliveries do
  @moduledoc """
  Deliveries and their attempts, by scope: listed, fetched, sent again.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Kunai.{Config, Delivery, Endpoint, Event, Owner, Page}
  alias Kunai.Workers.Deliver

  @doc """
  A scope's deliveries, newest first (`Kunai.Page`). Options:
  `:endpoint_id`, `:event_id`, `:status`, and those of `Kunai.Page`.
  """
  @spec list(term(), keyword()) :: Page.t(Delivery.t())
  def list(scope, opts \\ []) do
    Delivery
    |> Owner.where(Owner.of(scope))
    |> filter(:endpoint_id, opts[:endpoint_id])
    |> filter(:event_id, opts[:event_id])
    |> filter(:status, opts[:status])
    |> Page.fetch(opts)
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [d], field(d, ^field) == ^value)

  @doc "A delivery of a scope, with its attempts, or nil."
  @spec get(term(), String.t()) :: Delivery.t() | nil
  def get(scope, id) do
    Delivery
    |> Owner.where(Owner.of(scope))
    |> where([d], d.id == ^id)
    |> preload(attempt_log: ^from(a in Kunai.Attempt, order_by: a.number))
    |> Config.repo().one(Config.repo_opts())
  end

  @doc """
  Sends a delivery again, now, with the same `webhook-id`: one that failed,
  or one that succeeded and that its receiver lost. Its attempts go on
  from their number.
  """
  @spec retry(term(), Delivery.t()) :: {:ok, Delivery.t()} | {:error, term()}
  def retry(_scope, %Delivery{} = delivery) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.update(
      :delivery,
      Ecto.Changeset.change(delivery, status: "pending", next_attempt_at: now, completed_at: nil),
      Config.repo_opts()
    )
    |> then(&Oban.insert(Config.oban(), &1, :job, job(delivery.id)))
    |> Config.repo().transaction()
    |> case do
      {:ok, %{delivery: delivery}} -> {:ok, delivery}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Sends again an endpoint's deliveries of a time: after it was down, or
  disabled and enabled again. Options: `:from` and `:to` (`DateTime`s of
  when the deliveries were made; the last 24 hours by default), and
  `:status` (`"failed"`). Gives how many.
  """
  @spec replay(term(), Endpoint.t(), keyword()) :: {:ok, non_neg_integer()}
  def replay(_scope, %Endpoint{} = endpoint, opts \\ []) do
    to = Keyword.get_lazy(opts, :to, &DateTime.utc_now/0)
    from = Keyword.get_lazy(opts, :from, fn -> DateTime.add(to, -86_400, :second) end)
    status = Keyword.get(opts, :status, "failed")

    ids =
      Delivery
      |> where([d], d.endpoint_id == ^endpoint.id and d.status == ^status)
      |> where([d], d.inserted_at >= ^from and d.inserted_at <= ^to)
      |> select([d], d.id)
      |> Config.repo().all(Config.repo_opts())

    ids
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      now = DateTime.utc_now()

      Multi.new()
      |> Multi.update_all(
        :deliveries,
        where(Delivery, [d], d.id in ^chunk),
        [set: [status: "pending", next_attempt_at: now, completed_at: nil, updated_at: now]],
        Config.repo_opts()
      )
      |> then(&Oban.insert_all(Config.oban(), &1, :jobs, Enum.map(chunk, fn id -> job(id) end)))
      |> Config.repo().transaction()
    end)

    {:ok, length(ids)}
  end

  @doc """
  Sends a test to one endpoint: an event of this type (`"kunai.ping"`
  by default) with the example of the catalog (`:example` of
  `Kunai.Catalog.event/2`), marked `"test": true`, delivered to it only.
  """
  @spec send_test(term(), Endpoint.t(), String.t()) :: {:ok, Delivery.t()} | {:error, term()}
  def send_test(scope, %Endpoint{} = endpoint, type \\ "kunai.ping") do
    catalog = Config.catalog()

    case catalog.event_type(type) do
      nil ->
        {:error, :unknown_event}

      event_type ->
        event =
          Kunai.Events.build(catalog, event_type, event_type.example || %{}, endpoint.owner,
            scope: scope,
            test: true
          )

        Multi.new()
        |> Multi.insert(:event, event, Config.repo_opts())
        |> Multi.insert(
          :delivery,
          fn %{event: event} -> new(event, endpoint) end,
          Config.repo_opts()
        )
        |> then(
          &Oban.insert(Config.oban(), &1, :job, fn %{delivery: delivery} -> job(delivery.id) end)
        )
        |> Config.repo().transaction()
        |> case do
          {:ok, %{delivery: delivery}} ->
            Kunai.Broadcast.endpoint(endpoint.id, {:kunai_delivery, delivery.event_id})
            {:ok, delivery}

          {:error, _step, reason, _changes} ->
            {:error, reason}
        end
    end
  end

  @doc false
  def new(%Event{} = event, %Endpoint{} = endpoint) do
    now = DateTime.utc_now()

    %Delivery{
      id: Kunai.ID.generate("msg"),
      event_id: event.id,
      endpoint_id: endpoint.id,
      owner: endpoint.owner,
      event_type: event.type,
      status: "pending",
      next_attempt_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  @doc false
  def job(delivery_id, opts \\ []),
    do: Deliver.new(%{"delivery_id" => delivery_id}, Keyword.put(opts, :queue, Config.queue()))

  @doc false
  # Pending deliveries overdue by more than `grace` seconds have lost their
  # job (its node stopped, or it was discarded): each gets a new one. A
  # delivery that waits keeps next_attempt_at ahead (Kunai.Sender), and
  # a job too many finds the delivery claimed, and goes away.
  def recover(grace) do
    cutoff = DateTime.add(DateTime.utc_now(), -grace, :second)

    ids =
      Delivery
      |> where([d], d.status == "pending" and d.next_attempt_at < ^cutoff)
      |> order_by([d], d.next_attempt_at)
      |> limit(1_000)
      |> select([d], d.id)
      |> Config.repo().all(Config.repo_opts())

    if ids != [], do: Oban.insert_all(Config.oban(), Enum.map(ids, &job/1))
    length(ids)
  end

  @doc false
  # A pending delivery due now, with a job of its own: jobs it had for later
  # find it done, or not due, and go away (Kunai.Sender).
  def kick(delivery_id) do
    now = DateTime.utc_now()

    Delivery
    |> where([d], d.id == ^delivery_id and d.status == "pending")
    |> Config.repo().update_all([set: [next_attempt_at: now]], Config.repo_opts())

    {:ok, _job} = Oban.insert(Config.oban(), job(delivery_id))
    :ok
  end
end
