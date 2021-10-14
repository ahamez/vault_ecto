pid_file = "./pidfile"

vault {
  address = "https://127.0.0.1:8200"
}

auto_auth {
  method {
    type  = "approle"

    config = {
      role_id_file_path = "./vault/role_id"
      secret_id_file_path = "./vault/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }
}

template {
  source      = "./vault/vault_ecto.template"
  destination = "./secrets/vault_ecto"

  error_on_missing_key = true
  backup = false
}

