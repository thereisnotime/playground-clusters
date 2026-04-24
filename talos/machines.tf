resource "vagrant_vm" "cluster" {
  vagrantfile_dir = path.module
  env             = {}
  get_ports       = false
}
