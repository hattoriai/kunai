defmodule Kunai.Endpoints do
  @moduledoc """
  Endpoints and their secrets, by scope. Each change is written with a
  line of the audit log (`Kunai.Audit`) in its transaction, and clears the
  owner's subscriptions on every node (`Kunai.Subscriptions`).
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Kunai.{Audit, Config, Endpoint, EndpointSecret, Owner, Secret, Subscriptions, Vault}

  @doc """
  Makes an endpoint, and its first secret: `{:ok, endpoint, secret}`, the
  secret shown to its owner once (`whsec_…`, or `whpk_…` with
  `signing: :ed25519`).

  Attributes: `:url`, `:events`, `:description`, `:scopes`, `:payload`,
  `:ordered`, `:api_version`, `:metadata` (`Kunai.Endpoint`). Options:
  `:signing`, `:hmac` (the default) or `:ed25519`.
  """
  @spec create(term(), map(), keyword()) ::
          {:ok, Endpoint.t(), String.t()} | {:error, Ecto.Changeset.t()}
  def create(scope, attrs, opts \\ []) do
    owner = Owner.of(scope)
    changeset = Endpoint.create_changeset(attrs, owner)
    signing = Keyword.get(opts, :signing, :hmac)

    Multi.new()
    |> Multi.insert(:endpoint, changeset, Config.repo_opts())
    |> Multi.run(:secret, fn repo, %{endpoint: endpoint} ->
      insert_secret(repo, endpoint, signing)
    end)
    |> Multi.run(:audit, fn _repo, %{endpoint: endpoint} ->
      Audit.insert(Audit.entry(endpoint, "created", Owner.actor(scope), changeset.changes))
    end)
    |> transaction(owner)
    |> case do
      {:ok, %{endpoint: endpoint, secret: {_row, secret}}} -> {:ok, endpoint, secret}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc "A scope's endpoints, newest first (`Kunai.Page`). Options: `:status`, and those of `Kunai.Page`."
  @spec list(term(), keyword()) :: Kunai.Page.t(Endpoint.t())
  def list(scope, opts \\ []) do
    Endpoint
    |> Owner.where(Owner.of(scope))
    |> then(&if(status = opts[:status], do: where(&1, [e], e.status == ^status), else: &1))
    |> Kunai.Page.fetch(opts)
  end

  @doc "An endpoint of a scope, or nil."
  @spec get(term(), String.t()) :: Endpoint.t() | nil
  def get(scope, id) do
    Endpoint
    |> Owner.where(Owner.of(scope))
    |> where([e], e.id == ^id)
    |> Config.repo().one(Config.repo_opts())
  end

  @doc "Changes an endpoint (the attributes of `create/3`)."
  @spec update(term(), Endpoint.t(), map()) :: {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t()}
  def update(scope, %Endpoint{} = endpoint, attrs) do
    changeset = Endpoint.changeset(endpoint, attrs)
    change(scope, changeset, "updated", changeset.changes)
  end

  @doc "Enables an endpoint, and forgets that it was failing."
  @spec enable(term(), Endpoint.t()) :: {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t()}
  def enable(scope, %Endpoint{} = endpoint) do
    endpoint
    |> Ecto.Changeset.change(
      status: "enabled",
      disabled_reason: nil,
      failing_since: nil,
      warned_at: nil
    )
    |> then(&change(scope, &1, "enabled"))
  end

  @doc """
  Disables an endpoint: it gets no new deliveries, and those pending fail
  (`Kunai.Deliveries.replay/3` sends them again once it is enabled).
  """
  @spec disable(term(), Endpoint.t(), String.t()) ::
          {:ok, Endpoint.t()} | {:error, Ecto.Changeset.t()}
  def disable(scope, %Endpoint{} = endpoint, reason \\ "manual") do
    endpoint
    |> Ecto.Changeset.change(status: "disabled", disabled_reason: reason)
    |> then(&change(scope, &1, "disabled", %{reason: reason}))
  end

  @doc "Deletes an endpoint, its secrets and its deliveries. The audit log keeps that it was."
  @spec delete(term(), Endpoint.t()) :: {:ok, Endpoint.t()} | {:error, term()}
  def delete(scope, %Endpoint{} = endpoint) do
    Multi.new()
    |> Multi.run(:audit, fn _repo, _changes ->
      Audit.insert(Audit.entry(endpoint, "deleted", Owner.actor(scope), %{url: endpoint.url}))
    end)
    |> Multi.delete(:endpoint, endpoint, Config.repo_opts())
    |> transaction(endpoint.owner)
    |> case do
      {:ok, %{endpoint: endpoint}} -> {:ok, endpoint}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp change(scope, changeset, action, changes \\ %{}) do
    Multi.new()
    |> Multi.update(:endpoint, changeset, Config.repo_opts())
    |> Multi.run(:audit, fn _repo, %{endpoint: endpoint} ->
      Audit.insert(Audit.entry(endpoint, action, Owner.actor(scope), changes))
    end)
    |> transaction(changeset.data.owner)
    |> case do
      {:ok, %{endpoint: endpoint}} -> {:ok, endpoint}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  defp transaction(multi, owner) do
    with {:ok, _changes} = ok <- Config.repo().transaction(multi) do
      Subscriptions.invalidate(owner)
      ok
    end
  end

  @doc """
  Rolls an endpoint's secret: a new one signs from now, and the ones
  before sign beside it for `:expires_in` seconds more (`Kunai.Config`'s
  `:rotation_overlap`, a day; 0 stops them at once), so the receiver
  changes its secret in its own time. Gives the new secret, shown once.
  Options: `:signing`, to change between `:hmac` and `:ed25519`.
  """
  @spec roll_secret(term(), Endpoint.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def roll_secret(scope, %Endpoint{} = endpoint, opts \\ []) do
    now = DateTime.utc_now()

    expires_at =
      DateTime.add(now, Keyword.get(opts, :expires_in, Config.rotation_overlap()), :second)

    signing = Keyword.get_lazy(opts, :signing, fn -> current_kind(endpoint) end)

    Multi.new()
    |> Multi.delete_all(
      :expired,
      secrets(endpoint) |> where([s], s.expires_at <= ^now),
      Config.repo_opts()
    )
    |> Multi.update_all(
      :expiring,
      secrets(endpoint) |> where([s], is_nil(s.expires_at) or s.expires_at > ^expires_at),
      [set: [expires_at: expires_at]],
      Config.repo_opts()
    )
    |> Multi.run(:secret, fn repo, _changes -> insert_secret(repo, endpoint, signing) end)
    |> Multi.run(:audit, fn _repo, _changes ->
      Audit.insert(
        Audit.entry(endpoint, "secret_rolled", Owner.actor(scope), %{expires_at: expires_at})
      )
    end)
    |> Config.repo().transaction()
    |> case do
      {:ok, %{secret: {_row, secret}}} -> {:ok, secret}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  The secret the endpoint's receiver checks with now: `whsec_…`, or
  `whpk_…` for Ed25519. To show it again to its owner.
  """
  @spec secret(Endpoint.t()) :: String.t() | nil
  def secret(%Endpoint{} = endpoint) do
    case active_secrets(endpoint) do
      [] -> nil
      secrets -> secrets |> List.last() |> public_form()
    end
  end

  @doc false
  # The keys that sign the endpoint's requests now: {:hmac, key} or
  # {:ed25519, private_key}.
  def keys(%Endpoint{} = endpoint) do
    for secret <- active_secrets(endpoint) do
      {String.to_existing_atom(secret.kind), Vault.decrypt(secret.ciphertext)}
    end
  end

  defp active_secrets(endpoint) do
    now = DateTime.utc_now()

    endpoint
    |> secrets()
    |> where([s], is_nil(s.expires_at) or s.expires_at > ^now)
    |> order_by([s], asc: s.inserted_at, asc: s.id)
    |> Config.repo().all(Config.repo_opts())
  end

  defp current_kind(endpoint) do
    case active_secrets(endpoint) do
      [] -> :hmac
      secrets -> secrets |> List.last() |> Map.fetch!(:kind) |> String.to_existing_atom()
    end
  end

  defp public_form(%EndpointSecret{kind: "hmac"} = secret),
    do: Secret.encode(:hmac, Vault.decrypt(secret.ciphertext))

  defp public_form(%EndpointSecret{kind: "ed25519", public_key: public}),
    do: Secret.encode(:public, public)

  defp secrets(endpoint), do: where(EndpointSecret, [s], s.endpoint_id == ^endpoint.id)

  defp insert_secret(repo, endpoint, signing) when signing in [:hmac, :ed25519] do
    {row, shown} =
      case Secret.generate(signing) do
        {:hmac, key, shown} ->
          {%{kind: "hmac", ciphertext: Vault.encrypt(key)}, shown}

        {:ed25519, private, public, shown} ->
          {%{kind: "ed25519", ciphertext: Vault.encrypt(private), public_key: public}, shown}
      end

    secret =
      struct!(
        EndpointSecret,
        Map.merge(row, %{
          id: Kunai.ID.generate("sec"),
          endpoint_id: endpoint.id,
          inserted_at: DateTime.utc_now()
        })
      )

    with {:ok, secret} <- repo.insert(secret, Config.repo_opts()), do: {:ok, {secret, shown}}
  end
end
