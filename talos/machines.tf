resource "vagrant_vm" "cluster" {
  vagrantfile_dir = path.module
  env = {
    VAGRANT_EXPERIMENTAL = "none_communicator"
  }
  get_ports = false
}

# Talos boots into maintenance mode asynchronously after vagrant up exits.
# Wait for the API on each forwarded port before letting the talos resources run.
resource "null_resource" "talos_api_ready" {
  depends_on = [vagrant_vm.cluster]

  triggers = {
    cluster_id = vagrant_vm.cluster.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      for port in ${join(" ", values(var.node_api_ports))}; do
        echo "Waiting for Talos API on 127.0.0.1:$port..."
        timeout 300 bash -c \
          'until nc -zw2 127.0.0.1 '"$port"' 2>/dev/null; do sleep 5; done' \
          || { echo "ERROR: Talos API on port $port not ready after 5 min"; exit 1; }
        echo "127.0.0.1:$port ready"
      done
    EOT
  }
}
