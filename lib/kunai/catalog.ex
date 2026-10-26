defmodule Kunai.Catalog do
  @moduledoc """
  The app's events, declared once, checked when the app compiles.

      defmodule MyApp.Webhooks do
        use Kunai.Catalog

        version "2026-06-01"
        version "2026-10-01", downgrade: MyApp.Webhooks.To20260601

        event "page.published",
          doc: "A page was published.",
          scopes: ["pages:read"],
          schema: [id: :string, title: :string, published_at: :datetime],
          example: %{"id" => "page_1", "title" => "Hello", "published_at" => "2026-10-26T09:00:00Z"}

        event "member.invited",
          doc: "Someone was invited to a site.",
          scopes: ["members:read"],
          redact: [:token]

        @impl Kunai.Catalog
        def owner(%MyApp.Accounts.Scope{site: site}), do: "site:\#{site.id}"

        @impl Kunai.Catalog
        def actor(%MyApp.Accounts.Scope{user: user}),
          do: %{type: "user", id: to_string(user.id), name: user.name}
      end

  and `config :kunai, catalog: MyApp.Webhooks`.

  ## Emitting

  An event is emitted in the transaction of the change it tells of, so a
  change rolled back sends nothing and a change committed always sends
  (`Kunai.emit/5`):

      require MyApp.Webhooks

      Ecto.Multi.new()
      |> Ecto.Multi.update(:page, Page.publish_changeset(page))
      |> MyApp.Webhooks.emit("page.published", & &1.page, scope: scope)
      |> Repo.transaction()

  `emit/4` is a macro: an event's name the catalog does not declare is a
  compile error, with the name it was likely meant to be. The data is a
  map, or a function of the transaction's changes so far.

  ## Options of `event/2`

    * `:doc` - what it means, for the docs and the API's list of events.
    * `:scopes` - the scopes an endpoint needs to receive it
      (`Kunai.Authorizer.Scopes`).
    * `:schema` - its object's fields: `:string`, `:integer`, `:number`,
      `:boolean`, `:datetime`, `:date`, `:map`, `{:array, type}` or a
      keyword list of fields. Gives the event's JSON Schema
      (`Kunai.EventType.json_schema/1`).
    * `:redact` - fields of the object never kept nor sent (a token, a
      password). `c:redact/2` removes others.
    * `:example` - an object for test events (`Kunai.send_test/2`).

  ## Versions

  `version/2` declares the versions of the payloads, oldest first. An
  event is kept in the latest; an endpoint pinned to an older version
  gets it changed by each newer version's `:downgrade` module
  (`Kunai.Versions`), newest first.

  Every catalog also has `kunai.ping`, the event of a test with no
  example.
  """

  @doc "The owner of what a scope changes: whose endpoints receive its events. Nil for none."
  @callback owner(scope :: term()) :: String.t() | nil

  @doc ~S(Who made the change, as a map: its "type" is "user", "agent", "bot" or "system", with an "id" and a "name".)
  @callback actor(scope :: term()) :: map() | nil

  @doc "The object of an event as it is kept, without what must not be. The object as it is by default."
  @callback redact(type :: String.t(), object :: map()) :: map()

  @doc """
  The scopes a person may give an endpoint: those they hold themselves, so
  an endpoint never sees more than its maker may. Every scope of the
  catalog by default.
  """
  @callback scopes(scope :: term()) :: [String.t()]

  @ping %Kunai.EventType{
    name: "kunai.ping",
    doc: "A test, sent to one endpoint on request."
  }

  defmacro __using__(_opts) do
    quote do
      @behaviour Kunai.Catalog
      import Kunai.Catalog, only: [event: 1, event: 2, version: 1, version: 2]
      Module.register_attribute(__MODULE__, :kunai_events, accumulate: true)
      Module.register_attribute(__MODULE__, :kunai_versions, accumulate: true)
      @before_compile Kunai.Catalog

      @impl Kunai.Catalog
      def owner(_scope), do: nil

      @impl Kunai.Catalog
      def actor(_scope), do: nil

      @impl Kunai.Catalog
      def redact(_type, object), do: object

      @impl Kunai.Catalog
      def scopes(_scope), do: all_scopes()

      defoverridable owner: 1, actor: 1, redact: 2, scopes: 1
    end
  end

  @doc "Declares an event. See the module's docs for the options."
  defmacro event(name, opts \\ []) do
    quote do
      @kunai_events Kunai.EventType.new!(unquote(name), unquote(opts))
    end
  end

  @doc """
  Declares a version of the payloads, oldest first. `:downgrade` is the
  module that changes a payload of this version into the one before
  (`Kunai.Versions`).
  """
  defmacro version(name, opts \\ []) do
    quote do
      @kunai_versions {unquote(name), Keyword.get(unquote(opts), :downgrade)}
    end
  end

  defmacro __before_compile__(env) do
    events = env.module |> Module.get_attribute(:kunai_events) |> Enum.reverse()
    versions = env.module |> Module.get_attribute(:kunai_versions) |> Enum.reverse()
    check!(events, versions)

    by_name = Map.new([@ping | events], &{&1.name, &1})

    quote do
      @doc "The events of the catalog, by name."
      def __kunai__(:events), do: unquote(Macro.escape(by_name))
      def __kunai__(:versions), do: unquote(Macro.escape(versions))

      @doc "The event of this name, or nil."
      @spec event_type(String.t()) :: Kunai.EventType.t() | nil
      def event_type(name), do: Map.get(__kunai__(:events), name)

      @doc "The events of the catalog."
      @spec event_types() :: [Kunai.EventType.t()]
      def event_types, do: __kunai__(:events) |> Map.values() |> Enum.sort_by(& &1.name)

      @doc "Every scope the catalog's events declare."
      @spec all_scopes() :: [String.t()]
      def all_scopes,
        do: event_types() |> Enum.flat_map(& &1.scopes) |> Enum.uniq() |> Enum.sort()

      @doc "The versions of the payloads, oldest first."
      @spec versions() :: [String.t()]
      def versions, do: Enum.map(__kunai__(:versions), &elem(&1, 0))

      @doc "The version events are kept in, or nil when the catalog has none."
      @spec latest_version() :: String.t() | nil
      def latest_version, do: List.last(versions())

      unquote(emit_macros())
    end
  end

  # The catalog's emit/4 and emit!/3, which check the event's name.
  defp emit_macros do
    quote unquote: false do
      @doc """
      Adds an event to a transaction (`Kunai.emit/5`). A name the catalog
      does not declare is a compile error.
      """
      defmacro emit(multi, type, data, opts \\ []) do
        Kunai.Catalog.__check_name__(__MODULE__, type, __CALLER__)

        quote do
          Kunai.emit(
            unquote(__MODULE__),
            unquote(multi),
            unquote(type),
            unquote(data),
            unquote(opts)
          )
        end
      end

      @doc """
      Emits an event now (`Kunai.emit!/3`): inside a transaction of the
      app's repo (`Repo.transact/1`), in that transaction. A name the
      catalog does not declare is a compile error.
      """
      defmacro emit!(type, data, opts \\ []) do
        Kunai.Catalog.__check_name__(__MODULE__, type, __CALLER__)

        quote do
          Kunai.emit!(unquote(__MODULE__), unquote(type), unquote(data), unquote(opts))
        end
      end
    end
  end

  defp check!(events, versions) do
    events
    |> Enum.frequencies_by(& &1.name)
    |> Enum.each(fn
      {name, count} when count > 1 ->
        raise ArgumentError, "the event #{name} is declared #{count} times"

      _once ->
        :ok
    end)

    if Enum.any?(events, &(&1.name == "kunai.ping")),
      do: raise(ArgumentError, "kunai.ping is Kunai's own event")

    names = Enum.map(versions, &elem(&1, 0))

    if names != Enum.uniq(names),
      do: raise(ArgumentError, "a version is declared twice: #{inspect(names)}")

    case versions do
      [{_first, downgrade} | _rest] when not is_nil(downgrade) ->
        raise ArgumentError, "the first version has none before it to downgrade to"

      _other ->
        :ok
    end
  end

  @doc false
  # At the caller's compile time: a literal name must be in the catalog.
  def __check_name__(catalog, type, caller) when is_binary(type) do
    unless catalog.event_type(type) do
      known = Map.keys(catalog.__kunai__(:events))
      guess = Enum.max_by(known, &String.jaro_distance(&1, type), fn -> nil end)
      hint = if guess, do: " Did you mean #{inspect(guess)}?", else: ""

      raise CompileError,
        file: caller.file,
        line: caller.line,
        description: "#{inspect(catalog)} has no event #{inspect(type)}.#{hint}"
    end
  end

  def __check_name__(_catalog, _type, _caller), do: :ok
end
