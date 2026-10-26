defmodule Mix.Tasks.Kunai.Gen.Migration do
  @shortdoc "Generates the migration that installs or upgrades Kunai's tables"

  @moduledoc """
  Generates the migration of Kunai's tables in the app's repo: the one
  that installs them, or, after an upgrade of Kunai, the one that brings
  them to their latest version.

      $ mix kunai.gen.migration
      $ mix kunai.gen.migration --repo MyApp.Repo

  It is `mix phoenix_mountable.gen.migration Kunai.Migrations`: the
  version the app is at is read from its migrations, and the new migration
  pins the latest (see `Kunai.Migrations`). Run it with `mix ecto.migrate`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args), do: Mix.Task.run("phoenix_mountable.gen.migration", ["Kunai.Migrations" | args])
end
