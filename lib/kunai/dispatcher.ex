defmodule Kunai.Dispatcher do
  @moduledoc """
  An event's fan-out: a delivery for each endpoint of its owner that
  subscribes to it (`Kunai.Subscriptions`) and may see it
  (`Kunai.Authorizer`), and a job for each. Run once the event's
  transaction committed (`Kunai.Workers.Fanout`); run twice, it makes no
  delivery twice.
  """

  alias Ecto.Multi
  alias Kunai.{Config, Deliveries, Delivery, Event, Subscriptions, Telemetry}

  @doc false
  def fanout(event_id) do
    case Config.repo().get(Event, event_id, Config.repo_opts()) do
      nil -> :ok
      event -> fanout_event(event)
    end
  end

  defp fanout_event(event) do
    catalog = Config.catalog()

    Telemetry.span(:fanout, %{event_id: event.id, type: event.type}, fn ->
      count =
        case catalog.event_type(event.type) do
          # A type the catalog no longer has is sent nowhere.
          nil -> 0
          type -> insert(event, recipients(event, type))
        end

      {:ok, %{event_id: event.id, type: event.type, deliveries: count}}
    end)
  end

  defp recipients(event, type) do
    {authorizer, opts} = Config.authorizer()

    event.owner
    |> Subscriptions.endpoints(event.type)
    |> Enum.filter(&authorizer.allow?(&1, event, type, opts))
  end

  defp insert(_event, []), do: 0

  defp insert(event, endpoints) do
    rows = Enum.map(endpoints, &(event |> Deliveries.new(&1) |> row()))

    {:ok, %{deliveries: {count, _inserted}}} =
      Multi.new()
      |> Multi.insert_all(
        :deliveries,
        Delivery,
        rows,
        Config.repo_opts() ++
          [on_conflict: :nothing, conflict_target: [:event_id, :endpoint_id], returning: [:id]]
      )
      |> then(
        &Oban.insert_all(Config.oban(), &1, :jobs, fn %{deliveries: {_count, inserted}} ->
          Enum.map(inserted, fn delivery -> Deliveries.job(delivery.id) end)
        end)
      )
      |> Config.repo().transaction()

    count
  end

  @fields [
    :id,
    :event_id,
    :endpoint_id,
    :owner,
    :event_type,
    :status,
    :attempts,
    :next_attempt_at,
    :inserted_at,
    :updated_at
  ]

  defp row(%Delivery{} = delivery), do: Map.take(delivery, @fields)
end
