defmodule VaultEcto.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    conf =
      %{servers: %{secrets: :secrets}}
      |> configure()

    children = [
      {VaultEcto.Secrets, [name: :secrets, conf: conf]},
      {VaultEcto.Repo, [conf: conf]}
    ]

    opts = [strategy: :one_for_one, name: VaultEcto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # -- Private

  defp configure(conf) do
    conf
    |> load(:secrets_dir)
    |> tap(fn conf -> Logger.debug("#{inspect(conf)}") end)
  end

  defp load(conf, key) do
    value =
      case Application.get_env(:vault_ecto, key) do
        {:env, var, opts} ->
          {type, opts} = Keyword.pop(opts, :type, :string)
          {default, opts} = Keyword.pop(opts, :default)
          {required, _opts} = Keyword.pop(opts, :required, default == nil)

          case {System.get_env(var), required, type} do
            {nil, true, _type} ->
              raise "#{var} is required, but unset"

            {nil, false, _type} ->
              default

            {value, _required, :string} ->
              value

            {value, _required, :integer} ->
              String.to_integer(value)
          end

        value ->
          value
      end

    Map.put(conf, key, value)
  end
end
