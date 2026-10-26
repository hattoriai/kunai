defmodule Kunai.Serializer do
  @moduledoc """
  How a payload becomes the body of a request. The body is encoded once
  per attempt, signed, and sent as those bytes.

    * `Kunai.Serializer.JSON` - Elixir's own `JSON`, the default.
    * A module of the app's, of this behaviour (Jason, say).
  """

  @doc "The body of a payload."
  @callback encode!(term()) :: binary()

  @doc "A term from JSON."
  @callback decode!(binary()) :: term()
end

defmodule Kunai.Serializer.JSON do
  @moduledoc "JSON with Elixir's own `JSON` module (`Kunai.Serializer`)."

  @behaviour Kunai.Serializer

  @impl Kunai.Serializer
  def encode!(term), do: JSON.encode!(term)

  @impl Kunai.Serializer
  def decode!(binary), do: JSON.decode!(binary)
end
