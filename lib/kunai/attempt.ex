defmodule Kunai.Attempt do
  @moduledoc """
  One request of a delivery: its number, the response's status and the
  start of its body, how long it took, or the error that stopped it.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "kunai_attempts" do
    belongs_to :delivery, Kunai.Delivery, type: :string
    field :endpoint_id, :string
    field :number, :integer
    field :status_code, :integer
    field :duration_ms, :integer
    field :response_body, :string
    field :error, :string
    field :created_at, :utc_datetime_usec
  end
end
