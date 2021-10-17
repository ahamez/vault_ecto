defmodule VaultEcto.Repo do
  require Logger

  use Ecto.Repo,
    otp_app: :vault_ecto,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, opts) do
    Logger.debug("Starting #{__MODULE__} with opts: #{inspect(opts)}")

    wrapped_url = get_wrapped_url()
    opts = Keyword.put(opts, :url, wrapped_url.())

    {:ok, opts}
  end

  # Called when a pool connection is (re)started.
  def configure(opts) do
    wrapped_url = get_wrapped_url()
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

  def disconnect_all() do
    {_, %{pid: pid}} = Ecto.Repo.Registry.lookup(__MODULE__)
    DBConnection.disconnect_all(pid, 1_000)
  end

  # -- Private

  defp get_wrapped_url() do
    case System.fetch_env("VAULT_ECTO_POSTGRES_URL") do
      {:ok, url} ->
        fn -> url end

      :error ->
        {:ok, wrapped_url} = SecretsWatcher.get_wrapped_secret(:secrets, "vault_ecto")
        wrapped_url
    end
  end
end
