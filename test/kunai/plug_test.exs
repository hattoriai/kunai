defmodule Kunai.Plug.VerifyTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Kunai.Plug.Verify
  alias Kunai.{Secret, Signature}

  setup do
    {:hmac, key, secret} = Secret.generate(:hmac)
    %{key: key, secret: secret}
  end

  defp signed(body, key, at \\ System.system_time(:second)) do
    conn(:post, "/webhooks", body)
    |> put_req_header("webhook-id", "msg_1")
    |> put_req_header("webhook-timestamp", to_string(at))
    |> put_req_header("webhook-signature", Signature.header([{:hmac, key}], "msg_1", at, body))
    |> assign(:raw_body, body)
  end

  test "a request signed with the endpoint's secret gives its event", %{key: key, secret: secret} do
    body = ~s|{"type":"page.published","data":{"object":{"id":"page_1"}}}|
    opts = Verify.init(secrets: [secret])
    conn = Verify.call(signed(body, key), opts)

    refute conn.halted
    assert conn.assigns.webhook["type"] == "page.published"
  end

  test "secrets from a function of the conn", %{key: key, secret: secret} do
    opts = Verify.init(secrets: fn _conn -> [secret] end, assign: :event)
    conn = Verify.call(signed("{}", key), opts)
    assert conn.assigns.event == %{}
  end

  test "a request not signed, or too old, is answered 400", %{key: key, secret: secret} do
    opts = Verify.init(secrets: [secret])

    conn = Verify.call(conn(:post, "/webhooks", "{}") |> assign(:raw_body, "{}"), opts)
    assert conn.halted and conn.status == 400
    assert JSON.decode!(conn.resp_body) == %{"error" => "missing_headers"}

    conn = Verify.call(signed("{}", key, System.system_time(:second) - 600), opts)
    assert conn.status == 400
    assert JSON.decode!(conn.resp_body) == %{"error" => "timestamp_too_old"}
  end
end
