defmodule Kunai.Telemetry do
  @moduledoc """
  Kunai's `:telemetry` events. Each is a span: `:start`, then `:stop` (or
  `:exception`), with `:duration` in the measurements of the last.

    * `[:kunai, :emit, _]` - an event added to a transaction, with `:type`
      and `:owner`.
    * `[:kunai, :fanout, _]` - an event given its deliveries, with
      `:event_id` and `:type`; the `:stop` has `:deliveries`, how many.
    * `[:kunai, :attempt, _]` - a request to an endpoint, with
      `:delivery_id`, `:endpoint_id`, `:event_type` and `:attempt`; the
      `:stop` has `:result`: `:succeeded`, `:retry`, `:failed` or `:gone`,
      and `:status_code`.
    * `[:kunai, :disable, _]` - an endpoint disabled, with `:endpoint_id`
      and `:reason`.
  """

  @doc false
  def span(name, metadata, fun), do: :telemetry.span([:kunai, name], metadata, fun)
end
