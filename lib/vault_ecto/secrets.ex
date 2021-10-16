defmodule VaultEcto.Secrets do
  use Bitwise
  use GenServer

  require Logger

  defmodule State do
    defstruct watcher_pid: nil,
              secrets: %{},
              secrets_dir: nil
  end

  def start_link(opts) do
    Logger.debug("Start #{__MODULE__} with #{inspect(opts)}")
    conf = Keyword.fetch!(opts, :conf)

    GenServer.start_link(__MODULE__, conf, opts)
  end

  def get_wrapped_secret(server, secret_name) do
    GenServer.call(server, {:get_wrapped_secret, secret_name})
  end

  # -- GenServer

  @impl true
  def init(conf) do
    {:ok, watcher_pid} = FileSystem.start_link(dirs: [conf.secrets_dir])
    FileSystem.subscribe(watcher_pid)

    {
      :ok,
      %State{
        watcher_pid: watcher_pid,
        secrets: load_secrets(conf.secrets_dir),
        secrets_dir: conf.secrets_dir
      }
    }
  end

  @impl true
  def handle_info(
        {:file_event, watcher_pid, {path, events}},
        %State{watcher_pid: watcher_pid} = state
      ) do
    Logger.debug("Path #{inspect(path)}: #{inspect(events)}")

    case load_updated_secret(state.secrets, events, path) do
      :unchanged ->
        {:noreply, state}

      {:changed, secret_name, wrapped_new_secret} ->
        new_secrets = Map.put(state.secrets, secret_name, wrapped_new_secret)
        Logger.debug("Secret #{secret_name} has changed")

        # Using :continue will invoke handle_continue next, but it ensures at the same time
        # that the state is updated before any other process call get_wrapped_secret/2.
        {:noreply, %{state | secrets: new_secrets},
         {:continue, {:notify_new_secret, secret_name, wrapped_new_secret}}}
    end
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
  def handle_call({:get_wrapped_secret, secret_name}, _from, %State{} = state) do
    wrapped_secret = Map.get(state.secrets, secret_name)

    {:reply, wrapped_secret, state}
  end

  # -- Private

  defp load_secrets(secrets_dir) do
    for file_name <- File.ls!(secrets_dir), into: %{} do
      abs_path = Path.join(secrets_dir, file_name)
      Logger.debug("Load secret from #{abs_path}")
      load_secret(abs_path)
    end
  end

  defp load_updated_secret(secrets, events, path) do
    if contains_watched_events?(events) and is_file?(path) do
      {secret_name, wrapped_new_secret} = load_secret(path)
      wrapped_previous_secret = Map.get(secrets, secret_name, nil)

      cond do
        wrapped_previous_secret == nil ->
          :unchanged

        same_secrets?(wrapped_previous_secret.(), wrapped_new_secret.()) ->
          :unchanged

        true ->
          {:changed, secret_name, wrapped_new_secret}
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

    {secret_name, fn -> secret end}
  end

  # Constant-time comparison of secrets.
  defp same_secrets?(lhs, rhs) when byte_size(lhs) != byte_size(rhs) do
    false
  end

  defp same_secrets?(lhs, rhs) do
    compare_secrets(0, lhs, rhs)
  end

  defp compare_secrets(acc, <<x, lhs::binary>>, <<y, rhs::binary>>) do
    compare_secrets(acc ||| bxor(x, y), lhs, rhs)
  end

  defp compare_secrets(acc, <<>>, <<>>) do
    acc === 0
  end
end
