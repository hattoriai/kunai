defmodule Kunai.Events do
  @moduledoc """
  Events: emitted in the transaction of their change, then listed and
  fetched by their owner. See `Kunai.emit/4`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Kunai.{Config, Event, Owner, Page, Telemetry}
  alias Kunai.Workers.Fanout

  @doc false
  def emit(catalog, %Multi{} = multi, type, data, opts) do
    event_type =
      catalog.event_type(type) ||
        raise ArgumentError, "#{inspect(catalog)} has no event #{inspect(type)}"

    name =
      Keyword.get_lazy(opts, :as, fn ->
        {:kunai_event, type, System.unique_integer([:positive])}
      end)

    Multi.run(multi, name, fn repo, changes ->
      data = if is_function(data, 1), do: data.(changes), else: data
      insert(repo, catalog, event_type, data, opts)
    end)
  end

  defp insert(repo, catalog, event_type, data, opts) do
    owner = Keyword.get_lazy(opts, :owner, fn -> Owner.of(opts[:scope]) end)

    Telemetry.span(:emit, %{type: event_type.name, owner: owner}, fn ->
      event = build(catalog, event_type, data, owner, opts)

      result =
        with {:ok, event} <- repo.insert(event, Config.repo_opts()),
             {:ok, _job} <-
               Oban.insert(
                 Config.oban(),
                 Fanout.new(%{"event_id" => event.id}, queue: Config.queue())
               ) do
          {:ok, event}
        end

      {result, %{type: event_type.name, owner: owner}}
    end)
  end

  @doc false
  def build(catalog, event_type, data, owner, opts) do
    object = redact(catalog, event_type, data)

    %Event{
      id: Kunai.ID.generate("evt"),
      type: event_type.name,
      owner: owner,
      data: object,
      previous: if(previous = opts[:previous], do: redact(catalog, event_type, previous)),
      object_id: object_id(object),
      actor:
        if(actor = opts[:actor], do: Owner.stringify(actor), else: Owner.actor(opts[:scope])),
      api_version: catalog.latest_version(),
      test: Keyword.get(opts, :test, false),
      created_at: DateTime.utc_now()
    }
  end

  # The object as JSON gives it (string keys, no structs), without the
  # fields the event's type and the catalog keep out.
  defp redact(catalog, event_type, data) do
    object = Owner.stringify(data)
    catalog.redact(event_type.name, Map.drop(object, event_type.redact))
  end

  defp object_id(%{"id" => id}) when is_binary(id) or is_integer(id), do: to_string(id)
  defp object_id(_object), do: nil

  @doc """
  A scope's events, newest first (`Kunai.Page`). Options: `:type`, and
  those of `Kunai.Page`.
  """
  @spec list(term(), keyword()) :: Page.t(Event.t())
  def list(scope, opts \\ []) do
    Event
    |> Owner.where(Owner.of(scope))
    |> then(&if(type = opts[:type], do: where(&1, [e], e.type == ^type), else: &1))
    |> Page.fetch(opts)
  end

  @doc "An event of a scope, or nil."
  @spec get(term(), String.t()) :: Event.t() | nil
  def get(scope, id) do
    Event
    |> Owner.where(Owner.of(scope))
    |> where([e], e.id == ^id)
    |> Config.repo().one(Config.repo_opts())
  end
end
