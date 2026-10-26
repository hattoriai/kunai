defmodule Kunai.Secret do
  @moduledoc """
  An endpoint's secrets, as Standard Webhooks writes them: a prefix that
  says what each is, so a secret scanner finds one that leaked, and the
  key in base 64.

    * `whsec_…` - a shared secret, for HMAC-SHA256 (`v1`): 32 random bytes.
    * `whsk_…` and `whpk_…` - an Ed25519 key pair (`v1a`): Kunai signs with
      the private key, `whsk_`, and the receiver keeps only the public one,
      `whpk_`, which signs nothing.
  """

  @type kind :: :hmac | :ed25519

  @doc """
  A new secret. For HMAC, `{:hmac, key, "whsec_…"}`; for Ed25519,
  `{:ed25519, private_key, public_key, "whpk_…"}`, the public key the
  receiver keeps.
  """
  @spec generate(kind()) ::
          {:hmac, binary(), String.t()} | {:ed25519, binary(), binary(), String.t()}
  def generate(:hmac) do
    key = :crypto.strong_rand_bytes(32)
    {:hmac, key, encode(:hmac, key)}
  end

  def generate(:ed25519) do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    {:ed25519, private, public, encode(:public, public)}
  end

  @doc "A key as a string: `whsec_` for HMAC, `whsk_` for a private key, `whpk_` for a public one."
  @spec encode(:hmac | :private | :public, binary()) :: String.t()
  def encode(:hmac, key), do: "whsec_" <> Base.encode64(key)
  def encode(:private, key), do: "whsk_" <> Base.encode64(key)
  def encode(:public, key), do: "whpk_" <> Base.encode64(key)

  @doc "A key from its string: `{:hmac | :private | :public, key}`."
  @spec decode(String.t()) :: {:ok, {:hmac | :private | :public, binary()}} | :error
  def decode("whsec_" <> key), do: decode64(:hmac, key)
  def decode("whsk_" <> key), do: decode64(:private, key)
  def decode("whpk_" <> key), do: decode64(:public, key)
  def decode(_other), do: :error

  defp decode64(kind, key) do
    case Base.decode64(key) do
      {:ok, bytes} when byte_size(bytes) > 0 -> {:ok, {kind, bytes}}
      _error -> :error
    end
  end
end
