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
