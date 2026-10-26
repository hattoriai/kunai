defmodule Kunai.Vault do
  @moduledoc """
  What encrypts the endpoints' secrets at rest: a copy of the database
  does not give them away.

      config :kunai, vault: {Kunai.Vault.Cloak, vault: MyApp.Vault}

    * `Kunai.Vault.Cloak` - the app's [Cloak](https://hex.pm/packages/cloak)
      vault (with `Cloak.Ciphers.AES.GCM`).
    * `Kunai.Vault.Unencrypted` - kept as they are: for tests only.
    * A module of the app's, of this behaviour, around its KMS.
  """

  @doc "The ciphertext of a secret."
  @callback encrypt(plaintext :: binary(), opts :: keyword()) :: binary()

  @doc "The secret of a ciphertext."
  @callback decrypt(ciphertext :: binary(), opts :: keyword()) :: binary()

  @doc false
  def encrypt(plaintext) do
    {vault, opts} = Kunai.Config.vault()
    vault.encrypt(plaintext, opts)
  end

  @doc false
  def decrypt(ciphertext) do
    {vault, opts} = Kunai.Config.vault()
    vault.decrypt(ciphertext, opts)
  end
end
