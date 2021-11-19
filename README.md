# Automatic reloading of PostgreSQL credentials with Ecto

This repository is an example of how to automatically reload the credentials with [Ecto](https://github.com/elixir-ecto/ecto) of a [PostgreSQL](https://www.postgresql.org/) instance rotated automatically by [Vault](https://www.vaultproject.io/).

Note that Vault is not strictly required to rotate credentials, as long as an automatic process update these credentials. However, being the de-facto server to manage secrets, it's useful to see that it's easy to make Ecto and Vault work together.

### Tested with

* Elixir 1.12.3
* Ecto 3.7.1
* Vault 1.8.4
* Postgres 14.1

## How it works

- Vault agent renews credentials automatically and renders them in a file;
- We use [secrets_watcher](https://hex.pm/packages/secrets_watcher) to detect changes to this file;
- When a change is detected, we use [`disconnect_all/3`](https://hexdocs.pm/db_connection/2.4.1/DBConnection.html#disconnect_all/3) from [`db_connection`](https://hex.pm/packages/db_connection) to force connections to the database to disconnect (they will automatically reconnect after a backoff);
- Upon restart, these connections will reconfigure themselves using a MFA given when [configuring the repo](https://github.com/ahamez/vault_ecto/blob/fa88f43c0bdc655e9e69a306b1a78cc930236d9e/config/config.exs#L11).

⚠️ It requires `db_connection` >= 2.4.1, make sure your dependencies are up to date.

## Steps

### Launch server instances

* In a dedicated terminal (will set the root token to `root`), run vault dev server:
    ```sh
    vault server -dev -dev-root-token-id root
    ```
    ⚠️ in memory only, when the server is shutdown, everything is lost.

* Have a postgres instance running.
  On macOS (default user/pass: `postgres`/`postgres`):
    ```sh
    brew install postgres
    brew services start postgresql
    ```

### Configure Vault database engine

* In another terminal, login to vault as root:
    ```sh
    export VAULT_ADDR=http://127.0.0.1:8200
    vault login root
    ```
    👉 You can connect to the Vault GUI at [http://127.0.0.1:8200/ui](http://127.0.0.1:8200/ui)

* Enable vault database secret engine:
    ```sh
    vault secrets enable database
    ```

* Configure database plugin for our `vault_ecto` database:
    ```sh
    vault write database/config/vault_ecto \
      plugin_name=postgresql-database-plugin \
      allowed_roles="vault_ecto" \
      connection_url="postgresql://{{username}}:{{password}}@localhost:5432/vault_ecto?sslmode=disable" \
      username="postgres" \
      password="postgres"
    ```
    ℹ️ `username` and `password` are the  admin postgres instance credentials
    ℹ️ note the `?sslmode=disable` to connect to the dev instance (which is obviously a bad idea in production!)

* Create a role `vault_ecto`:
    ```sh
    vault write database/roles/vault_ecto \
      db_name=vault_ecto \
      creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';\
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";\
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; " \
      default_ttl="1m" \
      max_ttl="2m"
    ```

* Create a policy to authorize reading vault_ecto database credentials:
    ```sh
    vault policy write read_vault_ecto_creds ./vault/read_vault_ecto_creds_policy.hcl
    ```

### Configure AppRole for vault agent

ℹ️ Vault agent provides many ways to authenticate to vault. However, using an approle is the fastest way for a local setup.

* Enable approle backend:
    ```sh
    vault auth enable approle
    ```

* Create approle:
    ```sh
    vault write auth/approle/role/vault-agent\
        secret_id_ttl=43200m\
        token_num_uses=9999\
        token_ttl=43200m\
        token_max_ttl=43200m\
        secret_id_num_uses=99999\
        policies=read_vault_ecto_creds\
        token_policies=read_vault_ecto_creds
    ```

### Launch vault agent


* Get agent's approle role-id:
    ```sh
    vault read -format=json auth/approle/role/vault-agent/role-id | jq -r '.data.role_id' > ./vault/role_id
    ```

* Get agent's approle secret-id:
    ```sh
    vault write -format=json -f auth/approle/role/vault-agent/secret-id | jq -r '.data.secret_id' > ./vault/secret_id
    ```

* Launch vault agent:
    ```sh
    vault agent -config ./vault/vault_agent_config.hcl
    ```

### Create database

* Connect to instance
    ```sh
    $ PGPASSWORD=postgres psql -U postgres -p 5432 -h 127.0.0.1
    ```

* Create database
    ```sql
    CREATE DATABASE vault_ecto;
    ```

### Launch vault_ecto and initialize database

* Launch vault_ecto:
    ```sh
    iex -S mix
    ```

* Create table:
    ```elixir
    iex> Ecto.Migrator.with_repo(VaultEcto.Repo, &Ecto.Migrator.run(&1, :up, all: true))
    ```

    ℹ️ This code applies all migrations in `priv/repo/migrations`.

* Seed table with some data:
    ```elixir
    iex> Code.eval_file("priv/repo/seed.exs")
    ```

## Cheatsheet

### `vault_ecto`

* Select query:
    ```elixir
    VaultEcto.Person |> Ecto.Query.first() |> VaultEcto.Repo.one()
    ```

* Insert query:
    ```elixir
     %VaultEcto.Person{first_name: "foo", last_name: "bar", age: 42} |> VaultEcto.Repo.insert()
    ```
    or
    ```elixir
    VaultEcto.insert()
    ```

* Long transaction:
    ```elixir
    VaultEcto.Repo.transaction(
      fn ->
        %VaultEcto.Person{first_name: "foo", last_name: "bar", age: 42}
        |> VaultEcto.Repo.insert!()

        :timer.sleep(100_000)

        %VaultEcto.Person{first_name: "foo", last_name: "bar", age: 42}
        |> VaultEcto.Repo.insert!()
      end,
      timeout: :infinity)
    ```
    or
    ```elixir
    VaultEcto.long_transaction(100_000)
    ```
    👉 Running this long running transaction proves that even if the credentials are rotated during its execution,
    it will not be interrupted.

### Vault

* To get database credentials:
    ```sh
    vault read database/creds/vault_ecto
    ```

* Login using approle:
    ```sh
    TOKEN=$(vault write auth/approle/login role_id=@./vault/role_id secret_id=@./vault/secret_id -format=json | jq -r '.auth.client_token')
    vault login ${TOKEN}
    ```

### Postgres

* Connect to database:
    ```sh
    psql -U postgres -p 5432 -h 127.0.0.1 -d vault_ecto
    ```
* List roles
    ```sh
    \du
    ```

* List tables
    ```sh
    \dt
    ```

* [List permissions](https://stackoverflow.com/a/40759633/21584)
    ```sh
    select * from information_schema.role_table_grants where grantee='YOUR_USER';
    ```
