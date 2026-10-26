defmodule Kunai.TestingTest do
  # Kunai.Testing as an app's tests use it, with its transport: alone.
  use KunaiTest.DataCase

  import Kunai.Testing

  setup do
    transport = Application.get_env(:kunai, :transport)
    Application.put_env(:kunai, :transport, Kunai.Testing.Transport)
    on_exit(fn -> Application.put_env(:kunai, :transport, transport) end)
  end

  test "events emitted, matched by type and fields" do
    emit!("page.published", %{id: "page_1", title: "Hello", tags: ["a"]},
      previous: %{title: "Draft"}
    )

    event = assert_emitted("page.published", %{title: "Hello"})
    assert event.previous == %{"title" => "Draft"}
    assert [_one] = emitted("page.published")
    refute_emitted("page.published", %{title: "Other"})
    refute_emitted("member.invited")

    message =
      assert_raise ExUnit.AssertionError, fn ->
        assert_emitted("page.published", %{title: "Bye"})
      end

    assert message.message =~ ~s|No page.published event with %{"title" => "Bye"}|
    assert message.message =~ "Emitted: page.published"

    assert_raise ExUnit.AssertionError, ~r/A page.published event was emitted/, fn ->
      refute_emitted("page.published")
    end
  end

  test "requests delivered, signed with the endpoint's secret, answered as told" do
    {endpoint, _secret} = endpoint!()
    {other, _secret} = endpoint!(%{url: "https://hooks.example.com/other"})
    respond(other, [503, 200])

    emit!("page.published", %{id: "page_1", title: "Hello"})
    deliver()

    payload = assert_delivered("page.published", to: endpoint, data: %{title: "Hello"})
    assert payload["data"]["object"]["id"] == "page_1"

    # The other's first answer failed: tried again later, then delivered.
    assert_delivered("page.published", to: other)
    refute_delivered("page.published")
    deliver(retries: true)
    assert Enum.all?(Kunai.list_deliveries(scope()).data, &(&1.status == "succeeded"))
    assert_delivered("page.published", to: other.url)

    assert_raise ExUnit.AssertionError, ~r/No member.invited request was sent/, fn ->
      assert_delivered("member.invited")
    end
  end

  test "a request signed with another secret fails the assertion" do
    {endpoint, _secret} = endpoint!()
    emit!("page.published", %{id: "page_1"})
    deliver()
    {:ok, _secret} = Kunai.roll_secret(scope(), endpoint, expires_in: 0)

    assert_raise ExUnit.AssertionError, ~r/not signed with its secret/, fn ->
      assert_delivered("page.published", to: endpoint)
    end
  end
end
