import Config

if config_env() == :test do
  config :logger, level: :warning

  # PostgreSQL by default (DATABASE_URL), SQLite with KUNAI_DB=sqlite.
  sqlite? = System.get_env("KUNAI_DB") == "sqlite"

  config :kunai,
    repo: if(sqlite?, do: KunaiTest.SQLiteRepo, else: KunaiTest.Repo),
    catalog: KunaiTest.Webhooks,
    vault: Kunai.Vault.Unencrypted,
    transport: KunaiTest.Transport,
    retry_policy: {Kunai.RetryPolicy.Default, jitter: 0},
    # Its own test: draining every job at once would meet it at each turn.
    circuit_breaker: false,
    egress: [allow_http: true, allow_private: true]

  config :kunai, KunaiTest.Repo,
    url: System.get_env("DATABASE_URL", "postgres://postgres:postgres@localhost/kunai_test"),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10,
    log: false

  config :kunai, KunaiTest.SQLiteRepo,
    database: Path.expand("../tmp/kunai_test.db", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5,
    log: false
end
