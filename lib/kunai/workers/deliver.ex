defmodule Kunai.Workers.Deliver do
  @moduledoc """
  One attempt of a delivery (`Kunai.Sender`). A failed attempt schedules
  the next as a job of its own, when the retry policy says
  (`Kunai.RetryPolicy`); Oban's own retries are for a job that crashed
  before its attempt was kept. A job that finds its delivery done, or not
  due, goes away: the attempt is claimed in the database.
  """

  use Oban.Worker, queue: :kunai, max_attempts: 5

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}}),
    do: Kunai.Sender.attempt(delivery_id)
end
