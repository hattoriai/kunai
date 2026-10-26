defmodule Kunai.CircuitBreaker do
  @moduledoc """
  An endpoint that failed five times in a row is left alone for a while,
  on each node: its deliveries wait without an attempt, rather than each
  waiting for its own timeout. The pause starts at 30 seconds and doubles
  with each failure after, up to ten minutes; a success closes it.

  The pause counts no attempt: a delivery keeps its retries for when the
  endpoint is back.

      config :kunai, circuit_breaker: [threshold: 5, pause: 30_000, max_pause: 600_000]

  `circuit_breaker: false` turns it off.
  """

  use GenServer

  @table __MODULE__

  @doc "Whether requests to the endpoint wait: `{:open, milliseconds}`, or `:closed`."
  @spec check(String.t()) :: :closed | {:open, pos_integer()}
  def check(endpoint_id) do
    if options(), do: check_open(endpoint_id), else: :closed
  end

  defp check_open(endpoint_id) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, endpoint_id) do
      [{_id, _failures, until}] when is_integer(until) and until > now -> {:open, until - now}
      _closed -> :closed
    end
  end

  @doc "Records how a request to the endpoint went."
  @spec record(String.t(), :ok | :error) :: :ok
  def record(endpoint_id, :ok) do
    :ets.delete(@table, endpoint_id)
    :ok
  end

  def record(endpoint_id, :error) do
    if opts = options() do
      threshold = Keyword.get(opts, :threshold, 5)
      # Open until nil: monotonic time can be negative.
      failures = :ets.update_counter(@table, endpoint_id, {2, 1}, {endpoint_id, 0, nil})

      if failures >= threshold do
        pause =
          min(
            Keyword.get(opts, :pause, 30_000) * Integer.pow(2, min(failures - threshold, 16)),
            Keyword.get(opts, :max_pause, 600_000)
          )

        :ets.update_element(@table, endpoint_id, {3, System.monotonic_time(:millisecond) + pause})
      end
    end

    :ok
  end

  defp options do
    case Application.get_env(:kunai, :circuit_breaker, []) do
      false -> nil
      opts -> opts
    end
  end

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, nil}
  end
end
