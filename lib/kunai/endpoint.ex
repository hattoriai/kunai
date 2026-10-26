defmodule Kunai.Endpoint do
  @moduledoc """
  Where an owner's events go: a URL, the events it subscribes to, and how
  it receives them.

    * `:url` - HTTPS, on an address the internet reaches (`Kunai.Egress`).
    * `:events` - the names it subscribes to: `"page.published"`, a family
      such as `"page.*"`, or `"*"` for every event.
    * `:scopes` - what it may see (`Kunai.Authorizer.Scopes`): an event
      reaches it only when it has the event's scopes.
    * `:status` - `"enabled"` or `"disabled"`, with `:disabled_reason`:
      `"manual"`, `"gone"` (it answered 410) or `"failing"` (it failed for
      `:disable_after`).
    * `:payload` - `"full"`, the event's object, or `"thin"`, its id only.
    * `:ordered` - deliveries one at a time, in the order of their
      events. Off by default: events arrive in any order.
    * `:api_version` - the version of the payloads it gets (`Kunai.Versions`).
    * `:owner` - whose it is (`c:Kunai.Catalog.owner/1`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "kunai_endpoints" do
    field :owner, :string
    field :url, :string
    field :description, :string
    field :events, {:array, :string}, default: []
    field :scopes, {:array, :string}, default: []
    field :status, :string, default: "enabled"
    field :disabled_reason, :string
    field :payload, :string, default: "full"
    field :ordered, :boolean, default: false
    field :api_version, :string
    field :metadata, :map, default: %{}
    field :failing_since, :utc_datetime_usec
    field :warned_at, :utc_datetime_usec

    has_many :secrets, Kunai.EndpointSecret

    timestamps()
  end

  @fields [:url, :description, :events, :scopes, :payload, :ordered, :api_version, :metadata]

  @doc false
  def create_changeset(attrs, owner) do
    %__MODULE__{id: Kunai.ID.generate("ep"), owner: owner}
    |> changeset(attrs)
    |> put_default_version()
  end

  @doc false
  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, @fields)
    |> validate_required([:url, :events])
    |> validate_length(:url, max: 2048)
    |> validate_length(:description, max: 500)
    |> validate_change(:url, fn :url, url ->
      case Kunai.Egress.check_url(url) do
        :ok -> []
        {:error, reason} -> [url: {Kunai.Egress.describe(reason), reason: reason}]
      end
    end)
    |> validate_events_present()
    |> validate_change(:events, fn :events, patterns ->
      case Kunai.Subscriptions.unknown(patterns) do
        [] -> []
        unknown -> [events: {"has unknown events: %{unknown}", unknown: Enum.join(unknown, ", ")}]
      end
    end)
    |> validate_inclusion(:payload, ["full", "thin"])
    |> validate_change(:api_version, fn :api_version, version ->
      if version in Kunai.Config.catalog().versions(),
        do: [],
        else: [api_version: "is not a version"]
    end)
    |> validate_change(:metadata, fn :metadata, metadata ->
      if map_size(metadata) <= 50, do: [], else: [metadata: "has more than 50 keys"]
    end)
  end

  # Required whether given or not: an endpoint with no events receives none.
  defp validate_events_present(changeset) do
    if get_field(changeset, :events) in [nil, []],
      do: add_error(changeset, :events, "must have at least one event"),
      else: changeset
  end

  defp put_default_version(changeset) do
    if get_field(changeset, :api_version),
      do: changeset,
      else: put_change(changeset, :api_version, Kunai.Config.catalog().latest_version())
  end

  @doc "Whether it is enabled."
  @spec enabled?(t()) :: boolean()
  def enabled?(%__MODULE__{status: status}), do: status == "enabled"
end
