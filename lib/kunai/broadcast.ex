defmodule Kunai.Broadcast do
  @moduledoc false
  # What the pages watch live: an endpoint's deliveries, made and tried, on
  # Kunai's `:pubsub`.

  # Phoenix.PubSub is called only with a `:pubsub`.
  @compile {:no_warn_undefined, Phoenix.PubSub}

  def topic(endpoint_id), do: "kunai:endpoint:" <> endpoint_id

  def endpoint(endpoint_id, message) do
    if pubsub = Kunai.Config.pubsub(),
      do: Phoenix.PubSub.broadcast(pubsub, topic(endpoint_id), message)

    :ok
  end

  def subscribe(endpoint_id) do
    case Kunai.Config.pubsub() do
      nil -> :error
      pubsub -> Phoenix.PubSub.subscribe(pubsub, topic(endpoint_id))
    end
  end
end
