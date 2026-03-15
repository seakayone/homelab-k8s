variable "argocd_admin_password" {
  type      = string
  sensitive = true
}

variable "argocd_repo_url" {
  type = string
}

variable "argocd_repo_url_internal" {
  type = string
}

variable "argocd_repo_username" {
  type      = string
  sensitive = true
}

variable "argocd_repo_password" {
  type      = string
  sensitive = true
}
