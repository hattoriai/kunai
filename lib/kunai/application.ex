defmodule Kunai.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The counter of the ids made on this node (Kunai.ID).
    :persistent_term.put(Kunai.ID, :atomics.new(1, signed: false))

    children = [
      # The subscriptions of each owner, cached in ETS.
      Kunai.Subscriptions,
      # The endpoints left alone for a while after failing.
      Kunai.CircuitBreaker
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Kunai.Supervisor)
  end
end
