defmodule Kunai.Stats do
  @moduledoc """
  How an owner's deliveries went over the last hours: what the pages chart,
  and an app's own pages may show.

      Kunai.Stats.summary(scope)
      #=> %{total: 412, succeeded: 405, failed: 2, retrying: 1, pending: 4,
      #     success_rate: 0.993, average_ms: 182,
      #     hours: [%{at: ~U[...], succeeded: 18, failed: 0, retrying: 0, pending: 0}, ...]}

  A delivery is counted by its state: `succeeded`, `failed` (given up),
  `retrying` (tried, failed, and to be tried again) or `pending` (not tried
  yet). The success rate is of those tried: a delivery retrying counts
  against it until it succeeds.

  Counted in the database, by hour, on PostgreSQL and SQLite.
  """

  import Ecto.Query

  alias Kunai.{Attempt, Config, Delivery, Owner}

  @type hour :: %{
          at: DateTime.t(),
          succeeded: non_neg_integer(),
          failed: non_neg_integer(),
          retrying: non_neg_integer(),
          pending: non_neg_integer()
        }
  @type t :: %{
          total: non_neg_integer(),
          succeeded: non_neg_integer(),
          failed: non_neg_integer(),
          retrying: non_neg_integer(),
          pending: non_neg_integer(),
          success_rate: float() | nil,
          average_ms: non_neg_integer() | nil,
          hours: [hour()]
        }

  @doc """
  The deliveries of a scope over the last `:hours` (24), by hour, oldest
  first. `:endpoint_id` counts one endpoint's only.
  """
  @spec summary(term(), keyword()) :: t()
  def summary(scope, opts \\ []) do
    {since, buckets} = buckets(Keyword.get(opts, :hours, 24))
    owner = Owner.of(scope)

    rows =
      Delivery
      |> Owner.where(owner)
      |> where([d], d.inserted_at >= ^since)
      |> by_endpoint_id(opts[:endpoint_id])
      |> by_hour()
      |> select_merge([d], %{endpoint_id: nil})
      |> Config.repo().all(Config.repo_opts())

    summarize(rows, buckets, average_ms(owner, since, opts[:endpoint_id]))
  end

  @doc """
  The same, for each endpoint of a scope: a map of its id to its summary,
  without the response times.
  """
  @spec by_endpoint(term(), keyword()) :: %{String.t() => t()}
  def by_endpoint(scope, opts \\ []) do
    {since, buckets} = buckets(Keyword.get(opts, :hours, 24))

    Delivery
    |> Owner.where(Owner.of(scope))
    |> where([d], d.inserted_at >= ^since)
    |> by_hour()
    |> group_by([d], d.endpoint_id)
    |> select_merge([d], %{endpoint_id: d.endpoint_id})
    |> Config.repo().all(Config.repo_opts())
    |> Enum.group_by(& &1.endpoint_id)
    |> Map.new(fn {id, rows} -> {id, summarize(rows, buckets, nil)} end)
  end

  defp by_endpoint_id(query, nil), do: query
  defp by_endpoint_id(query, id), do: where(query, [d], d.endpoint_id == ^id)

  # Counts by hour and state. The hour is a fragment of each database's,
  # written as ISO 8601 so both give the same strings.
  defp by_hour(query) do
    query
    |> group_by([d], [selected_as(:hour), selected_as(:state)])
    |> select([d], %{
      state:
        selected_as(
          fragment(
            "CASE WHEN ? = 'pending' AND ? > 0 THEN 'retrying' ELSE ? END",
            d.status,
            d.attempts,
            d.status
          ),
          :state
        ),
      count: count(d.id)
    })
    |> select_merge(^%{hour: hour(Config.repo().__adapter__())})
  end

  defp hour(Ecto.Adapters.SQLite3),
    do:
      dynamic(
        [d],
        selected_as(fragment("strftime('%Y-%m-%dT%H:00:00Z', ?)", d.inserted_at), :hour)
      )

  defp hour(_postgres) do
    dynamic(
      [d],
      selected_as(
        fragment(~S|to_char(date_trunc('hour', ?), 'YYYY-MM-DD"T"HH24:00:00"Z"')|, d.inserted_at),
        :hour
      )
    )
  end

  defp buckets(hours) do
    now = DateTime.utc_now()
    this_hour = %{now | minute: 0, second: 0, microsecond: {0, 6}}
    since = DateTime.add(this_hour, -(hours - 1) * 3_600, :second)
    {since, for(n <- 0..(hours - 1), do: DateTime.add(since, n * 3_600, :second))}
  end

  defp summarize(rows, buckets, average_ms) do
    counts =
      Enum.reduce(rows, %{}, fn row, acc ->
        Map.update(acc, {row.hour, row.state}, row.count, &(&1 + row.count))
      end)

    hours =
      for at <- buckets do
        key = DateTime.to_iso8601(%{at | microsecond: {0, 0}})

        %{
          at: at,
          succeeded: counts[{key, "succeeded"}] || 0,
          failed: counts[{key, "failed"}] || 0,
          retrying: counts[{key, "retrying"}] || 0,
          pending: counts[{key, "pending"}] || 0
        }
      end

    succeeded = Enum.sum_by(hours, & &1.succeeded)
    failed = Enum.sum_by(hours, & &1.failed)
    retrying = Enum.sum_by(hours, & &1.retrying)
    pending = Enum.sum_by(hours, & &1.pending)
    tried = succeeded + failed + retrying

    %{
      total: tried + pending,
      succeeded: succeeded,
      failed: failed,
      retrying: retrying,
      pending: pending,
      success_rate: if(tried > 0, do: succeeded / tried),
      average_ms: average_ms,
      hours: hours
    }
  end

  defp average_ms(owner, since, endpoint_id) do
    Attempt
    |> join(:inner, [a], d in Delivery, on: d.id == a.delivery_id)
    |> where([a], a.created_at >= ^since)
    |> then(fn query ->
      if owner,
        do: where(query, [_a, d], d.owner == ^owner),
        else: where(query, [_a, d], is_nil(d.owner))
    end)
    |> then(&if(endpoint_id, do: where(&1, [a], a.endpoint_id == ^endpoint_id), else: &1))
    |> select([a], avg(a.duration_ms))
    |> Config.repo().one(Config.repo_opts())
    |> case do
      nil -> nil
      %Decimal{} = average -> average |> Decimal.round() |> Decimal.to_integer()
      average -> round(average)
    end
  end
end
