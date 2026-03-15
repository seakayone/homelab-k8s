terraform {
  required_version = ">= 1.11.0"
}

module "proxmox" {
  source               = "./proxmox"
  endpoint             = var.endpoint
  api_token            = var.api_token
  tf_username          = var.tf_username
  ssh_agent_username   = var.ssh_agent_username
  ssh_private_key_path = var.ssh_private_key_path
  target_node_name     = var.target_node_name
  target_node_ip       = var.target_node_ip
}
