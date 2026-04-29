variable "cluster_name" {
  description = "Name of the k0s cluster"
  type        = string
  default     = "k0s-playground"
}

variable "control_plane_count" {
  description = "Number of control plane nodes (IPs assigned from 192.168.56.10 upward)"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes (IPs assigned from 192.168.56.20 upward)"
  type        = number
  default     = 2
}

variable "control_plane_cpus" {
  description = "vCPUs per control plane node"
  type        = number
  default     = 2
}

variable "control_plane_memory" {
  description = "Memory per control plane node in MB"
  type        = number
  default     = 2048
}

variable "worker_cpus" {
  description = "vCPUs per worker node"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Memory per worker node in MB"
  type        = number
  default     = 2048
}

variable "k0s_version" {
  description = "k0s version to install (format: v<k8s-version>+k0s.<patch>)"
  type        = string
  default     = "v1.33.1+k0s.0"
}

variable "box_name" {
  description = "Vagrant box name for cluster nodes"
  type        = string
  default     = "bento/debian-12"
}

variable "box_version" {
  description = "Vagrant box version — leave empty for latest"
  type        = string
  default     = ""
}

variable "node_boot_timeout" {
  description = "Seconds to wait for SSH on each node before failing"
  type        = number
  default     = 120
}

variable "ssh_key_path" {
  description = "Path to the SSH private key used by k0sctl to reach nodes"
  type        = string
  default     = "~/.vagrant.d/insecure_private_key"
}
