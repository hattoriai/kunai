defmodule Kunai.Transport do
  @moduledoc """
  What sends a delivery's request.

    * `Kunai.Transport.HTTP` - a POST to the endpoint's URL, the default.
    * A module of the app's, of this behaviour: a queue such as Amazon SQS,
      EventBridge or Pub/Sub, or a fake in tests.

  The response is its status, its headers and the start of its body, at
  most `:max_response_bytes`.
  """

  @type response :: %{
          status: 100..599,
          headers: [{String.t(), String.t()}],
          body: binary()
        }

  @doc "Sends the body, with the headers, to the URL."
  @callback request(
              url :: String.t(),
              headers :: [{String.t(), String.t()}],
              body :: binary(),
              opts :: keyword()
            ) ::
              {:ok, response()} | {:error, term()}
end
