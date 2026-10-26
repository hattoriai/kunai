defmodule KunaiTest.Webhooks do
  @moduledoc "The catalog of the tests."
  use Kunai.Catalog

  version "2026-06-01"
  version "2026-10-01", downgrade: KunaiTest.Webhooks.To20260601

  event "page.published",
    doc: "A page was published.",
    scopes: ["pages:read"],
    schema: [id: :string, title: :string, tags: {:array, :string}],
    example: %{"id" => "page_example", "title" => "An example"}

  event "page.deleted", scopes: ["pages:read"]

  event "member.invited",
    scopes: ["members:read"],
    redact: [:token]

  @impl Kunai.Catalog
  def owner(%{site: site}), do: "site:#{site}"

  @impl Kunai.Catalog
  def actor(%{user: user}), do: %{type: "user", id: user}

  @impl Kunai.Catalog
  def redact(_type, object), do: Map.delete(object, "secret_note")
end

defmodule KunaiTest.Webhooks.To20260601 do
  @moduledoc "2026-10-01 renamed `name` to `title`."
  @behaviour Kunai.Versions

  @impl Kunai.Versions
  def downgrade(%{"data" => %{"object" => object}} = payload) when is_map(object) do
    {title, object} = Map.pop(object, "title")
    put_in(payload, ["data", "object"], Map.put(object, "name", title))
  end

  def downgrade(payload), do: payload
end
