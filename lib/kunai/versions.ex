defmodule Kunai.Versions do
  @moduledoc """
  The versions of the payloads. An event is kept in the catalog's latest
  version; an endpoint pinned to an older one gets it as that version
  wrote it, changed by each newer version's `:downgrade` module, the
  newest first (`Kunai.Catalog.version/2`).

      defmodule MyApp.Webhooks.To20260601 do
        @behaviour Kunai.Versions

        # 2026-10-01 renamed "name" to "title".
        @impl Kunai.Versions
        def downgrade(%{"data" => %{"object" => object}} = payload) do
          {title, object} = Map.pop(object, "title")
          put_in(payload, ["data", "object"], Map.put(object, "name", title))
        end
      end

  A payload is a map with string keys, as it is sent.
  """

  @doc "The payload of this module's version, as the version before wrote it."
  @callback downgrade(payload :: map()) :: map()

  @doc "A payload of version `from` as version `to` writes it."
  @spec downgrade(module(), map(), String.t() | nil, String.t() | nil) :: map()
  def downgrade(_catalog, payload, from, to) when from == to or is_nil(from) or is_nil(to),
    do: payload

  def downgrade(catalog, payload, from, to) do
    versions = catalog.__kunai__(:versions)
    names = Enum.map(versions, &elem(&1, 0))
    from_index = Enum.find_index(names, &(&1 == from))
    to_index = Enum.find_index(names, &(&1 == to))

    if from_index && to_index && to_index < from_index do
      versions
      |> Enum.slice((to_index + 1)..from_index//1)
      |> Enum.reverse()
      |> Enum.reduce(payload, fn
        {_name, nil}, payload -> payload
        {_name, module}, payload -> module.downgrade(payload)
      end)
      |> Map.put("api_version", to)
    else
      payload
    end
  end
end
