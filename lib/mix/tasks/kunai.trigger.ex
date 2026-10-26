defmodule Mix.Tasks.Kunai.Trigger do
  @shortdoc "Emits an event of the catalog, and shows where it went"

  @moduledoc """
  Emits an event of the app's catalog, from its example, to the endpoints
  that receive it, and shows each delivery as it goes: an event to test a
  receiver with, without making the change it tells of.

      $ mix kunai.trigger page.updated
      $ mix kunai.trigger page.updated --data '{"title": "Porto trip"}'
      $ mix kunai.trigger page.updated --owner site:42
      $ mix kunai.trigger page.updated --dry-run

  The event is the catalog's example for its type, with `--data`'s fields
  over it, and the system as its actor. It is the owner's whose endpoints
  receive it: `--owner` says whose when they are several's.

  `--dry-run` stores and sends nothing: it prints each request as it would
  go, signed, and a `curl` to send it by hand.

  ## Options

    * `--owner` - the owner of the event (and of its endpoints).
    * `--data` - JSON, merged over the example.
    * `--dry-run` - print the requests, send none.
    * `--wait` - seconds to wait for the deliveries (10).
  """

  use Mix.Task

  import Ecto.Query

  alias Kunai.{Config, Delivery, Endpoint, Subscriptions}

  @switches [owner: :string, data: :string, dry_run: :boolean, wait: :integer]

  @impl Mix.Task
  def run(args) do
    {opts, argv} = OptionParser.parse!(args, strict: @switches)

    type =
      List.first(argv) || Mix.raise("Which event? mix kunai.trigger <type>, one of: #{types()}")

    Mix.Task.run("app.start")

    event_type =
      Kunai.catalog().event_type(type) || Mix.raise("#{type} is not in the catalog: #{types()}")

    data = merge(event_type.example || %{}, decode(opts[:data]))
    {owner, endpoints} = endpoints(type, opts)

    if opts[:dry_run],
      do: dry_run(event_type, data, owner, endpoints),
      else: trigger(type, data, owner, endpoints, opts)
  end

  defp types do
    Kunai.catalog().event_types()
    |> Enum.map(& &1.name)
    |> Enum.reject(&(&1 == "kunai.ping"))
    |> Enum.join(", ")
  end

  defp decode(nil), do: %{}

  defp decode(json) do
    case JSON.decode(json) do
      {:ok, %{} = data} -> data
      _other -> Mix.raise("--data is not a JSON object: #{json}")
    end
  end

  defp merge(%{} = left, %{} = right),
    do: Map.merge(stringify(left), right, fn _key, l, r -> merge(l, r) end)

  defp merge(_left, right), do: right

  defp stringify(map), do: map |> JSON.encode!() |> JSON.decode!()

  # The endpoints enabled that receive the type: of the owner given, or of
  # the only owner that has any.
  defp endpoints(type, opts) do
    receiving =
      Endpoint
      |> where([e], e.status == "enabled")
      |> then(
        &if Keyword.has_key?(opts, :owner), do: where(&1, [e], e.owner == ^opts[:owner]), else: &1
      )
      |> Config.repo().all(Config.repo_opts())
      |> Enum.filter(fn endpoint ->
        Enum.any?(endpoint.events, &Subscriptions.matches?(&1, type))
      end)

    case {receiving |> Enum.map(& &1.owner) |> Enum.uniq(), Keyword.has_key?(opts, :owner)} do
      {[], true} ->
        {opts[:owner], []}

      {[], false} ->
        Mix.raise("No endpoint receives #{type}. Add one, or pass --owner to emit it anyway.")

      {[owner], _given?} ->
        {owner, receiving}

      {owners, _given?} ->
        Mix.raise(
          "Endpoints of several owners receive #{type}: pass --owner, one of #{Enum.join(owners, ", ")}"
        )
    end
  end

  @actor %{type: "system", id: "mix kunai.trigger"}

  defp trigger(type, data, owner, endpoints, opts) do
    event = Kunai.emit!(type, data, owner: owner, actor: @actor)
    Mix.shell().info("#{event.type} #{event.id}, for #{owner}")

    if endpoints == [] do
      Mix.shell().info("  No endpoint receives it.")
    else
      deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :wait, 10) * 1_000
      watch(event.id, MapSet.new(), length(endpoints), deadline)
    end
  end

  # Each delivery once it has an answer, until all have or time is up. The
  # deliveries are the app's to run: its Oban, here or in its server.
  defp watch(event_id, shown, expected, deadline) do
    deliveries =
      Delivery
      |> where([d], d.event_id == ^event_id)
      |> Config.repo().all(Config.repo_opts())

    answered = Enum.filter(deliveries, &(&1.attempts > 0 and not MapSet.member?(shown, &1.id)))
    Enum.each(answered, &show/1)
    shown = Enum.reduce(answered, shown, &MapSet.put(&2, &1.id))

    cond do
      MapSet.size(shown) >= expected ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        Mix.shell().info(
          "  #{expected - MapSet.size(shown)} not tried yet: is the app's Oban running the #{Config.queue()} queue?"
        )

      true ->
        Process.sleep(200)
        watch(event_id, shown, expected, deadline)
    end
  end

  defp show(delivery) do
    endpoint = Config.repo().get(Endpoint, delivery.endpoint_id, Config.repo_opts())

    outcome =
      case delivery do
        %{status: "succeeded", last_status_code: code} ->
          "#{code}, delivered"

        %{status: "failed", last_error: error, last_status_code: code} ->
          "#{code || error}, failed"

        %{last_status_code: code, last_error: error} ->
          "#{code || error}, tried again later"
      end

    Mix.shell().info("  → #{endpoint.url}  #{outcome}  (#{delivery.id})")
  end

  defp dry_run(event_type, data, owner, endpoints) do
    event = Kunai.Events.build(Kunai.catalog(), event_type, data, owner, actor: @actor)
    Mix.shell().info("#{event.type} #{event.id}, for #{owner}: a dry run, nothing stored or sent")
    if endpoints == [], do: Mix.shell().info("  No endpoint receives it.")

    for endpoint <- endpoints do
      webhook_id = Kunai.ID.generate("msg")
      body = Config.serializer().encode!(Kunai.payload(event, endpoint))
      headers = Kunai.Sender.headers(endpoint, webhook_id, System.system_time(:second), body)

      Mix.shell().info("""

      POST #{endpoint.url}
      #{Enum.map_join(headers, "\n", fn {name, value} -> "#{name}: #{value}" end)}

      #{Kunai.Pretty.json(JSON.decode!(body))}

      curl -X POST #{shell(endpoint.url)} \\
      #{Enum.map_join(headers, " \\\n", fn {name, value} -> "  -H #{shell("#{name}: #{value}")}" end)} \\
        --data-raw #{shell(body)}
      """)
    end

    :ok
  end

  defp shell(text), do: "'" <> String.replace(text, "'", ~S('\'')) <> "'"
end
