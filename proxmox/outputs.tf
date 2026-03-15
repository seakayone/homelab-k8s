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
