# All CA keys use ECDSA P256. hashicorp/tls v3.x outputs these as SEC1
# ("EC PRIVATE KEY") which is the format Talos's crypto package expects.
# v4.x switched to PKCS8 ("PRIVATE KEY") which breaks Talos cert parsing.

resource "random_id" "cluster_id" {
  byte_length = 32
}

resource "random_id" "cluster_secret" {
  byte_length = 32
}

resource "random_id" "secretbox_encryption_secret" {
  byte_length = 32
}

resource "random_string" "bootstrap_token_id" {
  length  = 6
  special = false
  upper   = false
}

resource "random_string" "bootstrap_token_secret" {
  length  = 16
  special = false
  upper   = false
}

resource "random_string" "trustdinfo_token_id" {
  length  = 6
  special = false
  upper   = false
}

resource "random_string" "trustdinfo_token_secret" {
  length  = 16
  special = false
  upper   = false
}

resource "tls_private_key" "os" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "os" {

  private_key_pem       = tls_private_key.os.private_key_pem
  subject { organization = "talos" }
  validity_period_hours = var.ca_validity_hours
  is_ca_certificate     = true
  allowed_uses          = ["digital_signature", "cert_signing", "server_auth", "client_auth"]
}

resource "tls_private_key" "etcd" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "etcd" {

  private_key_pem       = tls_private_key.etcd.private_key_pem
  subject { organization = "etcd" }
  validity_period_hours = var.ca_validity_hours
  is_ca_certificate     = true
  allowed_uses          = ["digital_signature", "cert_signing", "server_auth", "client_auth"]
}

resource "tls_private_key" "k8s" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "k8s" {

  private_key_pem       = tls_private_key.k8s.private_key_pem
  subject { organization = "kubernetes" }
  validity_period_hours = var.ca_validity_hours
  is_ca_certificate     = true
  allowed_uses          = ["digital_signature", "cert_signing", "server_auth", "client_auth"]
}

resource "tls_private_key" "k8s_aggregator" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "k8s_aggregator" {

  private_key_pem       = tls_private_key.k8s_aggregator.private_key_pem
  subject { organization = "front-proxy" }
  validity_period_hours = var.ca_validity_hours
  is_ca_certificate     = true
  allowed_uses          = ["digital_signature", "cert_signing", "server_auth", "client_auth"]
}

resource "tls_private_key" "k8s_serviceaccount" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Admin client cert — signed by OS CA, used for talosconfig
resource "tls_private_key" "client" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem
  subject { organization = "os:admin" }
}

resource "tls_locally_signed_cert" "client" {

  ca_cert_pem           = tls_self_signed_cert.os.cert_pem
  ca_private_key_pem    = tls_private_key.os.private_key_pem
  cert_request_pem      = tls_cert_request.client.cert_request_pem
  validity_period_hours = var.ca_validity_hours
  allowed_uses          = ["digital_signature", "client_auth"]
}

locals {
  machine_secrets = {
    cluster = {
      id     = random_id.cluster_id.b64_std
      secret = random_id.cluster_secret.b64_std
    }
    secrets = {
      bootstrap_token             = "${random_string.bootstrap_token_id.result}.${random_string.bootstrap_token_secret.result}"
      secretbox_encryption_secret = random_id.secretbox_encryption_secret.b64_std
    }
    trustdinfo = {
      token = "${random_string.trustdinfo_token_id.result}.${random_string.trustdinfo_token_secret.result}"
    }
    certs = {
      etcd = {
        key  = base64encode(trimspace(tls_private_key.etcd.private_key_pem))
        cert = base64encode(tls_self_signed_cert.etcd.cert_pem)
      }
      k8s = {
        key  = base64encode(trimspace(tls_private_key.k8s.private_key_pem))
        cert = base64encode(tls_self_signed_cert.k8s.cert_pem)
      }
      k8s_aggregator = {
        key  = base64encode(trimspace(tls_private_key.k8s_aggregator.private_key_pem))
        cert = base64encode(tls_self_signed_cert.k8s_aggregator.cert_pem)
      }
      k8s_serviceaccount = {
        key = base64encode(trimspace(tls_private_key.k8s_serviceaccount.private_key_pem))
      }
      os = {
        key  = base64encode(trimspace(tls_private_key.os.private_key_pem))
        cert = base64encode(tls_self_signed_cert.os.cert_pem)
      }
    }
  }

  client_configuration = {
    ca_certificate     = base64encode(tls_self_signed_cert.os.cert_pem)
    client_certificate = base64encode(tls_locally_signed_cert.client.cert_pem)
    client_key         = base64encode(trimspace(tls_private_key.client.private_key_pem))
  }
}
