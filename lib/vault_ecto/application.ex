defmodule VaultEcto.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    conf = %{
      servers: %{secrets: :secrets},
      secrets_dir: System.get_env("VAULT_ECTO_SECRETS_DIR", "./secrets")
    }

    children = [
      {VaultEcto.Secrets, [name: :secrets, conf: conf]},
      {VaultEcto.Repo, [conf: conf]}
    ]

    opts = [strategy: :one_for_one, name: VaultEcto.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
