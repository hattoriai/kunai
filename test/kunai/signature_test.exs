defmodule Kunai.SignatureTest do
  use ExUnit.Case, async: true

  alias Kunai.{Secret, Signature, Verifier}

  # The example of the Standard Webhooks specification.
  @secret "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"
  @id "msg_p5jXN8AQM9LWM0D4loKWxJek"
  @timestamp 1_614_265_330
  @body ~s|{"test": 2432232314}|

  test "signs as the Standard Webhooks specification does" do
    {:ok, {:hmac, key}} = Secret.decode(@secret)

    assert Signature.header([{:hmac, key}], @id, @timestamp, @body) ==
             "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE="
  end

  defp headers(signature, timestamp \\ @timestamp) do
    %{
      "webhook-id" => @id,
      "webhook-timestamp" => to_string(timestamp),
      "webhook-signature" => signature
    }
  end

  test "verifies the specification's example" do
    headers = headers("v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=")
    assert Verifier.verify(@body, headers, [@secret], now: @timestamp) == :ok
  end

  test "refuses a body changed, another secret, a timestamp out of range" do
    {:ok, {:hmac, key}} = Secret.decode(@secret)
    header = Signature.header([{:hmac, key}], @id, @timestamp, @body)

    assert Verifier.verify(@body <> " ", headers(header), [@secret], now: @timestamp) ==
             {:error, :invalid_signature}

    {:hmac, _key, other} = Secret.generate(:hmac)

    assert Verifier.verify(@body, headers(header), [other], now: @timestamp) ==
             {:error, :invalid_signature}

    assert Verifier.verify(@body, headers(header), [@secret], now: @timestamp + 301) ==
             {:error, :timestamp_too_old}

    assert Verifier.verify(@body, headers(header), [@secret], now: @timestamp - 301) ==
             {:error, :timestamp_too_new}

    assert Verifier.verify(@body, %{}, [@secret]) == {:error, :missing_headers}

    assert Verifier.verify(@body, headers(header, "soon"), [@secret]) ==
             {:error, :invalid_timestamp}
  end

  test "Ed25519: signed with the private key, verified with the public one" do
    {:ed25519, private, _public, public_secret} = Secret.generate(:ed25519)
    assert "whpk_" <> _ = public_secret

    header = Signature.header([{:ed25519, private}], @id, @timestamp, @body)
    assert "v1a," <> _ = header
    assert Verifier.verify(@body, headers(header), [public_secret], now: @timestamp) == :ok

    assert Verifier.verify("{}", headers(header), [public_secret], now: @timestamp) ==
             {:error, :invalid_signature}
  end

  test "during a rotation, either secret passes" do
    {:hmac, old, old_secret} = Secret.generate(:hmac)
    {:hmac, new, new_secret} = Secret.generate(:hmac)
    header = Signature.header([{:hmac, old}, {:hmac, new}], @id, @timestamp, @body)

    assert [_one, _two] = String.split(header, " ")
    assert Verifier.verify(@body, headers(header), [old_secret], now: @timestamp) == :ok
    assert Verifier.verify(@body, headers(header), [new_secret], now: @timestamp) == :ok
  end
end
