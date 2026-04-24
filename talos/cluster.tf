locals {
  cluster_endpoint = "https://${var.cluster_endpoint_ip}:6443"
  all_node_ips     = concat(var.control_plane_ips, var.worker_ips)
}

# --- Secrets (PKI, tokens, etc.) ---

resource "talos_machine_secrets" "this" {}

# --- Machine configs ---

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = var.control_plane_ips
  nodes                = local.all_node_ips
}

# --- Apply configs ---

resource "talos_machine_configuration_apply" "controlplane" {
  for_each = toset(var.control_plane_ips)

  depends_on = [vagrant_vm.cluster]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = toset(var.worker_ips)

  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value
}

# --- Bootstrap etcd on the first control plane ---

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.cluster_endpoint_ip
}

# --- Retrieve kubeconfig ---

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.cluster_endpoint_ip
}
