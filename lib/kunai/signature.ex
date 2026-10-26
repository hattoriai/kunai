defmodule Kunai.Signature do
  @moduledoc """
  The signature of a request, as [Standard Webhooks](https://www.standardwebhooks.com)
  defines it, so the receivers' libraries in every language check it:

      webhook-id: msg_06fh2k4w1xg9h3z5c8m2q7v0rs
      webhook-timestamp: 1793001600
      webhook-signature: v1,K5oZfzN95Z9UVu1EsfQmfVNQhnkZ2pj9o9NDN/H/pI4= v1a,…

  What is signed is `id.timestamp.body`, the body the bytes that are sent.
  Each secret that signs (`Kunai.EndpointSecret`) adds one signature, so
  during a rotation both the old and the new pass.
  """

  @doc "The content signed: `id.timestamp.body`."
  @spec content(String.t(), integer(), iodata()) :: iodata()
  def content(id, timestamp, body), do: [id, ?., Integer.to_string(timestamp), ?., body]

  @doc """
  The `webhook-signature` header for these keys: `{:hmac, key}` and
  `{:ed25519, private_key}`.
  """
  @spec header([{:hmac | :ed25519, binary()}], String.t(), integer(), iodata()) :: String.t()
  def header(keys, id, timestamp, body) do
    content = content(id, timestamp, body)
    Enum.map_join(keys, " ", &sign(&1, content))
  end

  @doc "One signature: `v1,…` or `v1a,…`."
  @spec sign({:hmac | :ed25519, binary()}, iodata()) :: String.t()
  def sign({:hmac, key}, content),
    do: "v1," <> Base.encode64(:crypto.mac(:hmac, :sha256, key, content))

  def sign({:ed25519, private}, content),
    do: "v1a," <> Base.encode64(:crypto.sign(:eddsa, :none, content, [private, :ed25519]))
end
