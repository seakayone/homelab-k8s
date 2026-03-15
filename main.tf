terraform {
  required_version = ">= 1.11.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

provider "helm" {
  alias = "talos"
  kubernetes {
    host                   = module.proxmox.kubernetes_host
    client_certificate     = base64decode(module.proxmox.kubernetes_client_certificate)
    client_key             = base64decode(module.proxmox.kubernetes_client_key)
    cluster_ca_certificate = base64decode(module.proxmox.kubernetes_ca_certificate)
  }
}

provider "helm" {
  alias = "tailscale"
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "tailscale-operator.lungfish-ide.ts.net"
  }
}

module "proxmox" {
  source               = "./proxmox"
  endpoint             = var.endpoint
  api_token            = var.api_token
  tf_username          = var.tf_username
  ssh_agent_username   = var.ssh_agent_username
  ssh_private_key_path = var.ssh_private_key_path
  target_node_name              = var.target_node_name
  target_node_ip                = var.target_node_ip
}

module "k8s_bootstrap" {
  source = "./k8s-bootstrap"
  providers = {
    helm = helm.talos
  }
  tailscale_oauth_client_id     = var.tailscale_oauth_client_id
  tailscale_oauth_client_secret = var.tailscale_oauth_client_secret
}

module "k8s" {
  source = "./k8s"
  providers = {
    helm = helm.tailscale
  }
  argocd_admin_password = var.argocd_admin_password
  argocd_repo_url       = var.argocd_repo_url
  argocd_repo_username  = var.argocd_repo_username
  argocd_repo_password  = var.argocd_repo_password

  depends_on = [module.k8s_bootstrap]
}
