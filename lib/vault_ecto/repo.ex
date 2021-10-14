defmodule VaultEcto.Repo do
  require Logger

  use Ecto.Repo,
    otp_app: :vault_ecto,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(context, opts) do
    Logger.debug("Starting #{__MODULE__} (context: #{context}) with opts: #{inspect(opts)}")

    url = get_url(opts)
    opts = Keyword.put(opts, :url, url)

    {:ok, opts}
  end

  # Called when a pool connection is (re)started.
  def configure(opts) do
    [username, password] =
      opts
      |> get_url()
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

  def execute(fun, timers \\ [0, 1, 10, 100, 1000]) when is_function(fun) do
    do_execute(fun, timers)
  end

  # -- Private

  defp do_execute(fun, _timers = []) do
    fun.()
  end

  defp do_execute(fun, [timer | timers]) do
    try do
      fun.()
    rescue
      e in Postgrex.Error ->
        case e do
          %Postgrex.Error{postgres: %{code: code}}
          when code in [
                 :insufficient_privilege,
                 :invalid_authorization_specification,
                 :invalid_password
               ] ->
            :timer.sleep(timer)
            do_execute(fun, timers)

          _ ->
            reraise e, __STACKTRACE__
        end
    end
  end

  defp get_url(opts) do
    case System.fetch_env("VAULT_ECTO_POSTGRES_URL") do
      {:ok, url} ->
        url

      :error ->
        conf = Keyword.fetch!(opts, :conf)
        VaultEcto.Secrets.get_secret(conf.servers.secrets, "vault_ecto")
    end
  end
end
