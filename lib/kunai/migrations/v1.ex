defmodule Kunai.Migrations.V1 do
  @moduledoc false
  # The endpoints and their secrets, the events, their deliveries and
  # attempts, and the audit log.

  use PhoenixMountable.Migration, description: "Kunai's tables"

  def up(ctx) do
    create table(:kunai_endpoints, primary_key: false, prefix: ctx.prefix) do
      add :id, :string, size: 40, primary_key: true
      add :owner, :string, size: 255
      add :url, :string, size: 2048, null: false
      add :description, :string, size: 500
      add :events, {:array, :string}, null: false, default: []
      add :scopes, {:array, :string}, null: false, default: []
      add :status, :string, size: 16, null: false, default: "enabled"
      add :disabled_reason, :string, size: 32
      add :payload, :string, size: 8, null: false, default: "full"
      add :ordered, :boolean, null: false, default: false
      add :api_version, :string, size: 32
      add :metadata, :map, null: false, default: %{}
      add :failing_since, :utc_datetime_usec
      add :warned_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:kunai_endpoints, [:owner, :status], prefix: ctx.prefix)

    create table(:kunai_endpoint_secrets, primary_key: false, prefix: ctx.prefix) do
      add :id, :string, size: 40, primary_key: true

      add :endpoint_id,
          references(:kunai_endpoints, type: :string, on_delete: :delete_all, prefix: ctx.prefix),
          null: false

      add :kind, :string, size: 16, null: false, default: "hmac"
      add :ciphertext, :binary, null: false
      add :public_key, :binary
      add :expires_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:kunai_endpoint_secrets, [:endpoint_id], prefix: ctx.prefix)

    create table(:kunai_events, primary_key: false, prefix: ctx.prefix) do
      add :id, :string, size: 40, primary_key: true
      add :type, :string, size: 255, null: false
      add :owner, :string, size: 255
      add :data, :map, null: false, default: %{}
      add :previous, :map
      add :object_id, :string, size: 255
      add :actor, :map
      add :api_version, :string, size: 32
      add :test, :boolean, null: false, default: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:kunai_events, [:owner, :id], prefix: ctx.prefix)
    create index(:kunai_events, [:owner, :type, :id], prefix: ctx.prefix)
    create index(:kunai_events, [:created_at], prefix: ctx.prefix)

    create table(:kunai_deliveries, primary_key: false, prefix: ctx.prefix) do
      add :id, :string, size: 40, primary_key: true

      add :event_id,
          references(:kunai_events, type: :string, on_delete: :delete_all, prefix: ctx.prefix),
          null: false

      add :endpoint_id,
          references(:kunai_endpoints, type: :string, on_delete: :delete_all, prefix: ctx.prefix),
          null: false

      add :owner, :string, size: 255
      add :event_type, :string, size: 255, null: false
      add :status, :string, size: 16, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :next_attempt_at, :utc_datetime_usec
      add :last_attempt_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :last_status_code, :integer
      add :last_error, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:kunai_deliveries, [:event_id, :endpoint_id], prefix: ctx.prefix)
    create index(:kunai_deliveries, [:endpoint_id, :status, :id], prefix: ctx.prefix)
    create index(:kunai_deliveries, [:owner, :id], prefix: ctx.prefix)
    create index(:kunai_deliveries, [:status, :next_attempt_at], prefix: ctx.prefix)

    create table(:kunai_attempts, primary_key: false, prefix: ctx.prefix) do
      add :id, :string, size: 40, primary_key: true

      add :delivery_id,
          references(:kunai_deliveries,
            type: :string,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :endpoint_id, :string, size: 40, null: false
      add :number, :integer, null: false
      add :status_code, :integer
      add :duration_ms, :integer
      add :response_body, :text
      add :error, :text
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:kunai_attempts, [:delivery_id, :number], prefix: ctx.prefix)
    create index(:kunai_attempts, [:created_at], prefix: ctx.prefix)

    create table(:kunai_audit_log, primary_key: false, prefix: ctx.prefix) do
      add :id, :string, size: 40, primary_key: true
      add :owner, :string, size: 255
      add :endpoint_id, :string, size: 40
      add :action, :string, size: 32, null: false
      add :actor, :map
      add :changes, :map, null: false, default: %{}
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:kunai_audit_log, [:owner, :id], prefix: ctx.prefix)
    create index(:kunai_audit_log, [:endpoint_id, :id], prefix: ctx.prefix)
  end

  def down(ctx) do
    for table <- ~w(kunai_audit_log kunai_attempts kunai_deliveries kunai_events
                    kunai_endpoint_secrets kunai_endpoints)a do
      drop_if_exists table(table, prefix: ctx.prefix)
    end
  end
end
