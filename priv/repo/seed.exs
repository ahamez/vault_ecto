people = [
  %VaultEcto.Person{first_name: "Ryan", last_name: "Bigg", age: 28},
  %VaultEcto.Person{first_name: "John", last_name: "Smith", age: 27},
  %VaultEcto.Person{first_name: "Jane", last_name: "Smith", age: 26},
]

Enum.each(people, fn (person) -> VaultEcto.Repo.insert(person) end)
