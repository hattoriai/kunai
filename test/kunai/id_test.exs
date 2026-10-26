defmodule Kunai.IDTest do
  use ExUnit.Case, async: true

  test "a prefix and 26 characters of Crockford's base 32" do
    id = Kunai.ID.generate("evt")
    assert id =~ ~r/\Aevt_[0-9a-hjkmnp-tv-z]{26}\z/
    assert Kunai.ID.prefix(id) == "evt"
  end

  test "an id made later sorts after" do
    first = Kunai.ID.generate("evt")
    Process.sleep(2)
    second = Kunai.ID.generate("evt")
    assert first < second
  end

  test "the floor of a time sorts before the ids made at it, after those made before" do
    before = Kunai.ID.generate("msg")
    Process.sleep(2)
    floor = Kunai.ID.floor("msg", DateTime.utc_now())
    after_it = Kunai.ID.generate("msg")
    assert before < floor and floor <= after_it
  end
end
