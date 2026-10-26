defmodule Kunai.Config do
  @moduledoc """
  Kunai's configuration, in the app's:

      config :kunai,
        repo: MyApp.Repo,
        catalog: MyApp.Webhooks,
        vault: {Kunai.Vault.Cloak, vault: MyApp.Vault}

    * `:repo` - the app's `Ecto.Repo`, where Kunai's tables are
      (`Kunai.Migrations`). Required.
    * `:catalog` - the app's events (`Kunai.Catalog`). Required.
    * `:vault` - what encrypts the endpoints' secrets at rest
      (`Kunai.Vault`). Required before an endpoint is made.
    * `:oban` - the name of the app's Oban instance (`Oban`).
    * `:queue` - the Oban queue of Kunai's jobs (`:kunai`). The app's Oban
      runs it: `queues: [kunai: 20]`.
    * `:authorizer` - which endpoint may see which event (`Kunai.Authorizer`,
      by scopes by default).
    * `:retry_policy` - when a failed delivery is tried again
      (`Kunai.RetryPolicy`, about three days by default).
    * `:notifier` - who is told of an endpoint failing, and disabled
      (`Kunai.Notifier`, the log by default).
    * `:transport` - what sends a request (`Kunai.Transport`, HTTP by
      default).
    * `:serializer` - JSON (`Kunai.Serializer`, Elixir's own by default).
    * `:egress` - which addresses requests may reach (`Kunai.Egress`):
      `allow_http: false` and `allow_private: false` in production;
      `true` for an endpoint on localhost in development.
    * `:timeouts` - `connect: 5_000` and `total: 15_000`, in milliseconds.
    * `:max_payload_bytes` - the largest body sent (256 KB). A larger
      event is not sent, and its delivery fails.
    * `:max_response_bytes` - how much of a response is read (64 KB), and
      `:kept_response_bytes`, how much of it each attempt keeps (2 KB).
    * `:circuit_breaker` - when an endpoint failing is left alone for a
      while (`Kunai.CircuitBreaker`), or `false`.
    * `:warn_after` and `:disable_after` - how long, in seconds, an
      endpoint fails before its owner is warned (a day), and before it is
      disabled (three days).
    * `:rotation_overlap` - how long, in seconds, a rolled secret still
      signs (a day).
    * `:retention_days` - how long events and attempts are kept (30), by
      `Kunai.prune/1` (`Kunai.Workers.Prune`).
    * `:pubsub` - a `Phoenix.PubSub` server: the subscriptions' cache is
      cleared on every node of the cluster, and the delivery log is live.
    * `:db_prefix` - the database schema of the tables, in PostgreSQL.
  """

  @doc false
  def repo do
    get(:repo) || raise ArgumentError, "Kunai needs a repo: config :kunai, repo: MyApp.Repo"
  end

  @doc false
  def catalog do
    get(:catalog) ||
      raise ArgumentError, "Kunai needs its events: config :kunai, catalog: MyApp.Webhooks"
  end

  @doc false
  def oban, do: get(:oban, Oban)

  @doc false
  def queue, do: get(:queue, :kunai)

  @doc false
  def authorizer, do: adapter(:authorizer, Kunai.Authorizer.Scopes)

  @doc false
  def retry_policy, do: adapter(:retry_policy, Kunai.RetryPolicy.Default)

  @doc false
  def notifier, do: adapter(:notifier, Kunai.Notifier.Logger)

  @doc false
  def transport, do: adapter(:transport, Kunai.Transport.HTTP)

  @doc false
  def serializer, do: get(:serializer, Kunai.Serializer.JSON)

  @doc false
  def vault do
    case get(:vault) do
      nil ->
        raise ArgumentError,
              "Kunai needs a vault for the endpoints' secrets: " <>
                "config :kunai, vault: {Kunai.Vault.Cloak, vault: MyApp.Vault}"

      vault ->
        normalize(vault)
    end
  end

  @doc false
  def egress, do: get(:egress, [])

  @doc false
  def timeouts, do: Keyword.merge([connect: 5_000, total: 15_000], get(:timeouts, []))

  @doc false
  def max_payload_bytes, do: get(:max_payload_bytes, 256_000)

  @doc false
  def max_response_bytes, do: get(:max_response_bytes, 64_000)

  @doc false
  def kept_response_bytes, do: get(:kept_response_bytes, 2_000)

  @doc false
  def warn_after, do: get(:warn_after, 86_400)

  @doc false
  def disable_after, do: get(:disable_after, 3 * 86_400)

  @doc false
  def rotation_overlap, do: get(:rotation_overlap, 86_400)

  @doc false
  def retention_days, do: get(:retention_days, 30)

  @doc false
  def pubsub, do: get(:pubsub)

  @doc false
  def db_prefix, do: get(:db_prefix)

  @doc false
  # The options of every query: the tables' schema.
  def repo_opts, do: [prefix: db_prefix()]

  defp adapter(key, default), do: key |> get(default) |> normalize()

  defp normalize({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp normalize(module) when is_atom(module), do: {module, []}

  defp get(key, default \\ nil), do: Application.get_env(:kunai, key, default)
end
