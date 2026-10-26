defmodule Kunai.Audit do
  @moduledoc """
  The audit log: each change to an endpoint or its secrets
  (`Kunai.AuditEntry`), with who made it, written in the change's
  transaction.
  """

  import Ecto.Query

  alias Kunai.{AuditEntry, Config, Owner, Page}

  @doc false
  def entry(%Kunai.Endpoint{} = endpoint, action, actor, changes \\ %{}) do
    %AuditEntry{
      id: Kunai.ID.generate("aud"),
      owner: endpoint.owner,
      endpoint_id: endpoint.id,
      action: action,
      actor: actor,
      changes: Owner.stringify(changes),
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  The log of a scope's endpoints, newest first (`Kunai.Page`). Options:
  `:endpoint_id`, and those of `Kunai.Page`.
  """
  @spec list(term(), keyword()) :: Page.t(AuditEntry.t())
  def list(scope, opts \\ []) do
    AuditEntry
    |> Owner.where(Owner.of(scope))
    |> then(&if(id = opts[:endpoint_id], do: where(&1, [a], a.endpoint_id == ^id), else: &1))
    |> Page.fetch(opts)
  end

  @doc false
  def insert(entry), do: Config.repo().insert(entry, Config.repo_opts())
end
