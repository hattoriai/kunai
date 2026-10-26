defmodule Kunai.Notifier do
  @moduledoc """
  Who is told when an endpoint keeps failing, and when it is disabled, so
  its owner fixes it: by email, in the app, in a chat.

    * `Kunai.Notifier.Logger` - in the log, the default.
    * A module of the app's, of this behaviour.

  `reason` says why it was disabled: `"gone"` (it answered 410) or
  `"failing"` (it failed for `:disable_after`).
  """

  alias Kunai.Endpoint

  @doc "The endpoint has failed every attempt since this time, and will be disabled if it goes on."
  @callback failing(Endpoint.t(), since :: DateTime.t(), opts :: keyword()) :: :ok

  @doc "The endpoint was disabled, for this reason."
  @callback disabled(Endpoint.t(), reason :: String.t(), opts :: keyword()) :: :ok

  @doc false
  def notify(fun, args) do
    {notifier, opts} = Kunai.Config.notifier()
    apply(notifier, fun, args ++ [opts])
  end
end

defmodule Kunai.Notifier.Logger do
  @moduledoc "Endpoints failing and disabled, told in the log (`Kunai.Notifier`)."

  @behaviour Kunai.Notifier

  require Logger

  @impl Kunai.Notifier
  def failing(endpoint, since, _opts) do
    Logger.warning(
      "Kunai: the endpoint #{endpoint.id} (#{endpoint.url}) has failed since #{since}"
    )
  end

  @impl Kunai.Notifier
  def disabled(endpoint, reason, _opts) do
    Logger.warning("Kunai: the endpoint #{endpoint.id} (#{endpoint.url}) was disabled: #{reason}")
  end
end
