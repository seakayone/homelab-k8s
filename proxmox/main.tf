terraform {
  required_version = ">= 1.11.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.98.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
  }
}

provider "proxmox" {
  endpoint  = var.endpoint
  api_token = var.api_token
  username  = var.tf_username
  ssh {
    agent       = true
    username    = var.ssh_agent_username
    private_key = file(pathexpand(var.ssh_private_key_path))
    node {
      name    = var.target_node_name
      address = var.target_node_ip
      port    = 22
    }
  }
}
