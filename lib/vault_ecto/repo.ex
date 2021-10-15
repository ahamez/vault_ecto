defmodule VaultEcto.Repo do
  require Logger

  use Ecto.Repo,
    otp_app: :vault_ecto,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, opts) do
    Logger.debug("Starting #{__MODULE__} with opts: #{inspect(opts)}")

    wrapped_url = get_wrapped_url(opts)
    opts = Keyword.put(opts, :url, wrapped_url.())

    {:ok, opts}
  end

  # Called when a pool connection is (re)started.
  def configure(opts) do
    wrapped_url = get_wrapped_url(opts)
    url = wrapped_url.()

    [username, password] =
      url
      |> URI.parse()
      |> Map.get(:userinfo)
      |> String.split(":")

    opts
    |> Keyword.replace!(:username, username)
    |> Keyword.replace!(:password, password)
    |> tap(fn opts ->
      Logger.debug("Configured database connection #{inspect(Keyword.get(opts, :pool_index))}")
    end)
  end

  # -- Private

  defp get_wrapped_url(opts) do
    case System.fetch_env("VAULT_ECTO_POSTGRES_URL") do
      {:ok, url} ->
        fn -> url end

      :error ->
        conf = Keyword.fetch!(opts, :conf)
        VaultEcto.Secrets.get_wrapped_secret(conf.servers.secrets, "vault_ecto")
    end
  end
end
