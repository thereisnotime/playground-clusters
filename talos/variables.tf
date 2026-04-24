variable "cluster_name" {
  description = "Name of the Talos cluster"
  type        = string
  default     = "talos-playground"
}

variable "cluster_endpoint_ip" {
  description = "IP of the control plane node used as the cluster endpoint"
  type        = string
  default     = "192.168.56.10"
}

variable "control_plane_ips" {
  description = "IPs of control plane nodes"
  type        = list(string)
  default     = ["192.168.56.10"]
}

variable "worker_ips" {
  description = "IPs of worker nodes"
  type        = list(string)
  default     = ["192.168.56.11", "192.168.56.12"]
}

variable "talos_version" {
  description = "Talos version to target (must match the Vagrant box version)"
  type        = string
  default     = "v1.9.5"
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy"
  type        = string
  default     = "v1.32.3"
}
