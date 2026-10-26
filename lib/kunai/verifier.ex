defmodule Kunai.Verifier do
  @moduledoc """
  Checks a webhook on the side that receives it: an app of yours, or of
  your users', that receives Kunai's requests, or any sender's of Standard
  Webhooks.

      :ok = Kunai.Verifier.verify(raw_body, headers, ["whsec_…"])

  The signatures are compared in constant time, and the timestamp must be
  within five minutes of now (`:tolerance`, in seconds), so a request
  captured cannot be replayed later. `secrets` is a list, for the time a
  secret rolls: `whsec_…` for HMAC, `whpk_…` for Ed25519. In a Phoenix
  app, `Kunai.Plug.Verify` does it for a route.
  """

  alias Kunai.{Secret, Signature}

  @type error ::
          :missing_headers
          | :invalid_timestamp
          | :timestamp_too_old
          | :timestamp_too_new
          | :no_secret
          | :invalid_signature

  @doc """
  Checks a body, as it was received, against its headers (a map or a list
  of pairs, names in lowercase) and the endpoint's secrets.
  """
  @spec verify(binary(), map() | [{String.t(), String.t()}], [String.t()], keyword()) ::
          :ok | {:error, error()}
  def verify(body, headers, secrets, opts \\ []) when is_binary(body) do
    tolerance = Keyword.get(opts, :tolerance, 300)
    now = Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end)
    headers = Map.new(headers, fn {name, value} -> {String.downcase(name), value} end)

    with {:ok, id, timestamp, signatures} <- read(headers),
         :ok <- check_time(timestamp, now, tolerance),
         {:ok, keys} <- keys(secrets) do
      content = IO.iodata_to_binary(Signature.content(id, timestamp, body))

      if Enum.any?(signatures, &matches?(&1, keys, content)),
        do: :ok,
        else: {:error, :invalid_signature}
    end
  end

  defp read(%{
         "webhook-id" => id,
         "webhook-timestamp" => timestamp,
         "webhook-signature" => header
       }) do
    case Integer.parse(timestamp) do
      {seconds, ""} -> {:ok, id, seconds, String.split(header, " ", trim: true)}
      _invalid -> {:error, :invalid_timestamp}
    end
  end

  defp read(_headers), do: {:error, :missing_headers}

  defp check_time(timestamp, now, tolerance) do
    cond do
      timestamp < now - tolerance -> {:error, :timestamp_too_old}
      timestamp > now + tolerance -> {:error, :timestamp_too_new}
      true -> :ok
    end
  end

  defp keys(secrets) do
    case Enum.flat_map(secrets, &key/1) do
      [] -> {:error, :no_secret}
      keys -> {:ok, keys}
    end
  end

  defp key(secret) do
    case Secret.decode(secret) do
      {:ok, {:hmac, key}} -> [{"v1", key}]
      {:ok, {:public, key}} -> [{"v1a", key}]
      _other -> []
    end
  end

  defp matches?(signature, keys, content) do
    case String.split(signature, ",", parts: 2) do
      [version, encoded] ->
        case Base.decode64(encoded) do
          {:ok, given} -> Enum.any?(keys, &valid?(&1, version, given, content))
          :error -> false
        end

      _other ->
        false
    end
  end

  defp valid?({"v1", key}, "v1", given, content) do
    expected = :crypto.mac(:hmac, :sha256, key, content)
    byte_size(given) == byte_size(expected) and :crypto.hash_equals(expected, given)
  end

  defp valid?({"v1a", public}, "v1a", given, content),
    do: :crypto.verify(:eddsa, :none, content, given, [public, :ed25519])

  defp valid?(_key, _version, _given, _content), do: false
end
