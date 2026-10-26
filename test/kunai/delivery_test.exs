defmodule Kunai.DeliveryTest do
  use KunaiTest.DataCase

  alias Ecto.Multi
  alias Kunai.{Delivery, Event, Verifier}

  require KunaiTest.Webhooks

  defp repo, do: Kunai.Config.repo()

  describe "emit" do
    test "in the transaction of the change: committed, it is delivered, signed" do
      {endpoint, secret} = endpoint!()

      {:ok, %{event: event}} =
        Multi.new()
        |> Multi.put(:page, %{id: "page_1", title: "Hello", tags: ["a"]})
        |> KunaiTest.Webhooks.emit("page.published", & &1.page,
          scope: scope(),
          as: :event,
          previous: %{title: "Draft"}
        )
        |> repo().transaction()

      assert %Event{type: "page.published", owner: "site:1", object_id: "page_1"} = event
      assert event.actor == %{"type" => "user", "id" => "u1"}
      assert event.previous == %{"title" => "Draft"}

      assert %{success: 2} = drain()
      url = endpoint.url
      assert_received {:request, ^url, headers, body}

      [delivery] = Kunai.list_deliveries(scope()).data
      assert delivery.status == "succeeded" and delivery.attempts == 1
      assert headers["webhook-id"] == delivery.id
      assert headers["content-type"] == "application/json"
      assert Verifier.verify(body, headers, [secret]) == :ok

      payload = JSON.decode!(body)
      assert payload["id"] == event.id
      assert payload["type"] == "page.published"
      assert payload["api_version"] == "2026-10-01"

      assert payload["data"] == %{
               "object" => %{"id" => "page_1", "title" => "Hello", "tags" => ["a"]},
               "previous" => %{"title" => "Draft"}
             }
    end

    test "rolled back, nothing is kept nor sent" do
      endpoint!()

      {:error, :boom, :failed, _changes} =
        Multi.new()
        |> KunaiTest.Webhooks.emit("page.published", %{id: "page_1"}, scope: scope())
        |> Multi.run(:boom, fn _repo, _changes -> {:error, :failed} end)
        |> repo().transaction()

      assert Kunai.list_events(scope()).data == []
      assert %{success: 0} = drain()
      refute_received {:request, _url, _headers, _body}
    end

    test "fields redacted by the event and the catalog are never kept" do
      endpoint!()

      event =
        emit!("member.invited", %{
          id: "m1",
          token: "t0k3n",
          secret_note: "x",
          email: "a@example.com"
        })

      assert event.data == %{"id" => "m1", "email" => "a@example.com"}
    end
  end

  describe "fan-out" do
    test "to the owner's endpoints subscribed to the event, with its scopes" do
      {all, _} = endpoint!(%{events: ["*"]})
      {pages, _} = endpoint!(%{events: ["page.*"]})
      {_members, _} = endpoint!(%{events: ["member.invited"]})
      {_no_scope, _} = endpoint!(%{events: ["page.published"], scopes: []})
      {_other_site, _} = endpoint!(%{events: ["*"]}, scope: scope("2"))

      emit!("page.published", %{id: "page_1"})
      drain()

      delivered =
        for %{endpoint_id: id} <- Kunai.list_deliveries(scope()).data, into: MapSet.new(), do: id

      assert delivered == MapSet.new([all.id, pages.id])
      assert Kunai.list_deliveries(scope("2")).data == []
    end

    test "a disabled endpoint gets nothing, and a change is seen at once" do
      {endpoint, _} = endpoint!()
      emit!("page.published", %{id: "page_1"})
      drain()
      assert length(Kunai.list_deliveries(scope()).data) == 1

      {:ok, _endpoint} = Kunai.disable_endpoint(scope(), endpoint)
      emit!("page.published", %{id: "page_2"})
      drain()
      assert length(Kunai.list_deliveries(scope()).data) == 1
    end

    test "a thin payload has the object's id only" do
      {endpoint, _} = endpoint!(%{payload: "thin"})
      emit!("page.published", %{id: "page_1", title: "Hello"})
      drain()

      url = endpoint.url
      assert_received {:request, ^url, _headers, body}
      assert JSON.decode!(body)["data"] == %{"object" => %{"id" => "page_1"}}
    end

    test "an endpoint pinned to an older version gets its payload downgraded" do
      {endpoint, _} = endpoint!(%{api_version: "2026-06-01"})
      emit!("page.published", %{id: "page_1", title: "Hello"})
      drain()

      url = endpoint.url
      assert_received {:request, ^url, _headers, body}
      payload = JSON.decode!(body)
      assert payload["api_version"] == "2026-06-01"
      assert payload["data"]["object"] == %{"id" => "page_1", "name" => "Hello"}
    end
  end

  describe "answers" do
    test "a 500 is tried again, with the same webhook-id, until it succeeds" do
      {endpoint, _} = endpoint!()
      Transport.respond(endpoint.url, [500, {:error, :timeout}, 200])

      emit!("page.published", %{id: "page_1"})
      drain_over_time()

      [delivery] = Kunai.list_deliveries(scope()).data
      assert delivery.status == "succeeded" and delivery.attempts == 3

      ids =
        for _ <- 1..3,
            do:
              (
                assert_received({:request, _url, %{"webhook-id" => id}, _body})
                id
              )

      assert Enum.uniq(ids) == [delivery.id]

      attempts = Kunai.get_delivery(scope(), delivery.id).attempt_log

      assert Enum.map(attempts, &{&1.number, &1.status_code, &1.error}) == [
               {1, 500, nil},
               {2, nil, "timeout"},
               {3, 200, nil}
             ]

      assert Kunai.get_endpoint(scope(), endpoint.id).failing_since == nil
    end

    test "a failure schedules the next attempt, obeying a longer Retry-After" do
      {endpoint, _} = endpoint!()
      Transport.respond(endpoint.url, [{429, [{"retry-after", "120"}]}])

      emit!("page.published", %{id: "page_1"})
      drain()

      [delivery] = Kunai.list_deliveries(scope()).data
      assert delivery.status == "pending" and delivery.last_status_code == 429
      assert_in_delta DateTime.diff(delivery.next_attempt_at, DateTime.utc_now()), 120, 2
      assert Kunai.get_endpoint(scope(), endpoint.id).failing_since
    end

    test "after the schedule, it gives up" do
      {endpoint, _} = endpoint!()
      Transport.respond(endpoint.url, [400])

      emit!("page.published", %{id: "page_1"})
      drain_over_time()

      [delivery] = Kunai.list_deliveries(scope()).data
      assert delivery.status == "failed" and delivery.attempts == 12
      assert delivery.last_error == "status 400"
      # One failure never disables: the endpoint failed for seconds, not days.
      assert Kunai.get_endpoint(scope(), endpoint.id).status == "enabled"
    end

    test "410 Gone disables the endpoint" do
      {endpoint, _} = endpoint!()
      Transport.respond(endpoint.url, [410])

      emit!("page.published", %{id: "page_1"})
      drain()

      assert %{status: "disabled", disabled_reason: "gone"} =
               Kunai.get_endpoint(scope(), endpoint.id)

      assert [%{status: "failed", last_error: "gone"}] = Kunai.list_deliveries(scope()).data

      assert [%{action: "disabled", actor: %{"type" => "system"}} | _] =
               Kunai.list_audit_log(scope()).data
    end

    test "an endpoint failing for days is warned, then disabled" do
      {endpoint, _} = endpoint!()
      Transport.respond(endpoint.url, [503])
      two_days_ago = DateTime.add(DateTime.utc_now(), -2 * 86_400, :second)
      set_failing_since(endpoint, two_days_ago)

      emit!("page.published", %{id: "page_1"})
      drain()
      endpoint = Kunai.get_endpoint(scope(), endpoint.id)
      assert endpoint.status == "enabled" and endpoint.warned_at

      set_failing_since(endpoint, DateTime.add(two_days_ago, -86_400, :second))
      emit!("page.published", %{id: "page_2"})
      drain()

      assert %{status: "disabled", disabled_reason: "failing"} =
               Kunai.get_endpoint(scope(), endpoint.id)
    end

    test "a payload too large is not sent" do
      {endpoint, _} = endpoint!()
      emit!("page.published", %{id: "page_1", title: String.duplicate("a", 300_000)})
      drain()

      assert [%{status: "failed", last_error: "payload_too_large", attempts: 0}] =
               Kunai.list_deliveries(scope()).data

      url = endpoint.url
      refute_received {:request, ^url, _headers, _body}
    end
  end

  defp set_failing_since(endpoint, at) do
    endpoint |> Ecto.Changeset.change(failing_since: at) |> repo().update!()
  end

  describe "in order" do
    test "a delivery waits for the one before it" do
      {endpoint, _} = endpoint!(%{ordered: true})
      Transport.respond(endpoint.url, [500, 200])

      emit!("page.published", %{id: "page_1"})
      emit!("page.published", %{id: "page_2"})
      drain()

      [second, first] = Kunai.list_deliveries(scope()).data
      assert first.status == "pending" and first.attempts == 1
      assert second.status == "pending" and second.attempts == 0

      # The first succeeds, and the second goes at once after it.
      {:ok, _first} = Kunai.retry_delivery(scope(), first)
      drain()

      assert Enum.map(Kunai.list_deliveries(scope()).data, & &1.status) == [
               "succeeded",
               "succeeded"
             ]

      bodies =
        for _ <- 1..3,
            do:
              (
                assert_received({:request, _url, _headers, body})
                JSON.decode!(body)["data"]["object"]["id"]
              )

      assert bodies == ["page_1", "page_1", "page_2"]
    end
  end

  describe "secrets" do
    test "a rolled secret signs beside the new one until it expires" do
      {endpoint, old} = endpoint!()
      {:ok, new} = Kunai.roll_secret(scope(), endpoint)
      assert new != old and Kunai.secret(endpoint) == new

      emit!("page.published", %{id: "page_1"})
      drain()
      assert_received {:request, _url, headers, body}
      assert [_old, _new] = String.split(headers["webhook-signature"], " ")
      assert Verifier.verify(body, headers, [old]) == :ok
      assert Verifier.verify(body, headers, [new]) == :ok

      {:ok, newest} = Kunai.roll_secret(scope(), endpoint, expires_in: 0)
      emit!("page.published", %{id: "page_2"})
      drain()
      assert_received {:request, _url, headers, body}
      assert Verifier.verify(body, headers, [newest]) == :ok
      assert Verifier.verify(body, headers, [new]) == {:error, :invalid_signature}
    end

    test "Ed25519: the owner keeps the public key" do
      {_endpoint, public} = endpoint!(%{}, signing: :ed25519)
      assert "whpk_" <> _ = public

      emit!("page.published", %{id: "page_1"})
      drain()
      assert_received {:request, _url, headers, body}
      assert "v1a," <> _ = headers["webhook-signature"]
      assert Verifier.verify(body, headers, [public]) == :ok
    end

    test "kept encrypted by the vault" do
      Application.put_env(:kunai, :vault, {KunaiTest.ReversingVault, []})
      on_exit(fn -> Application.put_env(:kunai, :vault, Kunai.Vault.Unencrypted) end)

      {endpoint, "whsec_" <> encoded} = endpoint!()
      [row] = repo().all(Kunai.EndpointSecret)
      assert row.ciphertext == String.reverse(Base.decode64!(encoded))
      assert Kunai.secret(endpoint) == "whsec_" <> encoded
    end
  end

  describe "the API of an owner" do
    test "an endpoint's URL and events are checked" do
      assert {:error, changeset} =
               Kunai.create_endpoint(scope(), %{url: "ftp://x", events: ["nothing.here"]})

      errors =
        Ecto.Changeset.traverse_errors(changeset, fn {message, values} ->
          Enum.reduce(values, message, fn {k, v}, acc ->
            String.replace(acc, "%{#{k}}", to_string(v))
          end)
        end)

      assert errors == %{url: ["must use HTTPS"], events: ["has unknown events: nothing.here"]}
    end

    test "a scope sees its own owner's rows only" do
      {endpoint, _} = endpoint!()
      assert Kunai.get_endpoint(scope("2"), endpoint.id) == nil
      event = emit!("page.published", %{id: "page_1"})
      assert Kunai.get_event(scope("2"), event.id) == nil
      assert Kunai.get_event(scope(), event.id).id == event.id
    end

    test "pages of events, newest first, with cursors" do
      ids = for n <- 1..5, do: emit!("page.published", %{id: "page_#{n}"}).id
      [e5, e4, e3, e2, e1] = Enum.reverse(ids)

      page = Kunai.list_events(scope(), limit: 2)
      assert Enum.map(page.data, & &1.id) == [e5, e4] and page.has_more

      page = Kunai.list_events(scope(), limit: 2, starting_after: e4)
      assert Enum.map(page.data, & &1.id) == [e3, e2] and page.has_more

      page = Kunai.list_events(scope(), limit: 2, starting_after: e2)
      assert Enum.map(page.data, & &1.id) == [e1] and not page.has_more

      page = Kunai.list_events(scope(), limit: 2, ending_before: e2)
      assert Enum.map(page.data, & &1.id) == [e4, e3]
    end

    test "a test event to one endpoint, with the catalog's example" do
      {endpoint, _} = endpoint!()
      {other, _} = endpoint!()

      {:ok, delivery} = Kunai.send_test(scope(), endpoint, "page.published")
      drain()

      url = endpoint.url
      assert_received {:request, ^url, _headers, body}
      other_url = other.url
      refute_received {:request, ^other_url, _headers, _body}
      payload = JSON.decode!(body)
      assert payload["test"] == true and payload["data"]["object"]["id"] == "page_example"
      assert repo().get(Delivery, delivery.id).status == "succeeded"
    end

    test "deliveries that failed are replayed once the endpoint is back" do
      {endpoint, _} = endpoint!()
      Transport.respond(endpoint.url, [400])
      Application.put_env(:kunai, :retry_policy, {Kunai.RetryPolicy.Default, schedule: []})

      on_exit(fn ->
        Application.put_env(:kunai, :retry_policy, {Kunai.RetryPolicy.Default, jitter: 0})
      end)

      emit!("page.published", %{id: "page_1"})
      emit!("page.published", %{id: "page_2"})
      drain()
      assert Enum.map(Kunai.list_deliveries(scope()).data, & &1.status) == ["failed", "failed"]

      Transport.respond(endpoint.url, [200])
      assert {:ok, 2} = Kunai.replay(scope(), endpoint)
      drain()

      assert Enum.map(Kunai.list_deliveries(scope()).data, & &1.status) == [
               "succeeded",
               "succeeded"
             ]
    end

    test "the audit log of an endpoint" do
      {endpoint, _} = endpoint!()
      {:ok, endpoint} = Kunai.update_endpoint(scope(), endpoint, %{description: "Billing"})
      {:ok, _secret} = Kunai.roll_secret(scope("1", "u2"), endpoint)
      {:ok, _deleted} = Kunai.delete_endpoint(scope(), endpoint)

      log = Kunai.list_audit_log(scope(), endpoint_id: endpoint.id).data
      assert Enum.map(log, & &1.action) == ["deleted", "secret_rolled", "updated", "created"]
      assert Enum.at(log, 1).actor == %{"type" => "user", "id" => "u2"}
      assert Enum.at(log, 2).changes == %{"description" => "Billing"}
    end

    test "old events are pruned, with their deliveries and attempts" do
      endpoint!()
      event = emit!("page.published", %{id: "page_1"})
      drain()

      old = DateTime.add(DateTime.utc_now(), -31 * 86_400, :second)
      repo().update_all(Event, set: [created_at: old])
      repo().update_all(Kunai.Attempt, set: [created_at: old])

      assert {:ok, %{events: 1, attempts: 1}} = Kunai.prune(30)
      assert Kunai.get_event(scope(), event.id) == nil
      assert Kunai.list_deliveries(scope()).data == []
    end
  end
end
