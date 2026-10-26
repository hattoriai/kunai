defmodule Kunai.Page do
  @moduledoc """
  A page of a list, newest first, as Stripe's API gives them: `:data`, and
  `:has_more` when there are more after it.

  The options of every list:

    * `:limit` - how many, 1 to 100 (25).
    * `:starting_after` - the page after this id (older).
    * `:ending_before` - the page before this id (newer).
  """

  import Ecto.Query

  @type t(item) :: %__MODULE__{data: [item], has_more: boolean()}

  defstruct data: [], has_more: false

  @doc false
  def fetch(query, opts) do
    limit = opts |> Keyword.get(:limit, 25) |> max(1) |> min(100)

    {query, reverse?} =
      cond do
        cursor = opts[:starting_after] ->
          {query |> where([r], r.id < ^cursor) |> order_by([r], desc: r.id), false}

        cursor = opts[:ending_before] ->
          {query |> where([r], r.id > ^cursor) |> order_by([r], asc: r.id), true}

        true ->
          {order_by(query, [r], desc: r.id), false}
      end

    rows = query |> limit(^(limit + 1)) |> Kunai.Config.repo().all(Kunai.Config.repo_opts())
    {data, more} = Enum.split(rows, limit)
    data = if reverse?, do: Enum.reverse(data), else: data

    %__MODULE__{data: data, has_more: more != []}
  end
end
