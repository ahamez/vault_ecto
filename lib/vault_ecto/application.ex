defmodule VaultEcto.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    secrets_directory = System.get_env("VAULT_ECTO_SECRETS_DIR", "./secrets")

    callbacks = %{
      "vault_ecto" => fn _secret_name, _wrapped_secret -> VaultEcto.Repo.disconnect_all() end
    }

    children = [
      {SecretsWatcher,
       [name: :secrets, secrets: [directory: secrets_directory, callbacks: callbacks]]},
      VaultEcto.Repo
    ]

    opts = [strategy: :one_for_one, name: VaultEcto.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
