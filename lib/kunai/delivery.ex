defmodule Kunai.Delivery do
  @moduledoc """
  An event on its way to one endpoint: one for each pair, whatever the
  number of attempts. Its id is the `webhook-id` of every attempt, so the
  receiver knows a retry from a new event.

    * `:status` - `"pending"`, until it `"succeeded"` or `"failed"` (it gave
      up, or the endpoint was disabled).
    * `:attempts` - how many requests were made.
    * `:next_attempt_at` - when the next one is due, while pending.
    * `:last_status_code` and `:last_error` - how the last one went.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "kunai_deliveries" do
    belongs_to :event, Kunai.Event, type: :string
    belongs_to :endpoint, Kunai.Endpoint, type: :string
    field :owner, :string
    field :event_type, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :last_attempt_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :last_status_code, :integer
    field :last_error, :string

    has_many :attempt_log, Kunai.Attempt, foreign_key: :delivery_id

    timestamps()
  end
end
