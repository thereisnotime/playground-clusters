# Generate .nodes.json from the computed node topology so the static Vagrantfile
# can pick up any change to control_plane_count / worker_count / node_cpus / node_memory.
resource "local_file" "nodes_json" {
  content = jsonencode({
    box_name    = "theorigamicorporation/talos-virtualbox"
    box_version = "2.0.0"
    nodes       = local.nodes_config
  })
  filename = "${path.module}/.nodes.json"
}

resource "vagrant_vm" "cluster" {
  depends_on      = [local_file.nodes_json]
  vagrantfile_dir = path.module
  env = {
    VAGRANT_EXPERIMENTAL = "none_communicator"
  }
  get_ports = false
}

# Talos boots into maintenance mode asynchronously after vagrant up exits.
# Wait for the API on each forwarded port before applying machine configs.
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
