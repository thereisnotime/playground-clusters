locals {
  # Control planes: 192.168.56.10, .11, .12, …
  # Workers:        192.168.56.20, .21, .22, …
  # Ports:          sequential from 50001 (CPs first, then workers)

  control_plane_ips   = [for i in range(var.control_plane_count) : "192.168.56.${10 + i}"]
  worker_ips          = [for i in range(var.worker_count) : "192.168.56.${20 + i}"]
  all_node_ips        = concat(local.control_plane_ips, local.worker_ips)
  cluster_endpoint_ip = local.control_plane_ips[0]
  cluster_endpoint    = "https://${local.cluster_endpoint_ip}:6443"

  node_api_ports = { for i, ip in local.all_node_ips : ip => 50001 + i }

  node_hostnames = merge(
    { for i, ip in local.control_plane_ips : ip => "cp-${i + 1}" },
    { for i, ip in local.worker_ips : ip => "worker-${i + 1}" }
  )

  nodes_config = [for ip in local.all_node_ips : {
    name       = local.node_hostnames[ip]
    ip         = ip
    talos_port = local.node_api_ports[ip]
    cpus       = var.node_cpus
    memory     = var.node_memory
  }]

  network_patch = { for ip in local.all_node_ips : ip => yamlencode({
    machine = {
      network = {
        interfaces = [{
          deviceSelector = { busPath = "0000:00:08.0" }
          dhcp           = false
          addresses      = ["${ip}/24"]
        }]
      }
    }
  }) }

  kubelet_patch = { for ip in local.all_node_ips : ip => yamlencode({
    machine = {
      kubelet = {
        extraArgs = { "hostname-override" = local.node_hostnames[ip] }
      }
    }
  }) }
}

# --- Machine configs (PKI comes from pki.tf locals) ---

data "talos_machine_configuration" "controlplane" {
  for_each = toset(local.control_plane_ips)

  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = local.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.network_patch[each.value], local.kubelet_patch[each.value]]
}

data "talos_machine_configuration" "worker" {
  for_each = toset(local.worker_ips)

  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = local.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.network_patch[each.value], local.kubelet_patch[each.value]]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = local.client_configuration
  endpoints            = local.control_plane_ips
  nodes                = local.all_node_ips
}

# --- Wait for maintenance API on each node ---

resource "null_resource" "talos_api_ready" {
  depends_on = [vagrant_vm.cluster]

  triggers = {
    cluster_id = vagrant_vm.cluster.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      for port in ${join(" ", values(local.node_api_ports))}; do
        echo "Waiting for Talos API on 127.0.0.1:$port..."
        timeout 300 bash -c \
          'until nc -zw2 127.0.0.1 '"$port"' 2>/dev/null; do sleep 5; done' \
          || { echo "ERROR: Talos API on port $port not ready after 5 min"; exit 1; }
        echo "127.0.0.1:$port ready"
      done
    EOT
  }
}

# --- Apply machine configs via Talos provider (no local config files, no talosctl CLI) ---
# talos_machine_configuration_apply handles maintenance-mode TLS internally.
# endpoint supports host:port — needed for NAT port-forwarded VMs.

resource "talos_machine_configuration_apply" "controlplane" {
  for_each   = toset(local.control_plane_ips)
  depends_on = [null_resource.talos_api_ready]

  client_configuration        = local.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane[each.value].machine_configuration
  endpoint                    = "127.0.0.1:${local.node_api_ports[each.value]}"
  node                        = "127.0.0.1"
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = toset(local.worker_ips)
  depends_on = [
    talos_machine_configuration_apply.controlplane,
  ]

  client_configuration        = local.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker[each.value].machine_configuration
  endpoint                    = "127.0.0.1:${local.node_api_ports[each.value]}"
  node                        = "127.0.0.1"
}

# --- Wait for CP static IP after reboot ---

resource "null_resource" "wait_for_static_ip" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  triggers = {
    cp_apply = join(",", [for k, v in talos_machine_configuration_apply.controlplane : v.id])
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for control plane static IP ${local.cluster_endpoint_ip}:50000..."
      timeout 300 bash -c \
        'until nc -zw3 ${local.cluster_endpoint_ip} 50000 2>/dev/null; do sleep 5; done' \
        || { echo "ERROR: ${local.cluster_endpoint_ip}:50000 not reachable after 5 min"; exit 1; }
      echo "${local.cluster_endpoint_ip}:50000 reachable"
    EOT
  }
}

# --- Bootstrap etcd ---

resource "talos_machine_bootstrap" "this" {
  depends_on = [null_resource.wait_for_static_ip]

  client_configuration = local.client_configuration
  node                 = local.cluster_endpoint_ip
  endpoint             = local.cluster_endpoint_ip
}

# --- Retrieve kubeconfig ---

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = local.client_configuration
  node                 = local.cluster_endpoint_ip
}
