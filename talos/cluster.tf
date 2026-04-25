locals {
  cluster_endpoint = "https://${var.cluster_endpoint_ip}:6443"
  all_node_ips     = concat(var.control_plane_ips, var.worker_ips)

  # Patch that sets a static IP on eth1 (host-only NIC) for a given node.
  # eth1 = second NIC in VirtualBox; Talos uses eth* naming for Intel 82540EM adapters.
  network_patch = { for ip in local.all_node_ips : ip => yamlencode({
    machine = {
      network = {
        interfaces = [{
          interface = "eth1"
          addresses = ["${ip}/24"]
        }]
      }
    }
  }) }
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

# One config per worker so each gets its own IP patch at apply time
data "talos_machine_configuration" "worker" {
  for_each = toset(var.worker_ips)

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
# Connect via NAT-forwarded localhost port for the initial apply (Talos maintenance
# mode). The config patch sets the static IP on eth1; after reboot subsequent
# resources connect directly via 192.168.56.x on the host-only network.

resource "talos_machine_configuration_apply" "controlplane" {
  for_each = toset(var.control_plane_ips)

  depends_on = [null_resource.talos_api_ready]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = each.value
  endpoint                    = "127.0.0.1:${var.node_api_ports[each.value]}"
  config_patches              = [local.network_patch[each.value]]
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = toset(var.worker_ips)

  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.value].machine_configuration
  node                        = each.value
  endpoint                    = "127.0.0.1:${var.node_api_ports[each.value]}"
  config_patches              = [local.network_patch[each.value]]
}

# --- Bootstrap etcd on the first control plane ---
# Connects via static IP after the CP reboots with the network patch applied.

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
