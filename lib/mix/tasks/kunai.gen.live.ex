defmodule Mix.Tasks.Kunai.Gen.Live do
  @shortdoc "Copies Kunai's pages into the app, to change as its own"

  @moduledoc """
  Copies Kunai's pages into the app, as LiveViews of its own: for a page
  whose parts, order or words the app wants otherwise than its style
  sheet can make them (see the Theming guide for that).

      $ mix kunai.gen.live
      $ mix kunai.gen.live --path /settings/webhooks --eyebrow Settings
      $ mix kunai.gen.live --only show

  The pages are the ones `kunai/2` mounts, with the same names and routes:

    * `index` - the endpoints, with the last day's deliveries.
    * `show` - an endpoint: its deliveries live, each in a drawer, its
      details, secret and test.
    * `form` - a new endpoint, or one changed.
    * `delivery` - a delivery on a page of its own.

  Each is built on `Kunai.Live.Page` and `Kunai.Components` and calls
  `Kunai`'s functions: what was copied is the page, not Kunai, and Kunai's
  upgrades still reach it through those. The task prints the routes, to
  put in the app's router behind its own pipeline and hooks; with
  `--only`, the routes of the pages copied go before a `kunai` mount at the
  same path, which keeps the others: each of its routes is its own
  (`Kunai.Components.endpoint_path/2`), so the app's take over theirs.

  ## Options

    * `--web` - the app's web module (`MyAppWeb`, from the app's name).
    * `--path` - where the pages are (`/settings/webhooks`).
    * `--layout` - the app's layout component, `MyAppWeb.Layouts.app`, or
      `none` for the root layout only.
    * `--eyebrow` - a line above the pages' titles.
    * `--scope-assign` - where the app's hooks put the scope
      (`current_scope`).
    * `--only` - some of the pages: `index,show,form,delivery`.
    * `--force` - overwrites files without asking.
  """

  use Mix.Task

  @pages [
    index: {"endpoints_live.ex", "Kunai.Live.EndpointsLive", "Index"},
    show: {"endpoint_live.ex", "Kunai.Live.EndpointLive", "Show"},
    form: {"endpoint_form_live.ex", "Kunai.Live.EndpointFormLive", "Form"},
    delivery: {"delivery_live.ex", "Kunai.Live.DeliveryLive", "Delivery"}
  ]

  # The pages' sources, as Kunai was compiled with them.
  @sources Map.new(@pages, fn {name, {file, _module, _as}} ->
             path = Path.expand("../../kunai/live/#{file}", __DIR__)
             @external_resource path
             {name, File.read!(path)}
           end)

  @switches [
    web: :string,
    path: :string,
    layout: :string,
    eyebrow: :string,
    scope_assign: :string,
    only: :string,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)

    web = opts[:web] || default_web()
    path = String.trim_trailing(opts[:path] || "/settings/webhooks", "/")
    namespace = "#{web}.WebhooksLive"
    dir = Path.join(["lib", Macro.underscore(web), "live", "webhooks_live"])
    pages = only(opts[:only])

    for name <- pages do
      {_file, _module, as} = @pages[name]
      source = page(name, "#{namespace}.#{as}", use_opts(web, path, opts))
      file = Path.join(dir, "#{Macro.underscore(as)}.ex")
      Mix.Generator.create_file(file, source, force: opts[:force] || false)
    end

    Mix.shell().info(instructions(web, namespace, path, pages))
  end

  defp default_web do
    app =
      Mix.Project.config()[:app] || Mix.raise("mix kunai.gen.live runs in an app; or pass --web")

    Macro.camelize(to_string(app)) <> "Web"
  end

  defp only(nil), do: Keyword.keys(@pages)

  defp only(list) do
    names = list |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
    known = Enum.map(@pages, fn {name, _} -> to_string(name) end)

    case names -- known do
      [] ->
        for {name, _} <- @pages, to_string(name) in names, do: name

      unknown ->
        Mix.raise(
          "Unknown pages for --only: #{Enum.join(unknown, ", ")} (#{Enum.join(known, ", ")})"
        )
    end
  end

  # The options of `use Kunai.Live.Page`: a page outside the mount says
  # where it is and in which layout.
  defp use_opts(web, path, opts) do
    layout =
      case opts[:layout] || "#{web}.Layouts.app" do
        "none" ->
          nil

        layout ->
          {module, [fun]} = layout |> String.split(".") |> Enum.split(-1)
          "{#{Enum.join(module, ".")}, :#{fun}}"
      end

    [
      {"base", inspect(path)},
      layout && {"app_layout", layout},
      opts[:eyebrow] && {"eyebrow", inspect(opts[:eyebrow])},
      opts[:scope_assign] && {"scope_assign", ":#{opts[:scope_assign]}"}
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{value}" end)
  end

  @doc false
  # Kunai's page, as the app's module: its name, its documentation, and
  # where it is.
  def page(name, module, use_opts) do
    {_file, kunai_module, _as} = @pages[name]
    source = @sources[name]

    {comment, source} = take_comment(source)

    source
    |> String.replace("defmodule #{kunai_module} do", "defmodule #{module} do")
    |> String.replace("  @moduledoc false\n", moduledoc(comment))
    |> String.replace("  use Kunai.Live.Page\n", "  use Kunai.Live.Page, #{use_opts}\n")
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  # The comment under `@moduledoc false`, which says what the page is.
  defp take_comment(source) do
    [head, rest] = String.split(source, "  @moduledoc false\n", parts: 2)

    {comment, rest} =
      rest |> String.split("\n") |> Enum.split_while(&String.starts_with?(&1, "  #"))

    text =
      Enum.map_join(comment, " ", &(&1 |> String.trim_leading() |> String.trim_leading("# ")))

    {text, head <> "  @moduledoc false\n" <> Enum.join(rest, "\n")}
  end

  defp moduledoc(comment) do
    version = Application.spec(:kunai, :vsn)

    comment = comment |> wrap(70) |> Enum.join("\n  ")

    ~s'''
      @moduledoc """
      #{comment}

      Made by `mix kunai.gen.live` from Kunai #{version}'s page, to change
      as the app's own. It is built on `Kunai.Live.Page` and
      `Kunai.Components`, and calls `Kunai`'s functions.
      """
    '''
  end

  defp wrap(text, width) do
    text
    |> String.split(" ")
    |> Enum.reduce([], fn
      word, [line | lines] when byte_size(line) + byte_size(word) < width ->
        [line <> " " <> word | lines]

      word, lines ->
        [word | lines]
    end)
    |> Enum.reverse()
  end

  defp instructions(web, namespace, path, pages) do
    routes =
      for {name, action, route} <- [
            {:index, :index, ""},
            {:form, :new, "/new"},
            {:show, :show, "/endpoints/:id"},
            {:form, :edit, "/endpoints/:id/edit"},
            {:delivery, :show, "/deliveries/:id"}
          ],
          name in pages do
        {_file, _module, as} = @pages[name]
        ~s|      live "#{path}#{route}", #{namespace}.#{as}, :#{action}|
      end

    keep =
      if length(pages) < length(@pages),
        do: """

        The pages not copied stay Kunai's: keep the `kunai "#{path}"` mount,
        after these routes. Each of its routes is its own, so these take over
        theirs.
        """,
        else: ""

    """

    The pages are in the app. Add their routes to its router, in a
    live_session with the hooks that assign the scope, behind the
    pipeline that signs people in:

        live_session :webhooks,
          on_mount: [{#{web}.UserAuth, :require_authenticated}] do
    #{Enum.join(routes, "\n")}
        end
    #{keep}
    """
  end
end
