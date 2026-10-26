defmodule Kunai.Vault.Cloak do
  @moduledoc """
  Secrets encrypted by the app's [Cloak](https://hex.pm/packages/cloak)
  vault (`Kunai.Vault`):

      config :kunai, vault: {Kunai.Vault.Cloak, vault: MyApp.Vault}

  Give the vault an authenticated cipher, `Cloak.Ciphers.AES.GCM`, not
  AES-CTR, whose ciphertexts can be changed unseen.
  """

  @behaviour Kunai.Vault

  @impl Kunai.Vault
  def encrypt(plaintext, opts), do: vault(opts).encrypt!(plaintext)

  @impl Kunai.Vault
  def decrypt(ciphertext, opts), do: vault(opts).decrypt!(ciphertext)

  defp vault(opts) do
    opts[:vault] ||
      raise ArgumentError,
            "Kunai.Vault.Cloak needs the app's vault: {Kunai.Vault.Cloak, vault: MyApp.Vault}"
  end
end
