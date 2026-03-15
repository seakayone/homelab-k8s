output "vm_name" {
  value = proxmox_virtual_environment_vm.talos_control_plane.name
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.talos_control_plane.vm_id
}

output "worker_vm_names" {
  value = proxmox_virtual_environment_vm.talos_worker[*].name
}

output "worker_vm_ids" {
  value = proxmox_virtual_environment_vm.talos_worker[*].vm_id
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "kubernetes_host" {
  value = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
}

output "kubernetes_client_certificate" {
  value     = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate
  sensitive = true
}

output "kubernetes_client_key" {
  value     = talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key
  sensitive = true
}

output "kubernetes_ca_certificate" {
  value     = talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate
  sensitive = true
}
