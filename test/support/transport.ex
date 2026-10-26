defmodule KunaiTest.Transport do
  @moduledoc """
  A transport of the tests: each request is sent to the test's process,
  and answered with what the test said for its URL (`respond/2`), else 200.
  The jobs run in the test's process (`Oban.drain_queue/2`).
  """

  @behaviour Kunai.Transport

  @doc "The answers for a URL, in turn: the last one is repeated."
  def respond(url, responses), do: Process.put({__MODULE__, url}, List.wrap(responses))

  @impl Kunai.Transport
  def request(url, headers, body, _opts) do
    send(self(), {:request, url, Map.new(headers), body})

    case Process.get({__MODULE__, url}, []) do
      [] -> {:ok, response(200)}
      [last] -> answer(last)
      [next | rest] -> Process.put({__MODULE__, url}, rest) && answer(next)
    end
  end

  defp answer({:error, reason}), do: {:error, reason}
  defp answer({status, headers}), do: {:ok, %{response(status) | headers: headers}}
  defp answer(status) when is_integer(status), do: {:ok, response(status)}

  defp response(status), do: %{status: status, headers: [], body: "ok"}
end

defmodule KunaiTest.ReversingVault do
  @moduledoc "A vault of the tests: its ciphertext is the secret reversed."
  @behaviour Kunai.Vault

  @impl Kunai.Vault
  def encrypt(plaintext, _opts), do: String.reverse(plaintext)

  @impl Kunai.Vault
  def decrypt(ciphertext, _opts), do: String.reverse(ciphertext)
end
