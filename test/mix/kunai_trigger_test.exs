defmodule Mix.Tasks.Kunai.TriggerTest do
  use KunaiTest.DataCase

  alias Mix.Tasks.Kunai.Trigger

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp output do
    receive do
      {:mix_shell, :info, [text]} -> text <> output()
    after
      0 -> ""
    end
  end

  test "the example, with the data given, to the owner's endpoints, each shown as it goes" do
    {endpoint, _secret} = endpoint!(%{events: ["page.*"]})
    endpoint!(%{events: ["member.invited"], url: "https://hooks.example.com/members"})

    # The app's Oban runs the jobs, as its server would.
    test = self()

    runner =
      Task.async(fn ->
        Process.sleep(150)
        drain()
        send(test, :drained)
      end)

    Trigger.run(["page.published", "--data", ~s({"title": "Porto trip"}), "--wait", "5"])
    Task.await(runner)

    printed = output()
    assert printed =~ ~r/page.published evt_\w+, for site:1/
    assert printed =~ "→ #{endpoint.url}  200, delivered"
    refute printed =~ "/members"

    [event] = Kunai.list_events(scope()).data
    assert event.data["title"] == "Porto trip"
    assert event.actor == %{"type" => "system", "id" => "mix kunai.trigger"}
  end

  test "deliveries not tried in time are said so" do
    endpoint!()
    Trigger.run(~w(page.published --wait 0))
    assert output() =~ "1 not tried yet: is the app's Oban running the kunai queue?"
  end

  test "a dry run prints the requests, signed, and stores nothing" do
    {endpoint, _secret} = endpoint!()
    Trigger.run(~w(page.published --dry-run))

    printed = output()
    assert printed =~ "a dry run, nothing stored or sent"
    assert printed =~ "POST #{endpoint.url}"
    assert printed =~ ~r/webhook-signature: v1,\S+/
    assert printed =~ "curl -X POST '#{endpoint.url}'"
    assert Kunai.list_events(scope()).data == []
  end

  test "an event the catalog does not have, or no endpoint, or several owners'" do
    assert_raise Mix.Error,
                 ~r/page.renamed is not in the catalog: member.invited, page.deleted, page.published/,
                 fn ->
                   Trigger.run(~w(page.renamed))
                 end

    assert_raise Mix.Error, ~r/No endpoint receives page.published/, fn ->
      Trigger.run(~w(page.published))
    end

    endpoint!()
    endpoint!(%{}, scope: scope("2"))

    assert_raise Mix.Error, ~r/several owners .* pass --owner, one of site:1, site:2/, fn ->
      Trigger.run(~w(page.published))
    end

    Trigger.run(~w(page.published --owner site:2 --wait 0))
    assert output() =~ "for site:2"
  end
end
