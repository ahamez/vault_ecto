defmodule VaultEcto do
  require Logger

  def insert() do
    %VaultEcto.Person{first_name: "foo", last_name: "bar", age: 42} |> VaultEcto.Repo.insert()
  end

  def long_transaction(duration \\ 100_000) do
    VaultEcto.Repo.transaction(
      fn ->
        insert()
        :timer.sleep(duration)
        insert()
      end,
      timeout: :infinity
    )
  end
end
