variable "cluster_name" {
  description = "Name of the kubeadm cluster"
  type        = string
  default     = "kubeadm-playground"
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
  default     = 4096
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

variable "kubernetes_version" {
  description = "Kubernetes version to install (format: <major>.<minor>.<patch>)"
  type        = string
  default     = "1.32.3"
}

variable "flannel_version" {
  description = "Flannel CNI version to install"
  type        = string
  default     = "0.26.7"
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
  description = "Seconds to wait for SSH or kubeadm readiness before failing"
  type        = number
  default     = 600
}

variable "ssh_key_path" {
  description = "Path to the SSH private key used to reach nodes"
  type        = string
  default     = "~/.vagrant.d/insecure_private_key"
}
