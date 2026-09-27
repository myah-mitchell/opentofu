terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.70.0"
    }
  }

  # State is stored in Postgres. The connection string comes from PG_CONN_STR,
  # so nothing site-specific is committed. See README.md.
  backend "pg" {}

  # The key provider and method come from the TF_ENCRYPTION environment
  # variable, which keeps the passphrase out of git. `enforced` makes OpenTofu
  # refuse to read or write unencrypted state if that variable is missing.
  encryption {
    state {
      enforced = true
    }
    plan {
      enforced = true
    }
  }
}
