defmodule Kunai.Event do
  @moduledoc """
  Something that happened, kept once, whatever endpoints receive it.

    * `:type` - its name in the catalog (`Kunai.Catalog`).
    * `:data` - the object as it was then, redacted (`c:Kunai.Catalog.redact/2`).
    * `:previous` - the fields that changed, as they were before.
    * `:object_id` - the object's `"id"`, for thin payloads.
    * `:actor` - who made the change: a person, an agent, a bot or the
      system.
    * `:owner` - whose it is: the endpoints of that owner receive it.
    * `:api_version` - the version its data is in (`Kunai.Versions`).
    * `:test` - made by `Kunai.send_test/2`, for one endpoint.

  Events are kept apart from their deliveries, so an app's users list and
  get them through the API, and one whose endpoint missed some catches up.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "kunai_events" do
    field :type, :string
    field :owner, :string
    field :data, :map, default: %{}
    field :previous, :map
    field :object_id, :string
    field :actor, :map
    field :api_version, :string
    field :test, :boolean, default: false
    field :created_at, :utc_datetime_usec
  end
end
