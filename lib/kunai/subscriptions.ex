defmodule Kunai.Subscriptions do
  @moduledoc """
  Which endpoints receive an event: those of its owner, enabled, whose
  `:events` match its name. An endpoint subscribes to a name
  (`"page.published"`), a family (`"page.*"`, every name that starts with
  `page.`), or `"*"`.

  The answer is kept in an ETS table on each node, by owner and name, so
  an event's fan-out asks the database once for many events. A change to
  an owner's endpoints clears that owner's answers on the node, and on
  every node of the cluster when Kunai has a `:pubsub`
  (`Kunai.Config`). An answer is also forgotten after a minute, so a node
  that missed a message is not wrong for long.
  """

  use GenServer

  import Ecto.Query

  alias Kunai.{Config, Endpoint}

  # Phoenix.PubSub is optional: it is called only with a `:pubsub`.
  @compile {:no_warn_undefined, Phoenix.PubSub}

  @table __MODULE__
  @topic "kunai:subscriptions"
  @ttl_ms 60_000

  @doc "Whether a pattern of an endpoint's `:events` matches an event's name."
  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?("*", _type), do: true

  def matches?(pattern, type) do
    case String.split_at(pattern, -2) do
      {family, ".*"} -> String.starts_with?(type, family <> ".")
      _exact -> pattern == type
    end
  end

  @doc "The patterns that match no event of the catalog."
  @spec unknown([String.t()]) :: [String.t()]
  def unknown(patterns) do
    names = Config.catalog().__kunai__(:events) |> Map.keys() |> List.delete("kunai.ping")
    Enum.reject(patterns, fn pattern -> Enum.any?(names, &matches?(pattern, &1)) end)
  end

  @doc "The enabled endpoints of an owner subscribed to an event's name."
  @spec endpoints(String.t() | nil, String.t()) :: [Endpoint.t()]
  def endpoints(owner, type) do
    key = {owner, type}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, at, endpoints}] when now - at < @ttl_ms ->
        endpoints

      _missing ->
        endpoints =
          Enum.filter(enabled(owner), fn ep -> Enum.any?(ep.events, &matches?(&1, type)) end)

        :ets.insert(@table, {key, now, endpoints})
        endpoints
    end
  end

  defp enabled(owner) do
    Endpoint
    |> where([e], e.status == "enabled")
    |> by_owner(owner)
    |> Config.repo().all(Config.repo_opts())
  end

  defp by_owner(query, nil), do: where(query, [e], is_nil(e.owner))
  defp by_owner(query, owner), do: where(query, [e], e.owner == ^owner)

  @doc "Forgets the answers of an owner, on this node and, with a `:pubsub`, on the others."
  @spec invalidate(String.t() | nil) :: :ok
  def invalidate(owner) do
    forget(owner)

    if pubsub = Config.pubsub() do
      Phoenix.PubSub.broadcast_from(pubsub, self(), @topic, {:kunai_invalidate, owner})
    end

    :ok
  end

  defp forget(owner), do: :ets.match_delete(@table, {{owner, :_}, :_, :_})

  # The table's owner, and the listener of the other nodes' changes.

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{subscribed: false}, {:continue, :subscribe}}
  end

  @impl true
  # The app's PubSub starts after Kunai: subscribed once it is there.
  def handle_continue(:subscribe, state), do: {:noreply, subscribe(state)}

  @impl true
  def handle_info(:subscribe, state), do: {:noreply, subscribe(state)}

  def handle_info({:kunai_invalidate, owner}, state) do
    forget(owner)
    {:noreply, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp subscribe(state) do
    case Config.pubsub() do
      nil ->
        state

      pubsub ->
        if Process.whereis(pubsub) do
          :ok = Phoenix.PubSub.subscribe(pubsub, @topic)
          %{state | subscribed: true}
        else
          Process.send_after(self(), :subscribe, 1_000)
          state
        end
    end
  end
end
