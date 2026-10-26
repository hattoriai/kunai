defmodule Kunai.Sender do
  @moduledoc """
  One attempt of a delivery (`Kunai.Workers.Deliver`): its request, signed,
  sent, and what follows from its answer.

  | Answer | What follows |
  | --- | --- |
  | 2xx | the delivery succeeded |
  | 410 Gone | the delivery failed, and the endpoint is disabled |
  | any other, or none (a timeout, a refused connection) | tried again (`Kunai.RetryPolicy`), obeying a `Retry-After` |

  One failure never disables an endpoint. An endpoint that fails every
  attempt for `:warn_after` (a day) has its owner warned, and for
  `:disable_after` (three days) is disabled (`Kunai.Notifier`); one
  success forgets it.

  A delivery waits, with no attempt counted, while its endpoint's circuit
  is open (`Kunai.CircuitBreaker`), and, for an endpoint with `ordered:
  true`, while an earlier delivery of the endpoint is pending.

  An attempt is claimed in the database before its request: the delivery
  is due (`:next_attempt_at`), and moves its next time to the end of the
  request, in one conditional update. So a delivery has as many jobs as
  it likes (a retry asked for by hand, the next one in order, a job of
  Oban's retried after a crash): one attempt runs at a time, and a job
  that finds its delivery not due goes away.
  """

  import Ecto.Query

  alias Kunai.{
    Attempt,
    CircuitBreaker,
    Config,
    Deliveries,
    Delivery,
    Endpoint,
    Endpoints,
    Event,
    Notifier,
    Payload,
    Signature,
    Telemetry
  }

  require Logger

  @doc false
  # :ok when the delivery is done with (for now), or {:snooze, seconds} to
  # come back without an attempt.
  @spec attempt(String.t()) :: :ok | {:snooze, pos_integer()}
  def attempt(delivery_id) do
    with %Delivery{status: "pending"} = delivery <- get(Delivery, delivery_id),
         {:due, delivery} <- due(delivery),
         %Endpoint{} = endpoint <- get(Endpoint, delivery.endpoint_id),
         %Event{} = event <- get(Event, delivery.event_id) do
      ready(delivery, endpoint, event)
    else
      {:snooze, seconds} -> {:snooze, seconds}
      _done_or_gone -> :ok
    end
  end

  defp ready(delivery, endpoint, event) do
    cond do
      not Endpoint.enabled?(endpoint) ->
        finish(delivery, "failed", %{last_error: "endpoint_disabled"})

      endpoint.ordered and earlier_pending?(delivery) ->
        wait(delivery, 30)

      true ->
        case CircuitBreaker.check(endpoint.id) do
          {:open, ms} -> wait(delivery, max(div(ms, 1000), 1))
          :closed -> claimed(delivery, endpoint, event)
        end
    end
  end

  # A delivery that waits says until when, so that one overdue has lost
  # its job (Kunai.recover/1).
  defp wait(delivery, seconds) do
    Delivery
    |> where(
      [d],
      d.id == ^delivery.id and d.status == "pending" and d.attempts == ^delivery.attempts
    )
    |> Config.repo().update_all(
      [set: [next_attempt_at: DateTime.add(DateTime.utc_now(), seconds, :second)]],
      Config.repo_opts()
    )

    {:snooze, seconds}
  end

  defp get(schema, id), do: Config.repo().get(schema, id, Config.repo_opts())

  # A job early for its delivery: one in flight (or whose job crashed) is
  # waited for, to the end of its lease; one due much later has a job of
  # its own then.
  defp due(%Delivery{next_attempt_at: nil} = delivery), do: {:due, delivery}

  defp due(delivery) do
    wait = DateTime.diff(delivery.next_attempt_at, DateTime.utc_now(), :millisecond)

    cond do
      wait <= 1_000 -> {:due, delivery}
      wait <= lease_ms() -> {:snooze, div(wait, 1000) + 1}
      true -> :later
    end
  end

  defp lease_ms, do: Config.timeouts()[:total] + 45_000

  defp claimed(delivery, endpoint, event) do
    now = DateTime.utc_now()
    lease = DateTime.add(now, lease_ms(), :millisecond)

    {count, _rows} =
      Delivery
      |> where(
        [d],
        d.id == ^delivery.id and d.status == "pending" and d.attempts == ^delivery.attempts
      )
      |> where(
        [d],
        is_nil(d.next_attempt_at) or d.next_attempt_at <= ^DateTime.add(now, 1, :second)
      )
      |> Config.repo().update_all([set: [next_attempt_at: lease]], Config.repo_opts())

    if count == 1,
      do: send_attempt(%{delivery | next_attempt_at: lease}, endpoint, event),
      else: :ok
  end

  defp earlier_pending?(delivery) do
    Delivery
    |> where([d], d.endpoint_id == ^delivery.endpoint_id and d.status == "pending")
    |> where([d], d.id < ^delivery.id)
    |> Config.repo().exists?(Config.repo_opts())
  end

  defp send_attempt(delivery, endpoint, event) do
    number = delivery.attempts + 1
    catalog = Config.catalog()
    serializer = Config.serializer()

    metadata = %{
      delivery_id: delivery.id,
      endpoint_id: endpoint.id,
      event_type: event.type,
      attempt: number
    }

    body = serializer.encode!(Payload.build(catalog, event, endpoint))

    if byte_size(body) > Config.max_payload_bytes() do
      finish(delivery, "failed", %{last_error: "payload_too_large"})
    else
      Telemetry.span(:attempt, metadata, fn ->
        {result, code} = request(delivery, endpoint, body, number)
        {:ok, Map.merge(metadata, %{result: result, status_code: code})}
      end)

      :ok
    end
  end

  defp request(delivery, endpoint, body, number) do
    timestamp = System.system_time(:second)
    {transport, opts} = Config.transport()

    headers = [
      {"content-type", "application/json"},
      {"user-agent", "Kunai (+https://hex.pm/packages/kunai)"},
      {"webhook-id", delivery.id},
      {"webhook-timestamp", Integer.to_string(timestamp)},
      {"webhook-signature",
       Signature.header(Endpoints.keys(endpoint), delivery.id, timestamp, body)}
    ]

    started = System.monotonic_time(:millisecond)
    response = transport.request(endpoint.url, headers, body, opts)
    duration = System.monotonic_time(:millisecond) - started

    attempt = %Attempt{
      id: Kunai.ID.generate("att"),
      delivery_id: delivery.id,
      endpoint_id: endpoint.id,
      number: number,
      duration_ms: duration,
      created_at: DateTime.utc_now()
    }

    case response do
      {:ok, %{status: status} = response} ->
        attempt = %{attempt | status_code: status, response_body: kept(response.body)}
        outcome(delivery, endpoint, attempt, {:status, status, retry_after(response.headers)})

      {:error, reason} ->
        attempt = %{attempt | error: describe(reason)}
        outcome(delivery, endpoint, attempt, {:error, reason})
    end
  end

  defp outcome(delivery, endpoint, attempt, {:status, status, _retry_after})
       when status in 200..299 do
    CircuitBreaker.record(endpoint.id, :ok)
    save(delivery, attempt, "succeeded", %{last_error: nil})
    recovered(endpoint)
    next_in_order(endpoint)
    {:succeeded, status}
  end

  defp outcome(delivery, endpoint, attempt, {:status, 410, _retry_after}) do
    save(delivery, attempt, "failed", %{last_error: "gone"})
    disable(endpoint, "gone")
    {:gone, 410}
  end

  defp outcome(delivery, endpoint, attempt, outcome) do
    CircuitBreaker.record(endpoint.id, :error)
    {policy, opts} = Config.retry_policy()
    error = attempt.error || "status #{attempt.status_code}"

    result =
      case policy.next(attempt.number, outcome, opts) do
        {:retry, seconds} ->
          at = DateTime.add(DateTime.utc_now(), seconds, :second)
          save(delivery, attempt, "pending", %{last_error: error, next_attempt_at: at})
          {:ok, _job} = Oban.insert(Config.oban(), Deliveries.job(delivery.id, scheduled_at: at))
          :retry

        :give_up ->
          save(delivery, attempt, "failed", %{last_error: error})
          next_in_order(endpoint)
          :failed
      end

    failing(endpoint)
    {result, attempt.status_code}
  end

  defp save(delivery, attempt, status, changes) do
    now = DateTime.utc_now()
    repo = Config.repo()

    completed = if status == "pending", do: %{}, else: %{completed_at: now, next_attempt_at: nil}

    changes =
      %{
        status: status,
        attempts: attempt.number,
        last_attempt_at: now,
        last_status_code: attempt.status_code
      }
      |> Map.merge(completed)
      |> Map.merge(changes)

    {:ok, _changes} =
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:attempt, attempt, Config.repo_opts())
      |> Ecto.Multi.update(
        :delivery,
        Ecto.Changeset.change(delivery, changes),
        Config.repo_opts()
      )
      |> repo.transaction()

    broadcast(delivery, attempt, status)
  end

  defp finish(delivery, status, changes) do
    delivery
    |> Ecto.Changeset.change(
      Map.merge(
        %{status: status, completed_at: DateTime.utc_now(), next_attempt_at: nil},
        changes
      )
    )
    |> Config.repo().update!(Config.repo_opts())

    :ok
  end

  # The live delivery log: each attempt, to whoever watches the endpoint.
  defp broadcast(delivery, attempt, status) do
    Kunai.Broadcast.endpoint(
      delivery.endpoint_id,
      {:kunai_attempt, %{delivery_id: delivery.id, attempt: attempt, status: status}}
    )
  end

  # An endpoint that answered again forgets that it was failing.
  defp recovered(%Endpoint{failing_since: nil}), do: :ok

  defp recovered(endpoint) do
    Endpoint
    |> where([e], e.id == ^endpoint.id)
    |> Config.repo().update_all([set: [failing_since: nil, warned_at: nil]], Config.repo_opts())
  end

  defp failing(%Endpoint{failing_since: nil} = endpoint) do
    Endpoint
    |> where([e], e.id == ^endpoint.id and is_nil(e.failing_since))
    |> Config.repo().update_all([set: [failing_since: DateTime.utc_now()]], Config.repo_opts())
  end

  defp failing(endpoint) do
    failed_for = DateTime.diff(DateTime.utc_now(), endpoint.failing_since)

    cond do
      failed_for >= Config.disable_after() ->
        disable(endpoint, "failing")

      failed_for >= Config.warn_after() and is_nil(endpoint.warned_at) ->
        {count, _rows} =
          Endpoint
          |> where([e], e.id == ^endpoint.id and is_nil(e.warned_at))
          |> Config.repo().update_all([set: [warned_at: DateTime.utc_now()]], Config.repo_opts())

        if count == 1, do: Notifier.notify(:failing, [endpoint, endpoint.failing_since])

      true ->
        :ok
    end
  end

  defp disable(endpoint, reason) do
    Telemetry.span(:disable, %{endpoint_id: endpoint.id, reason: reason}, fn ->
      case Endpoints.disable(nil, endpoint, reason) do
        {:ok, endpoint} ->
          Notifier.notify(:disabled, [endpoint, reason])

        {:error, error} ->
          Logger.error("Kunai could not disable #{endpoint.id}: #{inspect(error)}")
      end

      {:ok, %{endpoint_id: endpoint.id, reason: reason}}
    end)
  end

  # In order, the next delivery goes as soon as the one before is done.
  defp next_in_order(%Endpoint{ordered: false}), do: :ok

  defp next_in_order(endpoint) do
    Delivery
    |> where([d], d.endpoint_id == ^endpoint.id and d.status == "pending")
    |> order_by([d], asc: d.id)
    |> limit(1)
    |> select([d], d.id)
    |> Config.repo().one(Config.repo_opts())
    |> case do
      nil -> :ok
      id -> Deliveries.kick(id)
    end
  end

  defp kept(body) when is_binary(body) do
    max = Config.kept_response_bytes()
    body = if byte_size(body) > max, do: binary_part(body, 0, max), else: body
    # Kept as text: a body cut in a character, or not text, keeps what is valid.
    if String.valid?(body), do: body, else: :unicode.characters_to_binary(body, :latin1)
  end

  # Seconds; a Retry-After written as a date is not obeyed.
  defp retry_after(headers) do
    Enum.find_value(headers, fn {name, value} ->
      if String.downcase(name) == "retry-after", do: seconds(value)
    end)
  end

  defp seconds(value) do
    case Integer.parse(String.trim(value)) do
      {seconds, ""} when seconds >= 0 -> seconds
      _http_date -> nil
    end
  end

  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(reason), do: inspect(reason)
end
