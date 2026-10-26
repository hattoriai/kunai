defmodule Kunai.Workers.Fanout do
  @moduledoc """
  An event's fan-out (`Kunai.Dispatcher`), inserted with the event in the
  transaction of its change (`Kunai.emit/4`): it runs once that commits,
  and never for a change rolled back.
  """

  use Oban.Worker, queue: :kunai, max_attempts: 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}), do: Kunai.Dispatcher.fanout(event_id)
end
