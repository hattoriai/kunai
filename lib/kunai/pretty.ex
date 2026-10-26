defmodule Kunai.Pretty do
  @moduledoc false
  # JSON indented for people, as the pages show a payload. Keys sorted.

  def json(term), do: term |> encode(0) |> IO.iodata_to_binary()

  defp encode(map, _level) when is_map(map) and map_size(map) == 0, do: "{}"

  defp encode(map, level) when is_map(map) do
    inner =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, value} ->
        [indent(level + 1), JSON.encode!(to_string(key)), ": ", encode(value, level + 1)]
      end)
      |> Enum.intersperse(",\n")

    ["{\n", inner, "\n", indent(level), "}"]
  end

  defp encode([], _level), do: "[]"

  defp encode(list, level) when is_list(list) do
    inner =
      list |> Enum.map(&[indent(level + 1), encode(&1, level + 1)]) |> Enum.intersperse(",\n")

    ["[\n", inner, "\n", indent(level), "]"]
  end

  defp encode(value, _level), do: JSON.encode!(value)

  defp indent(level), do: String.duplicate("  ", level)
end
