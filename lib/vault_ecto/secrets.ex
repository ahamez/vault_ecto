defmodule VaultEcto.Secrets do
  use GenServer
  require Logger

  defmodule State do
    defstruct secrets_dir_watcher_pid: nil,
              secrets: %{},
              secrets_dir_path: nil
  end

  def start_link(opts) do
    Logger.debug("Start #{__MODULE__} with #{inspect(opts)}")
    conf = Keyword.fetch!(opts, :conf)

    GenServer.start_link(__MODULE__, conf, opts)
  end

  def read_secret(server, secret_name) do
    GenServer.call(server, {:read_secret, secret_name})
  end

  def get_secret(server, secret_name) do
    GenServer.call(server, {:get_secret, secret_name})
  end

  def get_secrets(server) do
    GenServer.call(server, :get_secrets)
  end

  # -- GenServer

  @impl true
  def init(conf) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [conf.secrets_dir])
    FileSystem.subscribe(watcher_pid)

    {
      :ok,
      %State{
        secrets_dir_watcher_pid: watcher_pid,
        secrets: load_secrets(conf.secrets_dir),
        secrets_dir_path: conf.secrets_dir
      }
    }
  end

  @impl true
  def handle_info(
        {:file_event, watcher_pid, {path, events}},
        %State{secrets_dir_watcher_pid: watcher_pid} = state
      ) do
    Logger.debug("Path #{inspect(path)}: #{inspect(events)}")

    case load_updated_secret(state.secrets, events, path) do
      :unchanged ->
        {:noreply, state}

      {:changed, secret_name, new_secret} ->
        new_secrets = Map.put(state.secrets, secret_name, new_secret)
        Logger.debug("Secret #{secret_name} has changed (#{new_secret})")

        # Using :continue will invoke handle_continue next, but it ensures at the same time
        # that the state is updated before any other process call get_secret/2.
        {:noreply, %{state | secrets: new_secrets},
         {:continue, {:notify_new_secret, secret_name, new_secret}}}
    end
  end

  @impl true
  def handle_info(
        {:file_event, watcher_pid, :stop},
        %State{secrets_dir_watcher_pid: watcher_pid} = state
      ) do
    Logger.warn("Secrets dir watcher terminated")

    {:noreply, state}
  end

  @impl true
  def handle_continue({:notify_new_secret, secret_name = "vault_ecto", _new_secret}, state) do
    case secret_name do
      "vault_ecto" ->
        Logger.debug("Will notify repo that secret #{secret_name} has been updated")
        {_, %{pid: pid}} = Ecto.Repo.Registry.lookup(VaultEcto.Repo)
        DBConnection.disconnect_all(pid, 1_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:read_secret, secret_name}, _from, %State{} = state) do
    secret_path = Path.join(state.secrets_dir_path, secret_name)
    Logger.debug("Read secret from #{secret_path}")
    {_secret_name, secret} = load_secret(secret_path)

    {:reply, secret, state}
  end

  @impl true
  def handle_call({:get_secret, secret_name}, _from, %State{} = state) do
    secret = Map.get(state.secrets, secret_name)

    {:reply, secret, state}
  end

  @impl true
  def handle_call(:get_secrets, _from, %State{} = state) do
    {:reply, state.secrets, state}
  end

  # -- Private

  defp load_secrets(secrets_dir_path) do
    for secret_path <- File.ls!(secrets_dir_path), into: %{} do
      abs_path = Path.join(secrets_dir_path, secret_path)
      Logger.debug("Load secret from #{abs_path}")
      load_secret(abs_path)
    end
  end

  defp load_updated_secret(secrets, events, path) do
    if contains_watched_events?(events) and is_file?(path) do
      {secret_name, new_secret} = load_secret(path)

      if Map.fetch!(secrets, secret_name) == new_secret do
        Logger.debug("Secret #{secret_name} hasn't changed")
        :unchanged
      else
        {:changed, secret_name, new_secret}
      end
    else
      :unchanged
    end
  end

  defp contains_watched_events?(events) do
    Enum.any?(events, fn
      :modified -> true
      :created -> true
      :renamed -> true
      _ -> false
    end)
  end

  defp is_file?(path) do
    File.exists?(path) and not File.dir?(path)
  end

  defp load_secret(path) do
    secret_name = Path.basename(path)
    secret = path |> File.read!() |> String.trim()

    {secret_name, secret}
  end
end
