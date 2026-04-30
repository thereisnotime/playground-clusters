output "control_plane_ips" {
  description = "Static IP addresses of control plane nodes"
  value       = local.control_plane_ips
}

output "worker_ips" {
  description = "Static IP addresses of worker nodes"
  value       = local.worker_ips
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL"
  value       = local.cluster_endpoint
}
