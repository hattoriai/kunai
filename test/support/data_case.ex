defmodule KunaiTest.DataCase do
  @moduledoc "Tests with the database (Ecto's sandbox) and Oban's jobs run by hand."
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import KunaiTest.DataCase
      alias KunaiTest.Transport
    end
  end

  setup _tags do
    pid = Sandbox.start_owner!(Kunai.Config.repo(), shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    # The caches of the nodes outlive a test's rows.
    :ets.delete_all_objects(Kunai.Subscriptions)
    :ets.delete_all_objects(Kunai.CircuitBreaker)
    :ok
  end

  @doc "A scope of the tests: a site and a user."
  def scope(site \\ "1", user \\ "u1"), do: %{site: site, user: user}

  @doc "An endpoint, and its secret."
  def endpoint!(attrs \\ %{}, opts \\ []) do
    scope = Keyword.get(opts, :scope, scope())

    attrs =
      Map.merge(
        %{
          url: "https://hooks.example.com/#{System.unique_integer([:positive])}",
          events: ["*"],
          scopes: ["pages:read", "members:read"]
        },
        attrs
      )

    {:ok, endpoint, secret} = Kunai.create_endpoint(scope, attrs, opts)
    {endpoint, secret}
  end

  @doc "Runs Kunai's jobs: those due, or every one with `with_scheduled: true`."
  def drain(opts \\ []) do
    Oban.drain_queue(Kunai.Config.oban(), [queue: :kunai, with_recursion: true] ++ opts)
  end

  @doc """
  Runs Kunai's jobs as time passes: each turn, the pending deliveries are
  made due, and their jobs run, until none is pending (or `turns` ran).
  """
  def drain_over_time(turns \\ 20) do
    Enum.reduce_while(1..turns, nil, fn _turn, _acc ->
      import Ecto.Query

      repo = Kunai.Config.repo()
      now = DateTime.utc_now()
      pending = from(d in Kunai.Delivery, where: d.status == "pending")
      repo.update_all(pending, set: [next_attempt_at: now])

      repo.update_all(from(j in Oban.Job, where: j.state == "scheduled"),
        set: [state: "available", scheduled_at: now]
      )

      drain()

      if repo.exists?(pending), do: {:cont, nil}, else: {:halt, nil}
    end)
  end

  @doc "Emits an event in a transaction of its own."
  def emit!(type, data, opts \\ []) do
    Kunai.emit!(type, data, Keyword.put_new(opts, :scope, scope()))
  end
end
