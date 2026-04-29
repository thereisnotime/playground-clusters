locals {
  # Control planes: 192.168.56.10, .11, .12, …
  # Workers:        192.168.56.20, .21, .22, …

  control_plane_ips       = [for i in range(var.control_plane_count) : "192.168.56.${10 + i}"]
  worker_ips              = [for i in range(var.worker_count) : "192.168.56.${20 + i}"]
  all_node_ips            = concat(local.control_plane_ips, local.worker_ips)
  cluster_endpoint        = "https://${local.control_plane_ips[0]}:6443"
  additional_cp_ips       = slice(local.control_plane_ips, 1, length(local.control_plane_ips))

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

  ssh = "ssh -i ${pathexpand(var.ssh_key_path)} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
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

# --- Bootstrap first control plane ---

resource "null_resource" "rke2_server_init" {
  depends_on = [null_resource.ssh_ready]

  triggers = {
    server_ip    = local.control_plane_ips[0]
    rke2_version = var.rke2_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      IP="${local.control_plane_ips[0]}"
      NAME="${local.node_hostnames[local.control_plane_ips[0]]}"

      echo "==> Installing RKE2 server on $IP..."
      ${local.ssh} vagrant@$IP "curl -sfL https://get.rke2.io | sudo env INSTALL_RKE2_VERSION=${var.rke2_version} sh -"

      echo "==> Writing config on $IP..."
      printf '%s\n' \
        "node-name: $NAME" \
        "node-ip: $IP" \
        "advertise-address: $IP" \
        "tls-san:" \
        "  - $IP" \
        | ${local.ssh} vagrant@$IP "sudo tee /etc/rancher/rke2/config.yaml > /dev/null"

      echo "==> Starting RKE2 server on $IP..."
      ${local.ssh} vagrant@$IP "sudo systemctl enable rke2-server && sudo systemctl start rke2-server"

      echo "==> Waiting for RKE2 server to become ready..."
      timeout ${var.node_boot_timeout} bash -c \
        'until ${local.ssh} vagrant@'"$IP"' \
            "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes 2>/dev/null | grep -q Ready" \
          2>/dev/null; do sleep 10; done' \
        || { echo "ERROR: RKE2 server on $IP not ready after ${var.node_boot_timeout}s"; exit 1; }

      echo "==> RKE2 server ready on $IP"
    EOT
  }
}

# --- Join additional control planes (only when control_plane_count > 1) ---

resource "null_resource" "rke2_server_join" {
  for_each   = toset(local.additional_cp_ips)
  depends_on = [null_resource.rke2_server_init]

  triggers = {
    server_ip    = each.value
    rke2_version = var.rke2_version
    init_id      = null_resource.rke2_server_init.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      INIT_IP="${local.control_plane_ips[0]}"
      IP="${each.value}"
      NAME="${local.node_hostnames[each.value]}"
      TOKEN=$(${local.ssh} vagrant@$INIT_IP "sudo cat /var/lib/rancher/rke2/server/node-token")

      echo "==> Installing RKE2 server on $IP..."
      ${local.ssh} vagrant@$IP "curl -sfL https://get.rke2.io | sudo env INSTALL_RKE2_VERSION=${var.rke2_version} sh -"

      echo "==> Writing config on $IP..."
      printf '%s\n' \
        "server: https://$INIT_IP:9345" \
        "token: $TOKEN" \
        "node-name: $NAME" \
        "node-ip: $IP" \
        "advertise-address: $IP" \
        "tls-san:" \
        "  - $IP" \
        | ${local.ssh} vagrant@$IP "sudo tee /etc/rancher/rke2/config.yaml > /dev/null"

      echo "==> Starting RKE2 server on $IP..."
      ${local.ssh} vagrant@$IP "sudo systemctl enable rke2-server && sudo systemctl start rke2-server"
      echo "==> RKE2 server join started on $IP"
    EOT
  }
}

# --- Join workers ---

resource "null_resource" "rke2_agents" {
  for_each = toset(local.worker_ips)
  depends_on = [
    null_resource.rke2_server_init,
    null_resource.rke2_server_join,
  ]

  triggers = {
    worker_ip    = each.value
    rke2_version = var.rke2_version
    init_id      = null_resource.rke2_server_init.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      INIT_IP="${local.control_plane_ips[0]}"
      IP="${each.value}"
      NAME="${local.node_hostnames[each.value]}"
      TOKEN=$(${local.ssh} vagrant@$INIT_IP "sudo cat /var/lib/rancher/rke2/server/node-token")

      echo "==> Installing RKE2 agent on $IP..."
      ${local.ssh} vagrant@$IP "curl -sfL https://get.rke2.io | sudo env INSTALL_RKE2_TYPE=agent INSTALL_RKE2_VERSION=${var.rke2_version} sh -"

      echo "==> Writing config on $IP..."
      printf '%s\n' \
        "server: https://$INIT_IP:9345" \
        "token: $TOKEN" \
        "node-name: $NAME" \
        "node-ip: $IP" \
        | ${local.ssh} vagrant@$IP "sudo tee /etc/rancher/rke2/config.yaml > /dev/null"

      echo "==> Starting RKE2 agent on $IP..."
      ${local.ssh} vagrant@$IP "sudo systemctl enable rke2-agent && sudo systemctl start rke2-agent"
      echo "==> RKE2 agent started on $IP"
    EOT
  }
}

# --- Fetch kubeconfig (replace 127.0.0.1 with CP static IP) ---

resource "null_resource" "kubeconfig" {
  depends_on = [
    null_resource.rke2_server_init,
    null_resource.rke2_agents,
  ]

  triggers = {
    init_id = null_resource.rke2_server_init.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/.rke2-configs
      ${local.ssh} vagrant@${local.control_plane_ips[0]} \
        "sudo cat /etc/rancher/rke2/rke2.yaml" \
        | sed 's|https://127.0.0.1:6443|${local.cluster_endpoint}|g' \
        > ${path.module}/.rke2-configs/kubeconfig
      chmod 600 ${path.module}/.rke2-configs/kubeconfig
      echo "kubeconfig -> ${path.module}/.rke2-configs/kubeconfig"
    EOT
  }
}
