locals {
  # --- IP and port layout ---
  # Control planes: 192.168.56.10, .11, .12, … (up to 10)
  # Workers:        192.168.56.20, .21, .22, …
  # Ports:          sequential from 50001 (CPs first, then workers)

  control_plane_ips   = [for i in range(var.control_plane_count) : "192.168.56.${10 + i}"]
  worker_ips          = [for i in range(var.worker_count) : "192.168.56.${20 + i}"]
  all_node_ips        = concat(local.control_plane_ips, local.worker_ips)
  cluster_endpoint_ip = local.control_plane_ips[0]

  # Cluster endpoint points to the first CP. For a playground this is fine —
  # etcd replicates across all CPs regardless. For production HA you'd put a
  # load balancer or kube-vip VIP here instead.
  cluster_endpoint = "https://${local.cluster_endpoint_ip}:6443"

  node_api_ports = { for i, ip in local.all_node_ips : ip => 50001 + i }

  # --- Node identity ---
  node_hostnames = merge(
    { for i, ip in local.control_plane_ips : ip => "cp-${i + 1}" },
    { for i, ip in local.worker_ips : ip => "worker-${i + 1}" }
  )

  # Vagrantfile node list (consumed by machines.tf templatefile)
  nodes_config = [for ip in local.all_node_ips : {
    name       = local.node_hostnames[ip]
    ip         = ip
    talos_port = local.node_api_ports[ip]
    cpus       = var.node_cpus
    memory     = var.node_memory
  }]

  # --- Machine config patches ---

  # Static IP on host-only NIC (PCI slot 8, busPath 0000:00:08.0).
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

  # Unique kubelet node name — avoids hostname collisions when all VMs clone
  # from the same box and get the same hardware-derived OS hostname.
  kubelet_patch = { for ip in local.all_node_ips : ip => yamlencode({
    machine = {
      kubelet = {
        extraArgs = { "hostname-override" = local.node_hostnames[ip] }
      }
    }
  }) }

}

# --- Secrets (PKI, tokens, etc.) ---

resource "talos_machine_secrets" "this" {}

# --- Machine configs ---

data "talos_machine_configuration" "controlplane" {
  for_each = toset(local.control_plane_ips)

  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.network_patch[each.value], local.kubelet_patch[each.value]]
}

data "talos_machine_configuration" "worker" {
  for_each = toset(local.worker_ips)

  cluster_name       = var.cluster_name
  machine_type       = "worker"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.network_patch[each.value], local.kubelet_patch[each.value]]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips
  nodes                = local.all_node_ips
}

# --- Write machine configs to local files ---
# talos_machine_configuration_apply uses the Go TLS stack which fails to verify
# Talos's Ed25519 CA cert. We use talosctl apply-config --insecure instead.

resource "local_file" "controlplane_config" {
  for_each = toset(local.control_plane_ips)
  content  = data.talos_machine_configuration.controlplane[each.value].machine_configuration
  filename = "${path.module}/.talos-configs/controlplane-${replace(each.value, ".", "-")}.yaml"
}

resource "local_file" "worker_config" {
  for_each = toset(local.worker_ips)
  content  = data.talos_machine_configuration.worker[each.value].machine_configuration
  filename = "${path.module}/.talos-configs/worker-${replace(each.value, ".", "-")}.yaml"
}

# --- Apply configs via talosctl --insecure (maintenance mode) ---
# --nodes 127.0.0.1:<port> is the only form talosctl respects for port overrides.

resource "null_resource" "apply_controlplane" {
  for_each = toset(local.control_plane_ips)
  depends_on = [
    null_resource.talos_api_ready,
    local_file.controlplane_config,
  ]

  triggers = {
    config = sha256(data.talos_machine_configuration.controlplane[each.value].machine_configuration)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Applying controlplane config to ${each.value} via 127.0.0.1:${local.node_api_ports[each.value]}..."
      out=$(talosctl apply-config \
        --insecure \
        --nodes 127.0.0.1:${local.node_api_ports[each.value]} \
        --file "${path.module}/.talos-configs/controlplane-${replace(each.value, ".", "-")}.yaml" \
        2>&1)
      echo "$out"
      if echo "$out" | grep -qi "^error\|refused\|unavailable\|failed to\|rpc error"; then
        echo "ERROR: talosctl apply-config failed for ${each.value}" >&2
        exit 1
      fi
      echo "Controlplane config applied to ${each.value}"
    EOT
  }
}

resource "null_resource" "apply_worker" {
  for_each = toset(local.worker_ips)
  depends_on = [
    null_resource.apply_controlplane,
    local_file.worker_config,
  ]

  triggers = {
    config = sha256(data.talos_machine_configuration.worker[each.value].machine_configuration)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Applying worker config to ${each.value} via 127.0.0.1:${local.node_api_ports[each.value]}..."
      out=$(talosctl apply-config \
        --insecure \
        --nodes 127.0.0.1:${local.node_api_ports[each.value]} \
        --file "${path.module}/.talos-configs/worker-${replace(each.value, ".", "-")}.yaml" \
        2>&1)
      echo "$out"
      if echo "$out" | grep -qi "^error\|refused\|unavailable\|failed to\|rpc error"; then
        echo "ERROR: talosctl apply-config failed for ${each.value}" >&2
        exit 1
      fi
      echo "Worker config applied to ${each.value}"
    EOT
  }
}

# --- Wait for VIP after config apply + reboot ---
# Nodes reboot after receiving config. Wait for the VIP on port 50000 of the
# first CP (kube-vip claims the VIP once Talos is configured).

resource "null_resource" "wait_for_static_ip" {
  depends_on = [null_resource.apply_controlplane]

  triggers = {
    cp_apply = join(",", [for k, v in null_resource.apply_controlplane : v.id])
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

# --- Bootstrap etcd on the first control plane ---

resource "talos_machine_bootstrap" "this" {
  depends_on = [null_resource.wait_for_static_ip]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cluster_endpoint_ip
  endpoint             = local.cluster_endpoint_ip
}

# --- Retrieve kubeconfig ---

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cluster_endpoint_ip
}
