defmodule KunaiTest.Repo do
  @moduledoc "The repo of the tests on PostgreSQL (DATABASE_URL)."
  use Ecto.Repo, otp_app: :kunai, adapter: Ecto.Adapters.Postgres
end

defmodule KunaiTest.SQLiteRepo do
  @moduledoc "The repo of the tests on SQLite (KUNAI_DB=sqlite)."
  use Ecto.Repo, otp_app: :kunai, adapter: Ecto.Adapters.SQLite3
end

defmodule KunaiTest.SQLiteMigrationsRepo do
  @moduledoc "A SQLite database of its own, for the migrations' suite."
  use Ecto.Repo, otp_app: :kunai, adapter: Ecto.Adapters.SQLite3
end
