defmodule Kunai.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/hattoriai/kunai"

  def project do
    [
      app: :kunai,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
      package: package(),
      docs: docs(),
      description: description(),
      name: "Kunai",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [mod: {Kunai.Application, []}, extra_applications: [:logger, :crypto, :public_key, :ssl]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      # The endpoints, events and deliveries, in the app's database, on
      # PostgreSQL or SQLite.
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.19", only: :test},
      {:ecto_sqlite3, "~> 0.22", only: :test},
      # The tables' versions (Kunai.Migrations), and a webhook's body as it
      # was sent, for the receiver's plug (PhoenixMountable.RawBody).
      {:phoenix_mountable, "~> 0.2.5"},
      {:phoenix, "~> 1.7.14 or ~> 1.8"},
      # The pages of the endpoints, mounted in the app (Kunai.Router).
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_ecto, "~> 4.6"},
      {:lazy_html, "~> 0.1", only: :test},
      # The outbox: an event's job is inserted in the transaction of the
      # change it tells of. Oban's open source engines, Basic and Lite.
      {:oban, "~> 2.19"},
      # The requests to endpoints: a connection to the address that was
      # checked (Kunai.Egress), with the endpoint's name for TLS.
      {:mint, "~> 1.6"},
      {:plug, "~> 1.15"},
      {:telemetry, "~> 1.0"},
      {:bandit, "~> 1.5", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      # Kunai.Text with an app's backend, in the tests.
      {:gettext, "~> 1.0", only: :test}
    ]
  end

  defp description do
    "Webhooks for Phoenix: events kept, signed, delivered and retried, to your users' endpoints."
  end

  defp package do
    [
      name: "kunai",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files:
        ~w(lib priv/static priv/gettext guides mix.exs .formatter.exs README.md CHANGELOG.md LICENSE NOTICE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      assets: %{"media" => "media"},
      extras: ["README.md", "guides/customizing.md", "CHANGELOG.md"]
    ]
  end
end
