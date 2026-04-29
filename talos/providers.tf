terraform {
  required_version = ">= 1.5"

  required_providers {
    vagrant = {
      source  = "bmatcuk/vagrant"
      version = "~> 4.0"
    }
    talos = {
      # Pinned to beta: this is the earliest version supporting machine_secrets
      # as a plain input (not a managed resource), required for custom PKI.
      # Upgrade to stable once 0.11.x is released.
      source  = "siderolabs/talos"
      version = "0.11.0-beta.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "vagrant" {}
provider "talos" {}
provider "local" {}
provider "null" {}
provider "tls" {}
provider "random" {}
