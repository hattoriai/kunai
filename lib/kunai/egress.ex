defmodule Kunai.Egress do
  @moduledoc """
  Where a request may go. An endpoint's URL is written by a user of the
  app, so it could point at the app's own network: its database, a cloud's
  metadata service, an admin page on localhost. Kunai refuses those:

    * HTTPS only, unless `allow_http: true`;
    * the name is resolved, and every address it resolves to is checked:
      private, loopback, link-local, shared (CGNAT), multicast, reserved,
      documentation, IPv6 unique local, IPv4-mapped and NAT64 addresses
      are refused, unless `allow_private: true`;
    * the request goes to the address that was checked, not to the name
      again (`Kunai.Transport.HTTP`), with the name for TLS (SNI and the
      certificate's check), so a second answer of the DNS cannot change it;
    * redirects are not followed.

      config :kunai, egress: [allow_http: true, allow_private: true]

  in development, for an endpoint on localhost. The URL is checked when
  an endpoint is saved, and its addresses before each request.
  """

  @type reason ::
          :invalid_url
          | :scheme_not_allowed
          | :userinfo_not_allowed
          | :private_address
          | :unresolvable

  @type target :: %{
          scheme: :http | :https,
          host: String.t(),
          port: :inet.port_number(),
          path: String.t(),
          address: :inet.ip_address()
        }

  @doc "Checks a URL as it is written: its scheme, its parts, and its address if it is one."
  @spec check_url(String.t()) :: :ok | {:error, reason()}
  def check_url(url) when is_binary(url) do
    with {:ok, uri} <- parse(url) do
      case parse_address(uri.host) do
        {:ok, address} -> check_address(address)
        :error -> :ok
      end
    end
  end

  @doc """
  The URL's target: its parts and the address to connect to, checked.
  """
  @spec resolve(String.t()) :: {:ok, target()} | {:error, reason()}
  def resolve(url) when is_binary(url) do
    with {:ok, uri} <- parse(url),
         {:ok, addresses} <- addresses(uri.host),
         :ok <- check_all(addresses) do
      path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")

      {:ok,
       %{
         scheme: String.to_existing_atom(uri.scheme),
         host: uri.host,
         port: uri.port,
         path: path,
         address: hd(addresses)
       }}
    end
  end

  @doc "What a reason means, for a person."
  @spec describe(reason()) :: String.t()
  def describe(:invalid_url), do: "is not a valid URL"
  def describe(:scheme_not_allowed), do: "must use HTTPS"
  def describe(:userinfo_not_allowed), do: "must not contain a user name or password"
  def describe(:private_address), do: "must be on an address the internet can reach"
  def describe(:unresolvable), do: "has a name that does not resolve"

  defp parse(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host} = uri}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        check_parts(uri)

      {:ok, %URI{scheme: scheme}} when scheme not in [nil, "http", "https"] ->
        {:error, :scheme_not_allowed}

      _other ->
        {:error, :invalid_url}
    end
  end

  defp check_parts(uri) do
    cond do
      uri.scheme == "http" and not option(:allow_http) -> {:error, :scheme_not_allowed}
      uri.userinfo != nil -> {:error, :userinfo_not_allowed}
      true -> {:ok, uri}
    end
  end

  defp parse_address(host) do
    host
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.to_charlist()
    |> :inet.parse_strict_address()
    |> case do
      {:ok, address} -> {:ok, address}
      {:error, _einval} -> :error
    end
  end

  defp addresses(host) do
    case parse_address(host) do
      {:ok, address} ->
        {:ok, [address]}

      :error ->
        charlist = String.to_charlist(host)

        v4 =
          case :inet.getaddrs(charlist, :inet),
            do: (
              {:ok, list} -> list
              _error -> []
            )

        v6 =
          case :inet.getaddrs(charlist, :inet6),
            do: (
              {:ok, list} -> list
              _error -> []
            )

        case v4 ++ v6 do
          [] -> {:error, :unresolvable}
          addresses -> {:ok, addresses}
        end
    end
  end

  # Every address must pass: a name with one private address among public
  # ones is refused, not tried on its public one.
  defp check_all(addresses) do
    Enum.reduce_while(addresses, :ok, fn address, :ok ->
      case check_address(address) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_address(address) do
    if option(:allow_private) or not blocked?(address),
      do: :ok,
      else: {:error, :private_address}
  end

  @blocked_v4 [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 88, 99, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @blocked_v6 [
    # unspecified and loopback
    {{0, 0, 0, 0, 0, 0, 0, 0}, 127},
    # IPv4-mapped and IPv4-translated
    {{0, 0, 0, 0, 0, 0xFFFF, 0, 0}, 96},
    {{0, 0, 0, 0, 0xFFFF, 0, 0, 0}, 96},
    # NAT64
    {{0x64, 0xFF9B, 0, 0, 0, 0, 0, 0}, 96},
    {{0x64, 0xFF9B, 1, 0, 0, 0, 0, 0}, 48},
    # discard, documentation, 6to4 and Teredo (which embed IPv4 addresses)
    {{0x100, 0, 0, 0, 0, 0, 0, 0}, 64},
    {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16},
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 32},
    # unique local, link-local, site-local and multicast
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFEC0, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @doc "Whether requests to this address are refused (unless `allow_private: true`)."
  @spec blocked?(:inet.ip_address()) :: boolean()
  def blocked?({_, _, _, _} = address), do: Enum.any?(@blocked_v4, &within?(address, &1))

  def blocked?({_, _, _, _, _, _, _, _} = address),
    do: Enum.any?(@blocked_v6, &within?(address, &1))

  defp within?(address, {base, bits}), do: prefix(address, bits) == prefix(base, bits)

  defp prefix(address, bits) do
    size = if tuple_size(address) == 4, do: 8, else: 16
    binary = address |> Tuple.to_list() |> Enum.map_join(&<<&1::size(size)>>)
    <<head::bitstring-size(^bits), _rest::bitstring>> = binary
    head
  end

  defp option(key), do: Keyword.get(Kunai.Config.egress(), key, false)
end
