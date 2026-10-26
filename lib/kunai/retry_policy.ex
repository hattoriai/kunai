defmodule Kunai.RetryPolicy do
  @moduledoc """
  When a delivery that failed is tried again, and when it gives up.

  An attempt's outcome is `{:status, code, retry_after}`, the response's
  status and its `Retry-After` in seconds (or nil), or `{:error, reason}`,
  when there was no response (a timeout, a refused connection).

    * `Kunai.RetryPolicy.Default` - about three days, the default.
    * A module of the app's, of this behaviour.
  """

  @type outcome :: {:status, 100..599, non_neg_integer() | nil} | {:error, term()}

  @doc "After the attempt of this number failed: in how many seconds the next, or give up."
  @callback next(attempt :: pos_integer(), outcome(), opts :: keyword()) ::
              {:retry, non_neg_integer()} | :give_up
end

defmodule Kunai.RetryPolicy.Default do
  @moduledoc """
  Twelve attempts over about three days: the first at once, then after 5
  seconds, 5 minutes, 30 minutes, 2 hours, 5 hours, 10 hours, and five
  times after 12 hours, each a tenth earlier or later at random, so the
  retries of an endpoint that was down do not all come at once.

  A `Retry-After` longer than the next wait is obeyed, up to a day. Every
  failure but a 410 is tried again, a timeout as well as a 400: the
  endpoint's mistake may be fixed in the meantime. Options: `:schedule`,
  the waits in seconds, and `:jitter` (0.1).
  """

  @behaviour Kunai.RetryPolicy

  @schedule [5, 300, 1_800, 7_200, 18_000, 36_000, 43_200, 43_200, 43_200, 43_200, 43_200]

  @impl Kunai.RetryPolicy
  def next(attempt, outcome, opts) do
    schedule = Keyword.get(opts, :schedule, @schedule)

    case Enum.at(schedule, attempt - 1) do
      nil -> :give_up
      wait -> {:retry, max(jitter(wait, Keyword.get(opts, :jitter, 0.1)), retry_after(outcome))}
    end
  end

  defp jitter(wait, 0), do: wait
  defp jitter(wait, ratio), do: round(wait * (1 - ratio + :rand.uniform() * 2 * ratio))

  defp retry_after({:status, _code, seconds}) when is_integer(seconds), do: min(seconds, 86_400)
  defp retry_after(_outcome), do: 0
end
