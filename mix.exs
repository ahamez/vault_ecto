defmodule VaultEcto.MixProject do
  use Mix.Project

  def project do
    [
      app: :vault_ecto,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {VaultEcto.Application, []}
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.1", only: [:test, :dev], runtime: false},
      {:ecto_sql, "~> 3.7"},
      {:file_system, "~> 0.2"},
      {:postgrex, ">= 0.0.0"}
    ]
  end
end
