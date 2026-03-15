terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.51.1"
    }
  }
}

provider "proxmox" {
  endpoint = var.endpoint
  api_token = var.api_token
  username = var.tf_username
  #password = var.tf_password
  ssh {
    agent    = true
    username = var.ssh_agent_username
    #password = var.ssh_agent_password
    private_key = file(var.ssh_private_key_path)
    node {
      name    = var.target_node_name
      address = var.target_node_ip
      port    = var.target_node_port
    }
  }
}
