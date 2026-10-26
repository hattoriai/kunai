defmodule Mix.Tasks.Kunai.Gen.LiveTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Kunai.Gen.Live

  setup do
    Mix.shell(Mix.Shell.Process)
    dir = Path.join(System.tmp_dir!(), "kunai_gen_live_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp generate(dir, args), do: File.cd!(dir, fn -> Live.run(args) end)

  defp routes do
    receive do
      {:mix_shell, :info, [text]} -> if text =~ "live_session", do: text, else: routes()
    after
      0 -> flunk("no routes printed")
    end
  end

  test "the pages, as the app's modules, where it says, on Kunai's API only", %{dir: dir} do
    generate(dir, ~w(--web GenOneWeb --path /settings/webhooks/ --eyebrow Settings))

    files = Path.wildcard(Path.join(dir, "lib/gen_one_web/live/webhooks_live/*.ex"))

    assert Enum.map(files, &Path.basename/1) |> Enum.sort() ==
             ~w(delivery.ex form.ex index.ex show.ex)

    show = File.read!(Path.join(dir, "lib/gen_one_web/live/webhooks_live/show.ex"))
    assert show =~ "defmodule GenOneWeb.WebhooksLive.Show do"
    assert show =~ ~s|base: "/settings/webhooks"|
    assert show =~ "app_layout: {GenOneWeb.Layouts, :app}"
    assert show =~ ~s|eyebrow: "Settings"|
    assert show =~ "Made by `mix kunai.gen.live`"
    assert show =~ "An endpoint: how its deliveries go"

    for file <- files do
      source = File.read!(file)
      refute source =~ "Kunai.Live.Endpoint"
      refute source =~ ~r/Kunai\.(Config|Broadcast|Events|Sender|Deliveries)\b/
    end

    # They compile, and are LiveViews.
    modules = files |> Enum.flat_map(&Code.compile_file/1) |> Enum.map(&elem(&1, 0))
    on_exit(fn -> Enum.each(modules, &(:code.purge(&1) && :code.delete(&1))) end)

    assert GenOneWeb.WebhooksLive.Index in modules
    assert function_exported?(GenOneWeb.WebhooksLive.Index, :render, 1)

    printed = routes()
    assert printed =~ ~s|live "/settings/webhooks", GenOneWeb.WebhooksLive.Index, :index|

    assert printed =~
             ~s|live "/settings/webhooks/deliveries/:id", GenOneWeb.WebhooksLive.Delivery, :show|

    refute printed =~ "keep the `kunai"
  end

  test "some of the pages, in the root layout, the rest left to the mount", %{dir: dir} do
    generate(dir, ~w(--web GenTwoWeb --only show --layout none))

    assert [file] = Path.wildcard(Path.join(dir, "lib/gen_two_web/live/webhooks_live/*.ex"))
    source = File.read!(file)
    assert source =~ ~s|use Kunai.Live.Page, base: "/settings/webhooks"\n|

    printed = routes()

    assert printed =~
             ~s|live "/settings/webhooks/endpoints/:id", GenTwoWeb.WebhooksLive.Show, :show|

    refute printed =~ "Index"
    assert printed =~ ~s|keep the `kunai "/settings/webhooks"` mount|
    assert printed =~ "GenTwoWeb.UserAuth"
  end

  test "an unknown page is refused", %{dir: dir} do
    assert_raise Mix.Error, ~r/Unknown pages for --only: logs/, fn ->
      generate(dir, ~w(--web GenThreeWeb --only show,logs))
    end
  end
end
