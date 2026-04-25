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
  description = "Talos version to target — must match the Vagrant box (theorigamicorporation/talos-virtualbox 1.0.0 = Talos v1.12.7)"
  type        = string
  default     = "v1.12.7"
}

variable "node_api_ports" {
  description = "Map of node IP to localhost port forwarded to Talos API (port 50000) — must match Vagrantfile"
  type        = map(number)
  default = {
    "192.168.56.10" = 50001
    "192.168.56.11" = 50002
    "192.168.56.12" = 50003
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to deploy (Talos v1.12.7 ships with K8s v1.33.x)"
  type        = string
  default     = "v1.33.1"
}
