defmodule Kunai.Transport.HTTP do
  @moduledoc """
  A POST to the endpoint's URL (`Kunai.Transport`), with Mint:

    * to the address `Kunai.Egress` checked, never to the name resolved
      again, with the name for TLS (SNI and the certificate's check) and
      the `Host` header;
    * no redirect followed: a 3xx is the answer;
    * `:connect` and `:total` timeouts (`Kunai.Config`'s `:timeouts`), and at
      most `:max_response_bytes` of the response read.

  Each request has its own connection: a slow endpoint holds nothing
  another endpoint needs.
  """

  @behaviour Kunai.Transport

  alias Kunai.{Config, Egress}

  @impl Kunai.Transport
  def request(url, headers, body, _opts) do
    timeouts = Config.timeouts()
    deadline = System.monotonic_time(:millisecond) + timeouts[:total]

    with {:ok, target} <- Egress.resolve(url),
         {:ok, conn} <- connect(target, timeouts[:connect]) do
      try do
        send_request(conn, target, headers, body, deadline)
      after
        Mint.HTTP.close(conn)
      end
    end
  end

  defp connect(target, timeout) do
    transport_opts =
      [timeout: timeout] ++
        if target.scheme == :https, do: [cacerts: :public_key.cacerts_get()], else: []

    case Mint.HTTP.connect(target.scheme, target.address, target.port,
           hostname: target.host,
           mode: :passive,
           protocols: [:http1],
           transport_opts: transport_opts
         ) do
      {:ok, conn} -> {:ok, conn}
      {:error, error} -> {:error, reason(error)}
    end
  end

  defp send_request(conn, target, headers, body, deadline) do
    case Mint.HTTP.request(conn, "POST", target.path, headers, body) do
      {:ok, conn, ref} ->
        receive_response(conn, ref, deadline, %{status: nil, headers: [], body: [], size: 0})

      {:error, _conn, error} ->
        {:error, reason(error)}
    end
  end

  defp receive_response(conn, ref, deadline, acc) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      case Mint.HTTP.recv(conn, 0, remaining) do
        {:ok, conn, responses} -> continue(conn, ref, deadline, collect(responses, ref, acc))
        {:error, _conn, error, _responses} -> {:error, reason(error)}
      end
    end
  end

  defp continue(_conn, _ref, _deadline, {:done, acc}), do: {:ok, finish(acc)}
  defp continue(conn, ref, deadline, {:more, acc}), do: receive_response(conn, ref, deadline, acc)
  defp continue(_conn, _ref, _deadline, {:error, error}), do: {:error, reason(error)}

  defp collect([], _ref, acc), do: {:more, acc}

  defp collect([{:status, ref, status} | rest], ref, acc),
    do: collect(rest, ref, %{acc | status: status})

  defp collect([{:headers, ref, headers} | rest], ref, acc),
    do: collect(rest, ref, %{acc | headers: acc.headers ++ headers})

  defp collect([{:data, ref, data} | rest], ref, acc) do
    max = Config.max_response_bytes()
    room = max - acc.size

    if byte_size(data) >= room do
      # Enough read: the rest of the body is not waited for.
      {:done, %{acc | body: [acc.body, binary_part(data, 0, max(room, 0))], size: max}}
    else
      collect(rest, ref, %{acc | body: [acc.body, data], size: acc.size + byte_size(data)})
    end
  end

  defp collect([{:done, ref} | _rest], ref, acc), do: {:done, acc}
  defp collect([{:error, ref, error} | _rest], ref, _acc), do: {:error, error}
  defp collect([_other | rest], ref, acc), do: collect(rest, ref, acc)

  defp finish(acc),
    do: %{status: acc.status, headers: acc.headers, body: IO.iodata_to_binary(acc.body)}

  defp reason(%Mint.TransportError{reason: reason}), do: reason
  defp reason(%Mint.HTTPError{reason: reason}), do: reason
  defp reason(other), do: other
end
