defmodule Kunai.Migrations do
  @moduledoc """
  Kunai's tables, in a migration of the app.

      $ mix kunai.gen.migration

  writes a migration that pins the latest version:

      defmodule MyApp.Repo.Migrations.AddKunai do
        use Ecto.Migration

        def up, do: Kunai.Migrations.up(version: 2)
        def down, do: Kunai.Migrations.down(to: 0)
      end

  The versions are `PhoenixMountable.Migrations`: tracked in the app's
  database (per prefix), and run on PostgreSQL and on SQLite. A later
  version of Kunai that changes the tables has a new version, and
  `mix kunai.gen.migration` writes the migration that upgrades.

  Version 1 makes the endpoints (`kunai_endpoints`) and their secrets
  (`kunai_endpoint_secrets`), the events (`kunai_events`), their
  deliveries (`kunai_deliveries`) and attempts (`kunai_attempts`), and the
  audit log (`kunai_audit_log`). The ids are Kunai's own (`Kunai.ID`),
  strings, whatever keys the app uses.

  Version 2 makes the API's idempotency keys (`kunai_idempotency_keys`).

  `up/1` takes `:version` and `:prefix` (the schema of the tables, in
  PostgreSQL); `down/1` takes `:to` and `:prefix`.
  """

  use PhoenixMountable.Migrations,
    otp_app: :kunai,
    versions: [Kunai.Migrations.V1, Kunai.Migrations.V2],
    compatible_with: 1,
    gen_task: "kunai.gen.migration"
end
