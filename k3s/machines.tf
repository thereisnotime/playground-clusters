locals {
  node_map = { for node in local.nodes_config : node.name => node }
}

resource "local_file" "node_vagrantfile" {
  for_each = local.node_map

  content = templatefile("${path.module}/Vagrantfile.tpl", {
    name        = each.value.name
    ip          = each.value.ip
    cpus        = each.value.cpus
    memory      = each.value.memory
    box_name    = var.box_name
    box_version = var.box_version
  })
  filename = "${path.module}/.vagrant-nodes/${each.key}/Vagrantfile"
}

resource "null_resource" "vm" {
  for_each = local.node_map

  triggers = {
    vagrantfile = local_file.node_vagrantfile[each.key].content
  }

  provisioner "local-exec" {
    command     = "vagrant up"
    working_dir = "${path.module}/.vagrant-nodes/${each.key}"
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "vagrant destroy -f; rm -rf '${path.module}/.vagrant-nodes/${each.key}'"
    working_dir = "${path.module}/.vagrant-nodes/${each.key}"
    on_failure  = continue
  }
}
