locals {
  # Control planes: 192.168.56.10, .11, .12, …
  # Workers:        192.168.56.20, .21, .22, …

  control_plane_ips = [for i in range(var.control_plane_count) : "192.168.56.${10 + i}"]
  worker_ips        = [for i in range(var.worker_count) : "192.168.56.${20 + i}"]
  all_node_ips      = concat(local.control_plane_ips, local.worker_ips)
  cluster_endpoint  = "https://${local.control_plane_ips[0]}:6443"

  node_hostnames = merge(
    { for i, ip in local.control_plane_ips : ip => "cp-${i + 1}" },
    { for i, ip in local.worker_ips : ip => "worker-${i + 1}" }
  )

  nodes_config = [for ip in local.all_node_ips : {
    name   = local.node_hostnames[ip]
    ip     = ip
    cpus   = var.node_cpus
    memory = var.node_memory
  }]

  k0sctl_config = {
    apiVersion = "k0sctl.k0sproject.io/v1beta1"
    kind       = "Cluster"
    metadata   = { name = var.cluster_name }
    spec = {
      hosts = concat(
        [for ip in local.control_plane_ips : {
          role = "controller"
          ssh = {
            address = ip
            user    = "vagrant"
            port    = 22
            keyPath = pathexpand(var.ssh_key_path)
          }
        }],
        [for ip in local.worker_ips : {
          role = "worker"
          ssh = {
            address = ip
            user    = "vagrant"
            port    = 22
            keyPath = pathexpand(var.ssh_key_path)
          }
        }]
      )
      k0s = { version = var.k0s_version }
    }
  }
}

# --- k0sctl config (generated from locals, not committed) ---

resource "local_file" "k0sctl_config" {
  content         = yamlencode(local.k0sctl_config)
  filename        = "${path.module}/k0sctl.yaml"
  file_permission = "0600"
}

# --- Wait for SSH on each node ---

resource "null_resource" "ssh_ready" {
  depends_on = [null_resource.vm]

  triggers = {
    node_ids = join(",", [for k, v in null_resource.vm : v.id])
  }

  provisioner "local-exec" {
    command = <<-EOT
      for ip in ${join(" ", local.all_node_ips)}; do
        echo "Waiting for SSH on $ip..."
        timeout ${var.node_boot_timeout} bash -c \
          'until nc -zw2 '"$ip"' 22 2>/dev/null; do sleep 5; done' \
          || { echo "ERROR: SSH on $ip not ready after ${var.node_boot_timeout}s"; exit 1; }
        echo "$ip:22 ready"
      done
    EOT
  }
}

# --- Apply k0s to all nodes ---

resource "null_resource" "k0sctl_apply" {
  depends_on = [null_resource.ssh_ready, local_file.k0sctl_config]

  triggers = {
    k0sctl_config = local_file.k0sctl_config.content
  }

  provisioner "local-exec" {
    command = "k0sctl apply --config ${path.module}/k0sctl.yaml"
  }
}
