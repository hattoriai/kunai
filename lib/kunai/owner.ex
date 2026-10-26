defmodule Kunai.Owner do
  @moduledoc false
  # Whose a scope is, and who acts in it, from the catalog. A string is an
  # owner already, and nil is the app's own: for code with no scope.

  require Ecto.Query

  alias Kunai.Config

  @system %{"type" => "system"}

  def of(scope) when is_binary(scope) or is_nil(scope), do: scope
  def of(scope), do: Config.catalog().owner(scope)

  def actor(scope) when is_binary(scope) or is_nil(scope), do: @system

  def actor(scope) do
    case Config.catalog().actor(scope) do
      nil -> @system
      actor -> stringify(actor)
    end
  end

  def stringify(map) when is_map(map),
    do: map |> Config.serializer().encode!() |> Config.serializer().decode!()

  # Queries of an owner's rows: nil is matched as nil.
  def where(query, nil), do: Ecto.Query.where(query, [row], is_nil(row.owner))
  def where(query, owner), do: Ecto.Query.where(query, [row], row.owner == ^owner)
end
