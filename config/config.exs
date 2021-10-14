import Config

config :vault_ecto,
  ecto_repos: [VaultEcto.Repo]

config :vault_ecto,
  secrets_dir: {:env, "VAULT_ECTO_SECRETS_DIR", [default: "./secrets"]}

config :vault_ecto, VaultEcto.Repo,
  pool_size: 10,
  configure: {VaultEcto.Repo, :configure, []},
  disconnect_on_error_codes: [
    :insufficient_privilege,
    :invalid_authorization_specification,
    :invalid_password
  ]
