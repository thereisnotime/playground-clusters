locals {
  # Control planes: 192.168.56.10, .11, .12, …
  # Workers:        192.168.56.20, .21, .22, …

  control_plane_ips = [for i in range(var.control_plane_count) : "192.168.56.${10 + i}"]
  worker_ips        = [for i in range(var.worker_count) : "192.168.56.${20 + i}"]
  all_node_ips      = concat(local.control_plane_ips, local.worker_ips)
  cluster_endpoint  = "https://${local.control_plane_ips[0]}:6443"
  additional_cp_ips = slice(local.control_plane_ips, 1, length(local.control_plane_ips))

  node_hostnames = merge(
    { for i, ip in local.control_plane_ips : ip => "cp-${i + 1}" },
    { for i, ip in local.worker_ips : ip => "worker-${i + 1}" }
  )

  nodes_config = concat(
    [for ip in local.control_plane_ips : {
      name   = local.node_hostnames[ip]
      ip     = ip
      cpus   = var.control_plane_cpus
      memory = var.control_plane_memory
    }],
    [for ip in local.worker_ips : {
      name   = local.node_hostnames[ip]
      ip     = ip
      cpus   = var.worker_cpus
      memory = var.worker_memory
    }]
  )

  ssh      = "ssh -i ${pathexpand(var.ssh_key_path)} -o StrictHostKeyChecking=no -o ConnectTimeout=10"
  k8s_minor = join(".", slice(split(".", var.kubernetes_version), 0, 2))
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

# --- Install containerd + kubeadm/kubelet/kubectl on every node ---

resource "null_resource" "node_prep" {
  for_each   = toset(local.all_node_ips)
  depends_on = [null_resource.ssh_ready]

  triggers = {
    node_id            = null_resource.vm[local.node_hostnames[each.value]].id
    kubernetes_version = var.kubernetes_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      IP="${each.value}"
      NAME="${local.node_hostnames[each.value]}"

      echo "==> Preparing node $IP ($NAME)..."

      # Disable swap
      ${local.ssh} vagrant@$IP "sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab"

      # Kernel modules
      ${local.ssh} vagrant@$IP "printf 'overlay\nbr_netfilter\n' | sudo tee /etc/modules-load.d/k8s.conf && sudo modprobe overlay && sudo modprobe br_netfilter"

      # sysctl
      ${local.ssh} vagrant@$IP "printf 'net.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\nnet.ipv4.ip_forward=1\n' | sudo tee /etc/sysctl.d/k8s.conf && sudo sysctl --system"

      # containerd from Docker repo
      ${local.ssh} vagrant@$IP "sudo apt-get install -y ca-certificates curl gnupg"
      ${local.ssh} vagrant@$IP "sudo install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && sudo chmod a+r /etc/apt/keyrings/docker.gpg"
      ${local.ssh} vagrant@$IP "echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable' | sudo tee /etc/apt/sources.list.d/docker.list"
      ${local.ssh} vagrant@$IP "sudo apt-get update && sudo apt-get install -y containerd.io"
      ${local.ssh} vagrant@$IP "sudo mkdir -p /etc/containerd && containerd config default | sudo tee /etc/containerd/config.toml && sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml && sudo systemctl restart containerd"

      # kubeadm / kubelet / kubectl
      ${local.ssh} vagrant@$IP "sudo apt-get install -y apt-transport-https gpg"
      ${local.ssh} vagrant@$IP "curl -fsSL https://pkgs.k8s.io/core:/stable:/v${local.k8s_minor}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
      ${local.ssh} vagrant@$IP "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${local.k8s_minor}/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list"
      ${local.ssh} vagrant@$IP "sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl && sudo apt-mark hold kubelet kubeadm kubectl"

      # Pin node IP so kubelet registers the static host-only address
      ${local.ssh} vagrant@$IP "echo 'KUBELET_EXTRA_ARGS=--node-ip=$IP' | sudo tee /etc/default/kubelet && sudo systemctl daemon-reload && sudo systemctl enable kubelet"

      echo "==> Node $IP ready"
    EOT
  }
}

# --- Init first control plane ---

resource "null_resource" "kubeadm_init" {
  depends_on = [null_resource.node_prep]

  triggers = {
    server_ip          = local.control_plane_ips[0]
    kubernetes_version = var.kubernetes_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      IP="${local.control_plane_ips[0]}"
      NAME="${local.node_hostnames[local.control_plane_ips[0]]}"

      echo "==> Running kubeadm init on $IP..."
      ${local.ssh} vagrant@$IP "sudo kubeadm init \
        --apiserver-advertise-address=$IP \
        --control-plane-endpoint=$IP:6443 \
        --pod-network-cidr=10.244.0.0/16 \
        --node-name=$NAME \
        --kubernetes-version=v${var.kubernetes_version} \
        --upload-certs"

      echo "==> Installing Flannel CNI..."
      ${local.ssh} vagrant@$IP \
        "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://github.com/flannel-io/flannel/releases/download/v${var.flannel_version}/kube-flannel.yml"

      echo "==> Waiting for control plane node to become Ready..."
      timeout ${var.node_boot_timeout} bash -c \
        'until ${local.ssh} vagrant@'"$IP"' \
            "sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes 2>/dev/null | grep -q Ready" \
          2>/dev/null; do sleep 10; done' \
        || { echo "ERROR: kubeadm CP on $IP not ready after ${var.node_boot_timeout}s"; exit 1; }

      echo "==> Control plane ready on $IP"
    EOT
  }
}

# --- Join additional control planes (only when control_plane_count > 1) ---

resource "null_resource" "kubeadm_cp_join" {
  for_each   = toset(local.additional_cp_ips)
  depends_on = [null_resource.kubeadm_init]

  triggers = {
    server_ip          = each.value
    kubernetes_version = var.kubernetes_version
    init_id            = null_resource.kubeadm_init.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      INIT_IP="${local.control_plane_ips[0]}"
      IP="${each.value}"
      NAME="${local.node_hostnames[each.value]}"

      JOIN_CMD=$(${local.ssh} vagrant@$INIT_IP "sudo kubeadm token create --print-join-command 2>/dev/null")
      CERT_KEY=$(${local.ssh} vagrant@$INIT_IP "sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1")

      echo "==> Joining control plane $IP..."
      ${local.ssh} vagrant@$IP \
        "sudo $JOIN_CMD --control-plane --certificate-key $CERT_KEY --node-name=$NAME --apiserver-advertise-address=$IP"
      echo "==> Control plane join started on $IP"
    EOT
  }
}

# --- Join workers ---

resource "null_resource" "kubeadm_worker_join" {
  for_each = toset(local.worker_ips)
  depends_on = [
    null_resource.kubeadm_init,
    null_resource.kubeadm_cp_join,
  ]

  triggers = {
    worker_ip          = each.value
    kubernetes_version = var.kubernetes_version
    init_id            = null_resource.kubeadm_init.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      INIT_IP="${local.control_plane_ips[0]}"
      IP="${each.value}"
      NAME="${local.node_hostnames[each.value]}"

      JOIN_CMD=$(${local.ssh} vagrant@$INIT_IP "sudo kubeadm token create --print-join-command 2>/dev/null")

      echo "==> Joining worker $IP..."
      ${local.ssh} vagrant@$IP "sudo $JOIN_CMD --node-name=$NAME"
      echo "==> Worker $IP joined"
    EOT
  }
}

# --- Fetch kubeconfig ---

resource "null_resource" "kubeconfig" {
  depends_on = [
    null_resource.kubeadm_init,
    null_resource.kubeadm_worker_join,
  ]

  triggers = {
    init_id = null_resource.kubeadm_init.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/.kubeadm-configs
      ${local.ssh} vagrant@${local.control_plane_ips[0]} \
        "sudo cat /etc/kubernetes/admin.conf" \
        > ${path.module}/.kubeadm-configs/kubeconfig
      chmod 600 ${path.module}/.kubeadm-configs/kubeconfig
      echo "kubeconfig -> ${path.module}/.kubeadm-configs/kubeconfig"
    EOT
  }
}
