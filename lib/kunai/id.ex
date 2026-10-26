defmodule Kunai.ID do
  @moduledoc """
  Kunai's ids: a prefix that says what the id is, and 26 characters that
  sort as they were made.

      Kunai.ID.generate("evt")
      #=> "evt_06fh2k4w1xg9h3z5c8m2q7v0rs"

  The 26 characters are 128 bits in Crockford's base 32, lowercase: 48
  bits of milliseconds, 16 of a counter of the node, then 64 random. An id
  made later sorts after, on the same node even within a millisecond, so
  a list ordered by id is ordered by time, and a page starts after an id
  (`starting_after`).

  | Prefix | What |
  | --- | --- |
  | `ep` | an endpoint (`Kunai.Endpoint`) |
  | `evt` | an event (`Kunai.Event`) |
  | `msg` | a delivery (`Kunai.Delivery`), its `webhook-id` |
  | `att` | an attempt (`Kunai.Attempt`) |
  | `sec` | a secret of an endpoint (`Kunai.EndpointSecret`) |
  | `aud` | a line of the audit log (`Kunai.AuditEntry`) |
  """

  @alphabet ~c"0123456789abcdefghjkmnpqrstvwxyz"

  @doc "A new id with this prefix."
  @spec generate(String.t()) :: String.t()
  def generate(prefix) when is_binary(prefix) do
    ms = System.system_time(:millisecond)
    sequence = :atomics.add_get(counter(), 1, 1)
    <<random::64>> = :crypto.strong_rand_bytes(8)
    prefix <> "_" <> encode(<<ms::48, sequence::16, random::64>>)
  end

  defp counter do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        ref = :atomics.new(1, signed: false)
        :persistent_term.put(__MODULE__, ref)
        ref

      ref ->
        ref
    end
  end

  @doc """
  The smallest id of this prefix made at this time: ids made at or after
  it sort after it. For a range of time, as a bound.
  """
  @spec floor(String.t(), DateTime.t()) :: String.t()
  def floor(prefix, %DateTime{} = at) do
    prefix <> "_" <> encode(<<DateTime.to_unix(at, :millisecond)::48, 0::80>>)
  end

  @doc "The prefix of an id, or nil."
  @spec prefix(String.t()) :: String.t() | nil
  def prefix(id) when is_binary(id) do
    case String.split(id, "_", parts: 2) do
      [prefix, _rest] -> prefix
      _other -> nil
    end
  end

  # 128 bits are 26 characters of 5 bits, the first of 3.
  defp encode(<<bits::128>>), do: encode(<<0::2, bits::128>>, [])

  defp encode(<<>>, acc), do: acc |> Enum.reverse() |> List.to_string()
  defp encode(<<c::5, rest::bitstring>>, acc), do: encode(rest, [Enum.at(@alphabet, c) | acc])
end
