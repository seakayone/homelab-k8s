locals {
  cp_ip            = [for addr in flatten(proxmox_virtual_environment_vm.talos_control_plane.ipv4_addresses) : addr if addr != "127.0.0.1" && !startswith(addr, "169.254.") && !startswith(addr, "10.244.")][0]
  worker_ips       = [for vm in proxmox_virtual_environment_vm.talos_worker : [for addr in flatten(vm.ipv4_addresses) : addr if addr != "127.0.0.1" && !startswith(addr, "169.254.") && !startswith(addr, "10.244.")][0]]
  cluster_endpoint = "https://${local.cp_ip}:6443"
}

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  machine_type     = "controlplane"
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  machine_type     = "worker"
  cluster_endpoint = local.cluster_endpoint
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = concat([local.cp_ip], local.worker_ips)
  endpoints            = [local.cp_ip]
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = local.cp_ip
}

resource "talos_machine_configuration_apply" "worker" {
  count = 1

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = local.worker_ips[count.index]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ip

  depends_on = [talos_machine_configuration_apply.controlplane]
}

data "talos_cluster_health" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [local.cp_ip]
  worker_nodes         = local.worker_ips
  endpoints            = [local.cp_ip]

  timeouts = {
    read = "10m"
  }

  depends_on = [talos_machine_bootstrap.this]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ip

  depends_on = [data.talos_cluster_health.this]
}
