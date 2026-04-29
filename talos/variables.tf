variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "talos-playground"
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

variable "node_cpus" {
  description = "vCPUs per node"
  type        = number
  default     = 2
}

variable "node_memory" {
  description = "Memory per node in MB"
  type        = number
  default     = 2048
}

variable "talos_version" {
  description = "Talos version — must match the Vagrant box (theorigamicorporation/talos-virtualbox 2.0.0 = Talos v1.12.7)"
  type        = string
  default     = "v1.12.7"
}

variable "kubernetes_version" {
  description = "Kubernetes version (Talos v1.12.7 ships with K8s v1.33.x)"
  type        = string
  default     = "v1.33.1"
}

variable "box_name" {
  description = "Vagrant box name for cluster nodes"
  type        = string
  default     = "theorigamicorporation/talos-virtualbox"
}

variable "box_version" {
  description = "Vagrant box version — must match var.talos_version"
  type        = string
  default     = "2.0.0"
}

variable "ca_validity_hours" {
  description = "Validity period in hours for all generated CA certificates"
  type        = number
  default     = 87600 # 10 years
}

variable "node_boot_timeout" {
  description = "Seconds to wait for each node's Talos API before failing"
  type        = number
  default     = 300
}
