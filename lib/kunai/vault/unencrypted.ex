defmodule Kunai.Vault.Unencrypted do
  @moduledoc """
  Secrets kept as they are, not encrypted (`Kunai.Vault`): for tests, never
  for an app's real endpoints.
  """

  @behaviour Kunai.Vault

  @impl Kunai.Vault
  def encrypt(plaintext, _opts), do: plaintext

  @impl Kunai.Vault
  def decrypt(ciphertext, _opts), do: ciphertext
end
