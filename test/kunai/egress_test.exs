defmodule Kunai.EgressTest do
  # Changes Kunai's egress options for the test.
  use ExUnit.Case, async: false

  alias Kunai.Egress

  setup do
    previous = Application.get_env(:kunai, :egress)
    Application.put_env(:kunai, :egress, [])
    on_exit(fn -> Application.put_env(:kunai, :egress, previous) end)
  end

  test "HTTPS only" do
    assert Egress.check_url("https://hooks.example.com/kunai") == :ok
    assert Egress.check_url("http://hooks.example.com/kunai") == {:error, :scheme_not_allowed}
    assert Egress.check_url("ftp://hooks.example.com") == {:error, :scheme_not_allowed}
    assert Egress.check_url("not a url") == {:error, :invalid_url}

    assert Egress.check_url("https://user:pass@hooks.example.com") ==
             {:error, :userinfo_not_allowed}
  end

  test "an address of the app's own network is refused" do
    for url <- [
          "https://127.0.0.1/",
          "https://10.1.2.3/",
          "https://172.20.0.1/",
          "https://192.168.1.1/",
          "https://169.254.169.254/latest/meta-data",
          "https://100.64.0.1/",
          "https://0.0.0.0/",
          "https://224.0.0.1/",
          "https://[::1]/",
          "https://[fd00::1]/",
          "https://[fe80::1]/",
          "https://[::ffff:127.0.0.1]/",
          "https://[64:ff9b::7f00:1]/"
        ] do
      assert Egress.check_url(url) == {:error, :private_address}, url
    end

    assert Egress.check_url("https://93.184.215.14/") == :ok
    assert Egress.check_url("https://[2606:4700::1111]/") == :ok
  end

  test "a name is resolved, and refused when it resolves to a private address" do
    assert Egress.resolve("https://localhost:4000/hooks") == {:error, :private_address}
  end

  test "a name that does not resolve" do
    assert Egress.resolve("https://kunai-does-not-exist.invalid/") == {:error, :unresolvable}
  end

  test "allowed, in development" do
    Application.put_env(:kunai, :egress, allow_http: true, allow_private: true)

    assert {:ok,
            %{scheme: :http, host: "localhost", port: 4000, path: "/hooks?a=1", address: address}} =
             Egress.resolve("http://localhost:4000/hooks?a=1")

    assert address in [{127, 0, 0, 1}, {0, 0, 0, 0, 0, 0, 0, 1}]
  end
end
