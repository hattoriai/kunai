defmodule Kunai.Migrations.V2 do
  @moduledoc false
  # The API's idempotency keys (Kunai.API.Idempotency).

  use PhoenixMountable.Migration, description: "The API's idempotency keys"

  def up(ctx) do
    create table(:kunai_idempotency_keys, primary_key: false, prefix: ctx.prefix) do
      add :id, :string, size: 40, primary_key: true
      add :owner, :string, size: 255
      add :key, :string, size: 255, null: false
      add :fingerprint, :string, size: 64, null: false
      add :status, :integer
      add :response, :text
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index(:kunai_idempotency_keys, [:owner, :key], prefix: ctx.prefix)
    create index(:kunai_idempotency_keys, [:created_at], prefix: ctx.prefix)
  end

  def down(ctx) do
    drop_if_exists table(:kunai_idempotency_keys, prefix: ctx.prefix)
  end
end
