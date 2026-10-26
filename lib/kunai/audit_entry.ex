defmodule Kunai.AuditEntry do
  @moduledoc """
  A change to an endpoint or its secrets, and who made it: `"created"`,
  `"updated"`, `"deleted"`, `"enabled"`, `"disabled"`, `"secret_rolled"`.
  Kept after the endpoint is deleted.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "kunai_audit_log" do
    field :owner, :string
    field :endpoint_id, :string
    field :action, :string
    field :actor, :map
    field :changes, :map, default: %{}
    field :created_at, :utc_datetime_usec
  end
end
