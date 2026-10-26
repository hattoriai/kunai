defmodule Kunai.APITest do
  use KunaiTest.DataCase
  use PhoenixMountable.Test, host: KunaiTest.Host

  @api "/api/v1/webhooks"

  setup %{conn: conn} do
    %{conn: conn |> put_req_header("x-site", "1") |> put_req_header("accept", "application/json")}
  end

  defp create!(conn, attrs \\ %{}) do
    attrs = Map.merge(%{"url" => "https://hooks.example.com/a", "events" => ["page.*"]}, attrs)
    conn |> post(@api <> "/endpoints", attrs) |> json_response(201)
  end

  test "an endpoint made, with its secret shown once", %{conn: conn} do
    created = create!(conn, %{"description" => "Billing"})

    assert %{"id" => "ep_" <> _, "object" => "endpoint", "secret" => "whsec_" <> _} = created
    assert created["scopes"] == ["members:read", "pages:read"]

    shown = conn |> get(@api <> "/endpoints/#{created["id"]}") |> json_response(200)
    assert shown["description"] == "Billing"
    refute Map.has_key?(shown, "secret")
  end

  test "invalid parameters, in one error format", %{conn: conn} do
    error =
      conn
      |> post(@api <> "/endpoints", %{"url" => "http:/nope", "events" => []})
      |> json_response(400)

    assert %{
             "error" => %{
               "type" => "invalid_request_error",
               "code" => "parameter_invalid",
               "param" => "events",
               "errors" => %{"events" => _, "url" => _}
             }
           } = error
  end

  test "no scope, no access; another owner's endpoint is missing", %{conn: conn} do
    created = create!(conn)

    assert %{"error" => %{"type" => "authentication_error"}} =
             build_conn() |> get(@api <> "/endpoints") |> json_response(401)

    other = build_conn() |> put_req_header("x-site", "2")

    assert %{"error" => %{"code" => "resource_missing"}} =
             other |> get(@api <> "/endpoints/#{created["id"]}") |> json_response(404)
  end

  test "lists with cursors", %{conn: conn} do
    ids = for n <- 1..3, do: create!(conn, %{"url" => "https://hooks.example.com/#{n}"})["id"]

    page = conn |> get(@api <> "/endpoints", %{"limit" => "2"}) |> json_response(200)
    assert %{"object" => "list", "url" => "/api/v1/webhooks/endpoints", "has_more" => true} = page
    assert Enum.map(page["data"], & &1["id"]) == ids |> Enum.reverse() |> Enum.take(2)

    rest =
      conn
      |> get(@api <> "/endpoints", %{
        "limit" => "2",
        "starting_after" => List.last(page["data"])["id"]
      })
      |> json_response(200)

    assert Enum.map(rest["data"], & &1["id"]) == [hd(ids)] and rest["has_more"] == false
  end

  test "updated, rolled, disabled, enabled and deleted", %{conn: conn} do
    %{"id" => id, "secret" => old} = create!(conn)

    assert %{"description" => "Shop"} =
             conn
             |> post(@api <> "/endpoints/#{id}", %{"description" => "Shop"})
             |> json_response(200)

    assert %{"ordered" => true} =
             conn |> patch(@api <> "/endpoints/#{id}", %{"ordered" => true}) |> json_response(200)

    %{"secret" => new} =
      conn
      |> post(@api <> "/endpoints/#{id}/roll_secret", %{"expires_in" => 0})
      |> json_response(200)

    assert new != old

    assert %{"status" => "disabled"} =
             conn |> post(@api <> "/endpoints/#{id}/disable") |> json_response(200)

    assert %{"status" => "enabled"} =
             conn |> post(@api <> "/endpoints/#{id}/enable") |> json_response(200)

    assert %{"deleted" => true} = conn |> delete(@api <> "/endpoints/#{id}") |> json_response(200)
    assert conn |> get(@api <> "/endpoints/#{id}") |> json_response(404)
  end

  test "an Idempotency-Key gives the same response again", %{conn: conn} do
    keyed = put_req_header(conn, "idempotency-key", "k-1")
    params = %{"url" => "https://hooks.example.com/once", "events" => ["*"]}

    first = keyed |> post(@api <> "/endpoints", params)
    again = keyed |> post(@api <> "/endpoints", params)

    assert json_response(again, 201) == json_response(first, 201)
    assert get_resp_header(again, "idempotent-replayed") == ["true"]
    assert length(Kunai.list_endpoints(scope()).data) == 1

    other =
      keyed
      |> post(@api <> "/endpoints", Map.put(params, "url", "https://hooks.example.com/twice"))

    assert %{"error" => %{"type" => "idempotency_error"}} = json_response(other, 422)

    # Another owner's same key is its own.
    assert build_conn()
           |> put_req_header("x-site", "2")
           |> put_req_header("idempotency-key", "k-1")
           |> post(@api <> "/endpoints", params)
           |> json_response(201)
  end

  test "events, deliveries with their attempts, expanded, and sent again", %{conn: conn} do
    %{"id" => endpoint_id} = create!(conn)
    event = emit!("page.published", %{id: "page_1", title: "Hello"})
    drain()

    events = conn |> get(@api <> "/events", %{"type" => "page.published"}) |> json_response(200)

    assert [
             %{
               "id" => event_id,
               "object" => "event",
               "data" => %{"object" => %{"title" => "Hello"}}
             }
           ] = events["data"]

    assert event_id == event.id

    assert conn |> get(@api <> "/events/#{event.id}") |> json_response(200) |> Map.fetch!("type") ==
             "page.published"

    [delivery] =
      conn
      |> get(@api <> "/deliveries", %{"endpoint" => endpoint_id})
      |> json_response(200)
      |> Map.fetch!("data")

    assert %{"status" => "succeeded", "event" => ^event_id, "endpoint" => ^endpoint_id} = delivery

    shown =
      conn
      |> get(@api <> "/deliveries/#{delivery["id"]}", %{"expand" => ["event", "endpoint"]})
      |> json_response(200)

    assert %{"event" => %{"id" => ^event_id}, "endpoint" => %{"id" => ^endpoint_id}} = shown
    assert [%{"number" => 1, "status_code" => 200}] = shown["attempt_log"]

    assert %{"status" => "pending"} =
             conn |> post(@api <> "/deliveries/#{delivery["id"]}/retry") |> json_response(200)

    drain()

    assert %{"attempts" => 2, "status" => "succeeded"} =
             conn |> get(@api <> "/deliveries/#{delivery["id"]}") |> json_response(200)
  end

  test "a test event, and the catalog", %{conn: conn} do
    %{"id" => id} = create!(conn)

    assert %{"object" => "delivery", "event_type" => "page.published"} =
             conn
             |> post(@api <> "/endpoints/#{id}/test", %{"type" => "page.published"})
             |> json_response(201)

    assert %{"error" => %{"param" => "type"}} =
             conn
             |> post(@api <> "/endpoints/#{id}/test", %{"type" => "nope"})
             |> json_response(400)

    types = conn |> get(@api <> "/event_types") |> json_response(200) |> Map.fetch!("data")
    assert Enum.map(types, & &1["name"]) == ["member.invited", "page.deleted", "page.published"]
    assert hd(types)["schema"]["properties"]["type"] == %{"const" => "member.invited"}
  end

  test "the OpenAPI document, with the webhooks", %{conn: conn} do
    doc = conn |> get(@api <> "/openapi.json") |> json_response(200)

    assert doc["openapi"] == "3.1.0"
    assert doc["servers"] == [%{"url" => "/api/v1/webhooks"}]
    assert Map.has_key?(doc["paths"], "/endpoints/{id}/roll_secret")
    assert Map.keys(doc["webhooks"]) == ["member.invited", "page.deleted", "page.published"]
  end
end
