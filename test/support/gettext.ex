defmodule KunaiTest.Gettext do
  @moduledoc "An app's Gettext backend, with Kunai's messages in Portuguese."
  use Gettext.Backend, otp_app: :kunai, priv: "test/support/gettext"
end
