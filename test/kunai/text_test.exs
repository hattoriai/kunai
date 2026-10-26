defmodule Kunai.TextTest do
  # Kunai's messages: the template an app translates, and the app's
  # Gettext reading them. The backend is application config: alone.
  use KunaiTest.DataCase
  use PhoenixMountable.Test, host: KunaiTest.Host

  @pot "priv/gettext/kunai.pot"
  @string ~S{"((?:[^"\\]|\\.)*)"}

  # Every message of Kunai's, from its calls of t/2 and tn/4, in code and
  # in templates alike.
  defp messages do
    for file <- Path.wildcard("lib/**/*.ex"), file != "lib/kunai/text.ex", reduce: %{} do
      acc ->
        source = File.read!(file)

        singles =
          for [_, id] <- Regex.scan(~r/\bt\(\s*#{@string}/, source), do: {id, nil}

        plurals =
          for [_, id, plural] <- Regex.scan(~r/\btn\(\s*#{@string},\s*#{@string}/, source),
              do: {id, plural}

        Enum.reduce(singles ++ plurals, acc, fn {id, plural}, acc ->
          Map.update(acc, {id, plural}, [file], &Enum.uniq(&1 ++ [file]))
        end)
    end
  end

  defp pot do
    entries =
      messages()
      |> Enum.sort_by(fn {{id, _plural}, _files} -> id end)
      |> Enum.map(fn
        {{id, nil}, files} ->
          refs(files) <> ~s|msgid "#{id}"\nmsgstr ""\n|

        {{id, plural}, files} ->
          refs(files) <>
            ~s|msgid "#{id}"\nmsgid_plural "#{plural}"\nmsgstr[0] ""\nmsgstr[1] ""\n|
      end)

    Enum.join(
      [
        """
        ## Kunai's messages, for an app's translations of its pages
        ## (Kunai.Text): copy this file into the app's priv/gettext and run
        ## `mix gettext.merge priv/gettext`. Made from Kunai's sources by its
        ## tests (UPDATE_POT=1 mix test test/kunai/text_test.exs).
        msgid ""
        msgstr ""
        """
        | entries
      ],
      "\n"
    )
  end

  defp refs(files), do: Enum.map_join(files, "", &"#: #{&1}\n")

  test "the template has every message of Kunai's, and none it no longer says" do
    if System.get_env("UPDATE_POT") do
      File.mkdir_p!(Path.dirname(@pot))
      File.write!(@pot, pot())
    end

    assert File.read!(@pot) == pot(),
           "priv/gettext/kunai.pot is not Kunai's messages: UPDATE_POT=1 mix test #{__ENV__.file}"
  end

  test "a message is one string, its values given apart" do
    for file <- Path.wildcard("lib/**/*.ex") do
      refute File.read!(file) =~ ~r/\btn?\(\s*"[^"]*#\{/, "#{file} interpolates a message"
    end
  end

  describe "with the app's Gettext" do
    setup do
      Application.put_env(:kunai, :gettext, KunaiTest.Gettext)
      Gettext.put_locale(KunaiTest.Gettext, "pt")

      on_exit(fn ->
        Application.delete_env(:kunai, :gettext)
        Gettext.put_locale(KunaiTest.Gettext, "en")
      end)
    end

    test "messages and plurals in the app's language, with their values" do
      assert Kunai.Text.t("Add endpoint") == "Adicionar endpoint"
      assert Kunai.Text.tn("%{count} event", "%{count} events", 1) == "1 evento"
      assert Kunai.Text.tn("%{count} event", "%{count} events", 3) == "3 eventos"
      # One the app has not translated stays Kunai's.
      assert Kunai.Text.t("Webhooks") == "Webhooks"
    end

    test "an app's English says what it prefers, the rest stays Kunai's" do
      Gettext.put_locale(KunaiTest.Gettext, "en")
      assert Kunai.Text.t("Endpoints") == "Destinations"
      assert Kunai.Text.t("Add endpoint") == "Add endpoint"
    end

    test "the pages speak it", %{conn: conn} do
      conn = init_test_session(conn, %{"site" => "1", "locale" => "pt"})
      {:ok, _view, html} = live(conn, "/webhooks")
      assert html =~ "Adicionar endpoint"
      refute html =~ "Add endpoint"
    end
  end
end
