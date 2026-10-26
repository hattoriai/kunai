defmodule Kunai.Transport.HTTPTest do
  # Changes Kunai's options for the test.
  use ExUnit.Case, async: false

  alias Kunai.Transport.HTTP

  defmodule Receiver do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(%{request_path: "/slow"} = conn, _opts) do
      Process.sleep(1_000)
      send_resp(conn, 200, "late")
    end

    def call(%{request_path: "/large"} = conn, _opts),
      do: send_resp(conn, 200, String.duplicate("x", 200_000))

    def call(%{request_path: "/redirect"} = conn, _opts) do
      conn |> put_resp_header("location", "http://169.254.169.254/") |> send_resp(302, "")
    end

    def call(conn, _opts) do
      {:ok, body, conn} = read_body(conn)

      conn
      |> put_resp_header("retry-after", "7")
      |> send_resp(
        503,
        JSON.encode!(%{host: conn.host, id: get_req_header(conn, "webhook-id"), body: body})
      )
    end
  end

  setup do
    {:ok, server} = Bandit.start_link(plug: Receiver, port: 0, ip: :loopback, startup_log: false)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    previous = Application.get_all_env(:kunai)

    on_exit(fn ->
      for {key, value} <- previous, do: Application.put_env(:kunai, key, value)
      Application.delete_env(:kunai, :timeouts)
      Application.delete_env(:kunai, :max_response_bytes)
    end)

    %{base: "http://localhost:#{port}"}
  end

  test "a POST to the address checked, with the name as Host", %{base: base} do
    assert {:ok, %{status: 503, headers: headers, body: body}} =
             HTTP.request(base <> "/hook?a=1", [{"webhook-id", "msg_1"}], ~s|{"a":1}|, [])

    assert {"retry-after", "7"} in headers

    assert JSON.decode!(body) == %{
             "host" => "localhost",
             "id" => ["msg_1"],
             "body" => ~s|{"a":1}|
           }
  end

  test "a redirect is the answer, not followed", %{base: base} do
    assert {:ok, %{status: 302}} = HTTP.request(base <> "/redirect", [], "{}", [])
  end

  test "the total timeout", %{base: base} do
    Application.put_env(:kunai, :timeouts, total: 200)
    assert HTTP.request(base <> "/slow", [], "{}", []) == {:error, :timeout}
  end

  test "at most max_response_bytes of the response are read", %{base: base} do
    Application.put_env(:kunai, :max_response_bytes, 1_000)
    assert {:ok, %{status: 200, body: body}} = HTTP.request(base <> "/large", [], "{}", [])
    assert byte_size(body) == 1_000
  end

  test "an endpoint of the app's network is refused before any connection", %{base: base} do
    Application.put_env(:kunai, :egress, allow_http: true)
    assert HTTP.request(base <> "/hook", [], "{}", []) == {:error, :private_address}
  end

  test "a connection refused is an error, tried again" do
    assert {:error, :econnrefused} = HTTP.request("http://127.0.0.1:1/hook", [], "{}", [])
  end
end
