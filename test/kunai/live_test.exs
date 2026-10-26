defmodule Kunai.LiveTest do
  use KunaiTest.DataCase
  use PhoenixMountable.Test, host: KunaiTest.Host

  setup %{conn: conn} do
    %{conn: init_test_session(conn, %{"site" => "1"})}
  end

  test "no endpoints yet, then a list of them", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/webhooks")
    assert html =~ "Listen for this account&#39;s events"

    {endpoint, _secret} = endpoint!(%{description: "Billing", events: ["page.*"]})
    {:ok, view, _html} = live(conn, "/webhooks")
    assert has_element?(view, "##{endpoint.id} a", endpoint.url)
    assert render(view) =~ "page.*"
  end

  test "an endpoint added, its secret shown once", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/webhooks/new")

    assert view |> form("#kunai-endpoint-form", endpoint: %{url: "ftp://nope"}) |> render_change() =~
             "is not a valid URL" or render(view) =~ "must use HTTPS"

    # All events unchecked, the events show, one by one.
    view |> form("#kunai-endpoint-form", endpoint: %{events: [""]}) |> render_change()
    assert render(view) =~ "must have at least one event"

    html =
      view
      |> form("#kunai-endpoint-form",
        endpoint: %{url: "https://hooks.example.com/new", events: ["", "page.published"]}
      )
      |> render_submit()

    assert html =~ "Endpoint added"
    [endpoint] = Kunai.list_endpoints(scope()).data
    assert endpoint.events == ["page.published"]
    assert has_element?(view, "#kunai-new-secret code", Kunai.secret(endpoint))
  end

  test "an endpoint's page: secret, test, deliveries live", %{conn: conn} do
    {endpoint, secret} = endpoint!()
    {:ok, view, _html} = live(conn, "/webhooks/#{endpoint.id}")

    assert has_element?(view, "#kunai-secret .kunai-secret-value--hidden")
    refute render(view) =~ secret
    view |> element("button", "Reveal") |> render_click()
    assert has_element?(view, "#kunai-secret code", secret)

    view |> form("#kunai-test", type: "page.published") |> render_submit()
    assert render(view) =~ "A test page.published is on its way"

    drain()
    # The attempt reaches the page over PubSub.
    assert render(view) =~ "Delivered"
    [delivery] = Kunai.list_deliveries(scope()).data
    assert has_element?(view, "##{delivery.id}", "200")
  end

  test "disabled, enabled, rolled and deleted", %{conn: conn} do
    {endpoint, old} = endpoint!()
    {:ok, view, _html} = live(conn, "/webhooks/#{endpoint.id}")

    view |> element("button", "Disable") |> render_click()
    assert render(view) =~ "It receives no events until it is enabled"
    view |> element("button", "Enable") |> render_click()
    assert Kunai.get_endpoint(scope(), endpoint.id).status == "enabled"

    view |> element("button", "Roll") |> render_click()
    assert render(view) =~ "The old one still signs for a day"
    refute Kunai.secret(endpoint) == old

    view |> element("button", "Delete") |> render_click()
    assert_redirect(view, "/webhooks")
    assert Kunai.get_endpoint(scope(), endpoint.id) == nil
  end

  test "an endpoint edited", %{conn: conn} do
    {endpoint, _secret} = endpoint!()
    {:ok, view, _html} = live(conn, "/webhooks/#{endpoint.id}/edit")

    view
    |> form("#kunai-endpoint-form", endpoint: %{description: "Shop", payload: "thin"})
    |> render_submit()

    assert_redirect(view, "/webhooks/#{endpoint.id}")
    assert %{description: "Shop", payload: "thin"} = Kunai.get_endpoint(scope(), endpoint.id)
  end

  test "a delivery: its attempts, its payload, sent again", %{conn: conn} do
    {endpoint, _secret} = endpoint!()
    Transport.respond(endpoint.url, [{503, []}, 200])
    emit!("page.published", %{id: "page_1", title: "Hello"})
    drain()

    [delivery] = Kunai.list_deliveries(scope()).data
    {:ok, view, html} = live(conn, "/webhooks/deliveries/#{delivery.id}")
    assert html =~ "503"
    assert html =~ ~s|&quot;title&quot;: &quot;Hello&quot;|

    view |> element("button", "Send again") |> render_click()
    drain()
    assert render(view) =~ "Delivered"
  end

  test "another owner's endpoint is not found", %{conn: conn} do
    {endpoint, _secret} = endpoint!(%{}, scope: scope("2"))

    assert {:error, {:live_redirect, %{to: "/webhooks", flash: %{"error" => _}}}} =
             live(conn, "/webhooks/#{endpoint.id}")
  end

  test "in the app's layout", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/settings/webhooks")
    assert has_element?(view, "#app-layout[data-site='1'] .kunai")
    assert has_element?(view, "a[href='/settings/webhooks/new']")
  end
end
