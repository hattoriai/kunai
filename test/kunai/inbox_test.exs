defmodule Kunai.Dev.InboxTest do
  # The inbox is the node's: alone.
  use KunaiTest.DataCase
  use PhoenixMountable.Test, host: KunaiTest.Host

  alias Kunai.Dev.Inbox

  @url "http://localhost:4000/dev/webhooks/inbox/billing"

  setup %{conn: conn} do
    Inbox.ensure_started()
    Inbox.clear()
    %{conn: init_test_session(conn, %{"site" => "1"})}
  end

  defp plug(conn), do: Inbox.call(conn, Inbox.init([]))

  # What Kunai sent, as the inbox receives it.
  defp sent do
    assert_received {:request, url, headers, body}
    {url, headers, body}
  end

  defp receive_in_inbox({url, headers, body}, extra \\ "") do
    Enum.reduce(headers, Plug.Test.conn(:post, url <> extra, body), fn {name, value}, conn ->
      Plug.Conn.put_req_header(conn, name, value)
    end)
    |> plug()
  end

  test "a delivery to the inbox is kept, its signature verified" do
    {endpoint, _secret} = endpoint!(%{url: @url})
    emit!("page.published", %{id: "page_1"})
    drain()

    conn = receive_in_inbox(sent())
    assert conn.halted and conn.status == 200

    assert [request] = Inbox.list()
    assert %{inbox: "billing", event_type: "page.published", status: 200, verified: :ok} = request
    assert request.endpoint_id == endpoint.id
    assert request.webhook_id =~ "msg_"
  end

  test "it answers as its address says, and tells a body that does not verify" do
    endpoint!(%{url: @url})
    emit!("page.published", %{id: "page_1"})
    drain()
    {url, headers, body} = sent()

    assert receive_in_inbox({url, headers, body}, "?status=503").status == 503

    assert receive_in_inbox({url, headers, String.replace(body, "page_1", "page_2")}).status ==
             200

    assert [tampered, failed] = Inbox.list()
    assert failed.status == 503 and failed.verified == :ok
    assert tampered.verified == {:error, :invalid_signature}
  end

  test "a request to an address no endpoint has, and the app's other requests" do
    conn = plug(Plug.Test.conn(:post, "/dev/webhooks/inbox/stray", ~s({"type":"x"})))
    assert [%{inbox: "stray", verified: :unknown_endpoint}] = Inbox.list()
    assert conn.halted

    for conn <- [
          Plug.Test.conn(:get, "/dev/webhooks/inbox/stray"),
          Plug.Test.conn(:post, "/pages")
        ] do
      refute plug(conn).halted
    end
  end

  test "the page: the requests as they arrive, each opened", %{conn: conn} do
    {:ok, view, html} = live(conn, "/webhooks/inbox")
    assert html =~ "Nothing yet"
    assert html =~ "/dev/webhooks/inbox/test"

    plug(Plug.Test.conn(:post, "/dev/webhooks/inbox/stray", ~s({"type":"page.published"})))
    assert render(view) =~ "stray"

    [request] = Inbox.list()
    html = view |> element("#request-#{request.id} a") |> render_click()
    assert html =~ "No endpoint"
    assert html =~ "Headers"

    view |> element("button", "Clear") |> render_click()
    assert render(view) =~ "Nothing yet"
  end

  test "the address of the inbox, given to a new endpoint", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/webhooks/new?url=" <> URI.encode_www_form(@url))
    assert html =~ ~s(value="#{@url}")
  end

  test "without the plug, the page is not there", %{conn: conn} do
    Supervisor.terminate_child(Kunai.Supervisor, Kunai.Dev.Inbox.Store)
    on_exit(&Inbox.ensure_started/0)

    assert {:error, {:live_redirect, %{to: "/webhooks"}}} = live(conn, "/webhooks/inbox")
    {:ok, _view, html} = live(conn, "/webhooks")
    refute html =~ "Inbox"
  end
end
