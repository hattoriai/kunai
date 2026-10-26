defmodule Kunai.CatalogTest do
  use ExUnit.Case, async: true

  alias KunaiTest.Webhooks

  test "the events, with kunai.ping" do
    assert Webhooks.event_type("page.published").scopes == ["pages:read"]
    assert Webhooks.event_type("member.invited").redact == ["token"]
    assert Webhooks.event_type("kunai.ping")

    assert Enum.map(Webhooks.event_types(), & &1.name) ==
             ["kunai.ping", "member.invited", "page.deleted", "page.published"]
  end

  test "the versions, oldest first" do
    assert Webhooks.versions() == ["2026-06-01", "2026-10-01"]
    assert Webhooks.latest_version() == "2026-10-01"
  end

  test "an event the catalog does not declare is a compile error, with a guess" do
    code =
      quote do
        defmodule KunaiTest.Emitter do
          require KunaiTest.Webhooks
          def go(multi), do: KunaiTest.Webhooks.emit(multi, "page.publish", %{})
        end
      end

    error = assert_raise CompileError, fn -> Code.compile_quoted(code) end
    assert error.description =~ ~s|has no event "page.publish". Did you mean "page.published"?|
  end

  test "a name that is not a name, or declared twice, is refused" do
    assert_raise ArgumentError, ~r/lowercase/, fn ->
      Kunai.EventType.new!("Page Published", [])
    end

    assert_raise ArgumentError, ~r/declared 2 times/, fn ->
      Code.compile_quoted(
        quote do
          defmodule KunaiTest.Twice do
            use Kunai.Catalog
            event "a.b"
            event "a.b"
          end
        end
      )
    end
  end

  test "the JSON Schema of an event" do
    schema = Kunai.EventType.json_schema(Webhooks.event_type("page.published"))

    assert schema["properties"]["type"] == %{"const" => "page.published"}

    assert schema["properties"]["data"]["properties"]["object"]["properties"] == %{
             "id" => %{"type" => "string"},
             "title" => %{"type" => "string"},
             "tags" => %{"type" => "array", "items" => %{"type" => "string"}}
           }
  end

  test "a payload downgraded to an endpoint's version" do
    payload = %{"api_version" => "2026-10-01", "data" => %{"object" => %{"title" => "Hello"}}}

    assert Kunai.Versions.downgrade(Webhooks, payload, "2026-10-01", "2026-06-01") ==
             %{"api_version" => "2026-06-01", "data" => %{"object" => %{"name" => "Hello"}}}

    assert Kunai.Versions.downgrade(Webhooks, payload, "2026-10-01", "2026-10-01") == payload
  end

  test "patterns of subscriptions" do
    assert Kunai.Subscriptions.matches?("*", "page.published")
    assert Kunai.Subscriptions.matches?("page.*", "page.published")
    refute Kunai.Subscriptions.matches?("page.*", "pages.published")
    assert Kunai.Subscriptions.matches?("page.published", "page.published")
    refute Kunai.Subscriptions.matches?("page.published", "page.deleted")
  end
end
