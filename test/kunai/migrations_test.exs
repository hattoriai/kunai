defmodule Kunai.MigrationsTest do
  # Migrates a schema, or a database, of its own, out of the sandbox.
  use ExUnit.Case, async: false

  alias PhoenixMountable.Migrations.Test, as: Suite

  test "up, down and up again, upgrades, and what a host adds is kept" do
    repo = Kunai.Config.repo()

    case repo.__adapter__() do
      Ecto.Adapters.Postgres ->
        # A pool of its own: the sandbox's connection, shared, can be
        # busy with what an earlier test left running.
        config = Keyword.drop(repo.config(), [:pool, :otp_app])

        {:ok, _pid} = KunaiTest.MigrationsRepo.start_link(Keyword.put(config, :pool_size, 2))

        Suite.run_suite(KunaiTest.MigrationsRepo, Kunai.Migrations, prefix: "kunai_migrations")

      Ecto.Adapters.SQLite3 ->
        path = Path.expand("../../tmp/kunai_migrations.db", __DIR__)
        File.rm(path)

        {:ok, _pid} =
          KunaiTest.SQLiteMigrationsRepo.start_link(database: path, pool_size: 1, log: false)

        Suite.run_suite(KunaiTest.SQLiteMigrationsRepo, Kunai.Migrations)
    end
  end
end
