defmodule Kunai.Workers.Prune do
  @moduledoc """
  Deletes the events, deliveries and attempts older than `:retention_days`
  (`Kunai.prune/1`), in a cron job of the app's Oban:

      config :my_app, Oban,
        queues: [kunai: 20],
        plugins: [{Oban.Plugins.Cron, crontab: [{"17 3 * * *", Kunai.Workers.Prune}]}]

  The audit log is kept.
  """

  use Oban.Worker, queue: :kunai, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    days = Map.get(args, "days", Kunai.Config.retention_days())
    {:ok, _counts} = Kunai.prune(days)
    :ok
  end
end
