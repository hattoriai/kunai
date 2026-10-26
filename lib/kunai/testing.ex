defmodule Kunai.Testing do
  @moduledoc """
  Assertions for an app's tests: the events its changes emit, and what its
  endpoints receive.

      # config/test.exs
      config :kunai, transport: Kunai.Testing.Transport

      defmodule MyApp.PagesTest do
        use MyApp.DataCase
        import Kunai.Testing

        test "renaming a page tells the endpoints" do
          {:ok, page} = Pages.update(scope, page, %{title: "Porto trip"})

          event = assert_emitted "page.updated", %{title: "Porto trip"}
          assert event.previous == %{"title" => "Lisbon trip"}
          refute_emitted "page.archived"

          deliver()
          payload = assert_delivered "page.updated", to: endpoint
          assert payload["data"]["object"]["title"] == "Porto trip"
        end
      end

  Events are read from the app's repo, in the test's transaction. Requests
  never leave the test: `Kunai.Testing.Transport` sends each one to the
  process that ran its job, the test's when `deliver/1` runs them (or
  Oban's `testing: :inline` does), and answers as `respond/2` said.
  """

  import Ecto.Query
  import ExUnit.Assertions

  alias Kunai.{Config, Delivery, Endpoint, Event}

  @doc """
  The events emitted, oldest first: all, or those of a type. Options:
  `:owner`.
  """
  @spec emitted(String.t() | nil, keyword()) :: [Event.t()]
  def emitted(type \\ nil, opts \\ []) do
    Event
    |> then(&if type, do: where(&1, [e], e.type == ^type), else: &1)
    |> then(
      &if Keyword.has_key?(opts, :owner), do: where(&1, [e], e.owner == ^opts[:owner]), else: &1
    )
    |> order_by([e], e.id)
    |> Config.repo().all(Config.repo_opts())
  end

  @doc """
  Asserts that an event of `type` was emitted whose object has `data`'s
  fields (atom or string keys; nested maps are matched as subsets too).
  Gives the latest such event. Options: `:owner`.
  """
  @spec assert_emitted(String.t(), map(), keyword()) :: Event.t()
  def assert_emitted(type, data \\ %{}, opts \\ []) do
    expected = stringify(data)
    events = emitted(type, opts)

    case Enum.filter(events, &subset?(expected, &1.data)) do
      [] ->
        flunk("""
        No #{type} event#{if data != %{}, do: " with #{inspect(expected)}"} was emitted.

        Emitted: #{describe(emitted(nil, opts))}
        """)

      matches ->
        List.last(matches)
    end
  end

  @doc "Asserts that no event of `type` (with `data`'s fields) was emitted."
  @spec refute_emitted(String.t(), map(), keyword()) :: :ok
  def refute_emitted(type, data \\ %{}, opts \\ []) do
    expected = stringify(data)

    case Enum.filter(emitted(type, opts), &subset?(expected, &1.data)) do
      [] -> :ok
      [event | _] -> flunk("A #{type} event was emitted: #{inspect(event.data)}")
    end
  end

  @doc """
  Runs Kunai's jobs in the test's process, the fan-out and the deliveries,
  and those they make. Gives Oban's counts.

  `retries: true` first makes every delivery waiting for its next attempt
  due, so that each call is one more round of retries.
  """
  @spec deliver(keyword()) :: map()
  def deliver(opts \\ []) do
    if opts[:retries] do
      Delivery
      |> where([d], d.status == "pending" and d.attempts > 0)
      |> Config.repo().update_all(
        [set: [next_attempt_at: DateTime.utc_now()]],
        Config.repo_opts()
      )
    end

    Oban.drain_queue(Config.oban(),
      queue: Config.queue(),
      with_recursion: true,
      with_scheduled: Keyword.get(opts, :retries, false)
    )
  end

  @doc """
  What `Kunai.Testing.Transport` answers for a URL (or an endpoint), in
  turn, the last one repeated: a status, `{status, headers}` or
  `{:error, reason}`. Unsaid, 200.

      respond(endpoint, [503, 200])
  """
  @spec respond(Endpoint.t() | String.t(), term()) :: :ok
  def respond(%Endpoint{url: url}, responses), do: respond(url, responses)

  def respond(url, responses) when is_binary(url) do
    Process.put({Kunai.Testing.Transport, url}, List.wrap(responses))
    :ok
  end

  @doc """
  Asserts that a request of an event of `type` was sent, and gives its
  payload, decoded. Options:

    * `:to` - an endpoint, or its URL. Given an endpoint, the request's
      signature is verified with its secret, as its receiver would.
    * `:data` - fields its object must have.
  """
  @spec assert_delivered(String.t(), keyword()) :: map()
  def assert_delivered(type, opts \\ []) do
    requests = requests()
    url = with %Endpoint{url: url} <- opts[:to], do: url
    expected = stringify(opts[:data] || %{})
    found = Enum.find(requests, &request?(&1, type, url, expected))

    # Unmatched requests stay for the next assertion.
    for request <- requests, request != found, do: send(self(), {:kunai_request, request})

    case found do
      nil ->
        flunk(
          "No #{type} request was sent#{if url, do: " to #{url}"}.\n\nSent: #{sent(requests)}"
        )

      {_to, headers, body, payload} ->
        verified!(payload, headers, body, opts[:to])
    end
  end

  defp request?({to, _headers, _body, payload}, type, url, expected) do
    payload["type"] == type and (is_nil(url) or to == url) and
      subset?(expected, get_in(payload, ["data", "object"]) || %{})
  end

  # Given an endpoint, the request is checked as its receiver would.
  defp verified!(payload, headers, body, %Endpoint{} = endpoint) do
    secrets = Enum.reject([Kunai.secret(endpoint)], &is_nil/1)

    assert Kunai.Verifier.verify(body, headers, secrets) == :ok,
           "The request to #{endpoint.url} is not signed with its secret."

    payload
  end

  defp verified!(payload, _headers, _body, _url), do: payload

  defp sent([]), do: "none"

  defp sent(requests),
    do: Enum.map_join(requests, ", ", fn {to, _, _, p} -> "#{p["type"]} to #{to}" end)

  @doc "Asserts that no request (of an event of `type`) was sent."
  @spec refute_delivered(String.t() | nil) :: :ok
  def refute_delivered(type \\ nil) do
    requests = requests()
    for request <- requests, do: send(self(), {:kunai_request, request})

    case Enum.filter(requests, fn {_, _, _, payload} ->
           is_nil(type) or payload["type"] == type
         end) do
      [] -> :ok
      [{to, _, _, payload} | _] -> flunk("A #{payload["type"]} request was sent to #{to}.")
    end
  end

  # The requests in the test's mailbox, oldest first.
  defp requests(acc \\ []) do
    receive do
      {:kunai_request, {_to, _headers, _body, _payload} = request} -> requests([request | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp stringify(data), do: data |> JSON.encode!() |> JSON.decode!()

  defp subset?(expected, actual) when is_map(expected) and is_map(actual) do
    Enum.all?(expected, fn {key, value} ->
      Map.has_key?(actual, key) and subset?(value, actual[key])
    end)
  end

  defp subset?(expected, actual), do: expected == actual

  defp describe([]), do: "none"
  defp describe(events), do: Enum.map_join(events, ", ", & &1.type)
end

defmodule Kunai.Testing.Transport do
  @moduledoc """
  A transport for tests (`Kunai.Testing`): each request goes to the process
  that sent it, as `{:kunai_request, {url, headers, body, payload}}`, and is
  answered as `Kunai.Testing.respond/2` said for its URL, else with 200.

      config :kunai, transport: Kunai.Testing.Transport
  """

  @behaviour Kunai.Transport

  @impl Kunai.Transport
  def request(url, headers, body, _opts) do
    send(self(), {:kunai_request, {url, Map.new(headers), body, JSON.decode!(body)}})

    case Process.get({__MODULE__, url}, []) do
      [] -> {:ok, response(200)}
      [last] -> answer(last)
      [next | rest] -> Process.put({__MODULE__, url}, rest) && answer(next)
    end
  end

  defp answer({:error, reason}), do: {:error, reason}
  defp answer({status, headers}), do: {:ok, %{response(status) | headers: headers}}
  defp answer(status) when is_integer(status), do: {:ok, response(status)}

  defp response(status), do: %{status: status, headers: [], body: "ok"}
end
