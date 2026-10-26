defmodule Kunai.MigrationsTest do
  # Migrates a schema, or a database, of its own, out of the sandbox.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixMountable.Migrations.Test, as: Suite

  test "up, down and up again, upgrades, and what a host adds is kept" do
    repo = Kunai.Config.repo()

    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        Sandbox.unboxed_run(repo, fn ->
          Suite.run_suite(repo, Kunai.Migrations, prefix: "kunai_migrations")
        end)

      Ecto.Adapters.SQLite3 ->
        path = Path.expand("../../tmp/kunai_migrations.db", __DIR__)
        File.rm(path)

        {:ok, _pid} =
          KunaiTest.SQLiteMigrationsRepo.start_link(database: path, pool_size: 1, log: false)

        Suite.run_suite(KunaiTest.SQLiteMigrationsRepo, Kunai.Migrations)
    end
  end
end
