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
