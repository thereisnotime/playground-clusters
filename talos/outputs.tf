output "talosconfig" {
  description = "Talos client configuration (talosconfig)"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubeconfig for the cluster"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

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

