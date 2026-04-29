terraform {
  required_version = ">= 1.5"

  required_providers {
    vagrant = {
      source  = "bmatcuk/vagrant"
      version = "~> 4.0"
    }
    talos = {
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
