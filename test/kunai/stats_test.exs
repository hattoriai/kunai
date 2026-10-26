defmodule Kunai.StatsTest do
  use KunaiTest.DataCase

  import Ecto.Query

  alias Kunai.{Delivery, Stats}

  # The fanout's jobs only: deliveries made, none tried.
  defp fan_out, do: Oban.drain_queue(Kunai.Config.oban(), queue: :kunai, with_recursion: false)

  defp set(id, changes),
    do: Kunai.Config.repo().update_all(from(d in Delivery, where: d.id == ^id), set: changes)

  test "deliveries by state and hour; one retrying counts against the rate until it succeeds" do
    {endpoint, _} = endpoint!()
    for n <- 1..4, do: emit!("page.published", %{id: "page_#{n}"})
    fan_out()
    [a, b, c, _d] = Kunai.list_deliveries(scope()).data |> Enum.map(& &1.id)

    set(a, status: "succeeded", attempts: 1)
    set(b, status: "failed", attempts: 9)
    set(c, attempts: 1)

    summary = Stats.summary(scope())
    assert %{total: 4, succeeded: 1, failed: 1, retrying: 1, pending: 1} = summary
    assert_in_delta summary.success_rate, 1 / 3, 0.001
    assert length(summary.hours) == 24
    assert %{succeeded: 1, failed: 1, retrying: 1, pending: 1} = List.last(summary.hours)

    assert %{total: 4, retrying: 1} = Stats.summary(scope(), endpoint_id: endpoint.id)
    assert %{total: 4, retrying: 1} = Stats.by_endpoint(scope())[endpoint.id]
  end

  test "an owner sees only its own; none tried has no rate" do
    endpoint!()
    emit!("page.published", %{id: "page_1"})
    fan_out()

    assert %{total: 1, pending: 1, success_rate: nil} = Stats.summary(scope())
    assert %{total: 0} = Stats.summary(scope("2"))
    assert Stats.by_endpoint(scope("2")) == %{}
  end
end
