variable "cluster_name" {
  description = "Name of the k3s cluster"
  type        = string
  default     = "k3s-playground"
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

variable "k3s_version" {
  description = "k3s version (format: v<k8s-version>+k3s<patch>)"
  type        = string
  default     = "v1.32.3+k3s1"
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
  description = "Seconds to wait for SSH or k3s readiness before failing"
  type        = number
  default     = 600
}

variable "ssh_key_path" {
  description = "Path to the SSH private key used to reach nodes"
  type        = string
  default     = "~/.vagrant.d/insecure_private_key"
}
