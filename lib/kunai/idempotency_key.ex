defmodule Kunai.IdempotencyKey do
  @moduledoc """
  A request of the API sent with an `Idempotency-Key`, and its response,
  kept a day (`Kunai.API.Idempotency`).
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "kunai_idempotency_keys" do
    field :owner, :string
    field :key, :string
    field :fingerprint, :string
    field :status, :integer
    field :response, :string
    field :created_at, :utc_datetime_usec
  end
end
