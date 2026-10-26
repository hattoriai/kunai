defmodule Kunai.StyleTest do
  # The tokens of kunai.css, as the Customizing guide lists them.
  use ExUnit.Case, async: true

  @css File.read!("priv/static/kunai.css")
  @guide File.read!("guides/customizing.md")

  defp tokens do
    [_, root] = String.split(@css, ":where(:root) {", parts: 2)
    [root | _] = String.split(root, "\n}", parts: 2)
    ~r/(--kunai-[a-z0-9-]+):/ |> Regex.scan(root) |> Enum.map(&List.last/1)
  end

  defp used(css), do: ~r/var\((--kunai-[a-z0-9-]+)/ |> Regex.scan(css) |> Enum.map(&List.last/1)

  test "every token is in the guide, with its own row" do
    for token <- tokens(), do: assert(@guide =~ "| `#{token}` |", "#{token} is not in the guide")
  end

  test "every token is used, and every token used is declared" do
    assert tokens() -- used(@css) == []
    assert Enum.uniq(used(@css)) -- tokens() == []
  end

  test "the mappings set only Kunai's tokens" do
    for file <- ~w(priv/static/kunai-daisyui.css priv/static/kunai-sumi.css) do
      set =
        ~r/(--kunai-[a-z0-9-]+):/
        |> Regex.scan(File.read!(file))
        |> Enum.map(&List.last/1)
        |> Enum.reject(&String.starts_with?(&1, "--kunai-sumi-"))

      assert Enum.uniq(set) -- tokens() == [], "#{file} sets a token Kunai does not have"
    end
  end
end
