defmodule Kunai.Workers.Recover do
  @moduledoc """
  Gives a new job to the deliveries whose job was lost (`Kunai.recover/1`),
  in a cron job of the app's Oban, every few minutes:

      config :my_app, Oban,
        queues: [kunai: 20],
        plugins: [
          Oban.Plugins.Lifeline,
          {Oban.Plugins.Cron,
           crontab: [
             {"*/5 * * * *", Kunai.Workers.Recover},
             {"17 3 * * *", Kunai.Workers.Prune}
           ]}
        ]
  """

  use Oban.Worker, queue: :kunai, max_attempts: 3, unique: [period: 60]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Kunai.recover(Map.get(args, "grace", 300))
    :ok
  end
end
