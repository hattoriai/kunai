# The tests run against PostgreSQL (DATABASE_URL, a local one by default)
# or SQLite (KUNAI_DB=sqlite), as CI does both.
repo = Kunai.Config.repo()

case repo.__adapter__() do
  Ecto.Adapters.Postgres -> _ = Ecto.Adapters.Postgres.storage_up(repo.config())
  Ecto.Adapters.SQLite3 -> File.mkdir_p!("tmp") && File.rm("tmp/kunai_test.db")
end

{:ok, _pid} = repo.start_link()

defmodule KunaiTest.Migration do
  use Ecto.Migration

  def up do
    Oban.Migration.up()
    Kunai.Migrations.up(version: 1)
  end

  def down do
    Kunai.Migrations.down(to: 0)
    Oban.Migration.down()
  end
end

Ecto.Migrator.up(repo, 1, KunaiTest.Migration, log: false)

engine =
  if repo.__adapter__() == Ecto.Adapters.SQLite3, do: Oban.Engines.Lite, else: Oban.Engines.Basic

{:ok, _oban} = Oban.start_link(repo: repo, engine: engine, testing: :manual, queues: [kunai: 10])

ExUnit.start()
