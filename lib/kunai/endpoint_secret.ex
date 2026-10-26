defmodule Kunai.EndpointSecret do
  @moduledoc """
  A secret that signs an endpoint's requests (`Kunai.Signature`), encrypted
  at rest (`Kunai.Vault`).

  An endpoint has one, or two while it rolls (`Kunai.roll_secret/3`): the
  old one, with an `:expires_at`, signs beside the new until then, so the
  receiver can change its secret in its own time.

    * `"hmac"` - a shared secret, `whsec_…`: HMAC-SHA256, `v1`.
    * `"ed25519"` - a key pair: the endpoint keeps the public key,
      `whpk_…`, and Kunai the private one: `v1a`.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key {:id, :string, autogenerate: false}

  schema "kunai_endpoint_secrets" do
    belongs_to :endpoint, Kunai.Endpoint, type: :string
    field :kind, :string, default: "hmac"
    field :ciphertext, :binary
    field :public_key, :binary
    field :expires_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end

  @doc "Whether it still signs at this time."
  @spec active?(t(), DateTime.t()) :: boolean()
  def active?(%__MODULE__{expires_at: nil}, _now), do: true
  def active?(%__MODULE__{expires_at: at}, now), do: DateTime.compare(at, now) == :gt
end
