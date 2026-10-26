defmodule Kunai.CircuitBreakerTest do
  # Changes Kunai's options for the test.
  use ExUnit.Case, async: false

  alias Kunai.CircuitBreaker

  setup do
    Application.put_env(:kunai, :circuit_breaker, threshold: 3, pause: 1_000)
    on_exit(fn -> Application.put_env(:kunai, :circuit_breaker, false) end)
    %{id: "ep_" <> Integer.to_string(System.unique_integer([:positive]))}
  end

  test "opens after the threshold of failures in a row, and a success closes it", %{id: id} do
    CircuitBreaker.record(id, :error)
    CircuitBreaker.record(id, :error)
    assert CircuitBreaker.check(id) == :closed

    CircuitBreaker.record(id, :error)
    assert {:open, ms} = CircuitBreaker.check(id)
    assert ms in 900..1_000

    CircuitBreaker.record(id, :error)
    assert {:open, ms} = CircuitBreaker.check(id)
    assert ms in 1_900..2_000

    CircuitBreaker.record(id, :ok)
    assert CircuitBreaker.check(id) == :closed
  end

  test "off", %{id: id} do
    Application.put_env(:kunai, :circuit_breaker, false)
    for _ <- 1..10, do: CircuitBreaker.record(id, :error)
    assert CircuitBreaker.check(id) == :closed
  end
end
