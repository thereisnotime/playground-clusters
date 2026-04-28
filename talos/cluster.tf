locals {
  cluster_endpoint = "https://${var.cluster_endpoint_ip}:6443"
  all_node_ips     = concat(var.control_plane_ips, var.worker_ips)

  # Map from IP to short hostname so each node gets a unique identity.
  node_hostnames = merge(
    { for idx, ip in var.control_plane_ips : ip => "cp-${idx + 1}" },
    { for idx, ip in var.worker_ips : ip => "worker-${idx + 1}" }
  )

  # Patch that sets a static IP on the host-only NIC for a given node.
  # Uses deviceSelector.busPath to match by PCI address (0000:00:08.0) rather than
  # interface name — VirtualBox always places NIC 2 on PCI slot 8 regardless of
  # what name the OS assigns (eth1, enp0s8, etc.). dhcp: false prevents the DHCP
  # lease from overriding the static address.
  network_patch = { for ip in local.all_node_ips : ip => yamlencode({
    machine = {
      network = {
        interfaces = [{
          deviceSelector = {
            busPath = "0000:00:08.0"
          }
          dhcp      = false
          addresses = ["${ip}/24"]
        }]
      }
    }
  }) }

  # Per-node kubelet hostname-override patch.
  # Talos auto-generates OS hostnames from hardware IDs; since all VMs are cloned
  # from the same box they get the same generated name. Setting hostname-override in
  # the kubelet makes each node register under a unique name in Kubernetes without
  # touching the OS hostname (which would conflict with the provider's HostnameConfig
  # document and produce a "static hostname already set" error).
  kubelet_patch = { for ip in local.all_node_ips : ip => yamlencode({
    machine = {
      kubelet = {
        extraArgs = {
          "hostname-override" = local.node_hostnames[ip]
        }
      }
    }
  }) }

}

# --- Secrets (PKI, tokens, etc.) ---

resource "talos_machine_secrets" "this" {}

# --- Machine configs (network patch baked in per node) ---

data "talos_machine_configuration" "controlplane" {
  for_each = toset(var.control_plane_ips)

  cluster_name       = var.cluster_name
  machine_type       = "controlplane"
  cluster_endpoint   = local.cluster_endpoint
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.network_patch[each.value], local.kubelet_patch[each.value]]
}

data "talos_machine_configuration" "worker" {
  for_each = toset(var.worker_ips)

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
  endpoints            = var.control_plane_ips
  nodes                = local.all_node_ips
}

# --- Write machine configs to local files ---
# talos_machine_configuration_apply uses the Go TLS stack which fails to verify
# Talos's Ed25519 CA cert (x509 Ed25519 verification failure in Go). We use
# talosctl apply-config --insecure instead, which is the correct approach for
# maintenance mode and skips TLS verification entirely.

resource "local_file" "controlplane_config" {
  for_each = toset(var.control_plane_ips)
  content  = data.talos_machine_configuration.controlplane[each.value].machine_configuration
  filename = "${path.module}/.talos-configs/controlplane-${replace(each.value, ".", "-")}.yaml"
}

resource "local_file" "worker_config" {
  for_each = toset(var.worker_ips)
  content  = data.talos_machine_configuration.worker[each.value].machine_configuration
  filename = "${path.module}/.talos-configs/worker-${replace(each.value, ".", "-")}.yaml"
}

# --- Apply configs via talosctl --insecure (maintenance mode) ---
# Pass the NAT-forwarded port directly via --nodes 127.0.0.1:<port> — this is
# the only form talosctl respects for port overrides in insecure mode.
# talosctl exits 0 even on failure, so we grep output for error indicators.

resource "null_resource" "apply_controlplane" {
  for_each = toset(var.control_plane_ips)
  depends_on = [
    null_resource.talos_api_ready,
    local_file.controlplane_config,
  ]

  triggers = {
    config = sha256(data.talos_machine_configuration.controlplane[each.value].machine_configuration)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Applying controlplane config to ${each.value} via 127.0.0.1:${var.node_api_ports[each.value]}..."
      out=$(talosctl apply-config \
        --insecure \
        --nodes 127.0.0.1:${var.node_api_ports[each.value]} \
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
  for_each = toset(var.worker_ips)
  depends_on = [
    null_resource.apply_controlplane,
    local_file.worker_config,
  ]

  triggers = {
    config = sha256(data.talos_machine_configuration.worker[each.value].machine_configuration)
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Applying worker config to ${each.value} via 127.0.0.1:${var.node_api_ports[each.value]}..."
      out=$(talosctl apply-config \
        --insecure \
        --nodes 127.0.0.1:${var.node_api_ports[each.value]} \
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

# --- Wait for static IP after config apply + reboot ---
# Nodes reboot after receiving their config. Wait for the control plane static IP
# to be reachable on the Talos API port before bootstrapping etcd.

resource "null_resource" "wait_for_static_ip" {
  depends_on = [null_resource.apply_controlplane]

  triggers = {
    cp_apply = join(",", [for k, v in null_resource.apply_controlplane : v.id])
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for control plane static IP ${var.cluster_endpoint_ip}:50000..."
      timeout 300 bash -c \
        'until nc -zw3 ${var.cluster_endpoint_ip} 50000 2>/dev/null; do sleep 5; done' \
        || { echo "ERROR: ${var.cluster_endpoint_ip}:50000 not reachable after 5 min"; exit 1; }
      echo "${var.cluster_endpoint_ip}:50000 reachable"
    EOT
  }
}

# --- Bootstrap etcd on the first control plane ---

resource "talos_machine_bootstrap" "this" {
  depends_on = [null_resource.wait_for_static_ip]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.cluster_endpoint_ip
  endpoint             = var.cluster_endpoint_ip
}

# --- Retrieve kubeconfig ---

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.cluster_endpoint_ip
}
