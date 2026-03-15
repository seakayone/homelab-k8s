terraform {
  required_version = ">= 1.11.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = var.argocd_admin_password
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "tailscale"
  }

  set {
    name  = "server.ingress.tls[0].hosts[0]"
    value = "argocd"
  }

  set {
    name  = "configs.repositories.argocd-repo.url"
    value = var.argocd_repo_url_internal
  }

  set {
    name  = "configs.repositories.argocd-repo.type"
    value = "git"
  }

  set {
    name  = "configs.repositories.argocd-repo.insecure"
    value = "true"
  }

  set_sensitive {
    name  = "configs.repositories.argocd-repo.username"
    value = var.argocd_repo_username
  }

  set_sensitive {
    name  = "configs.repositories.argocd-repo.password"
    value = var.argocd_repo_password
  }

  values = [yamlencode({
    server = {
      additionalApplications = [{
        name      = "root"
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.argocd_repo_url_internal
          targetRevision = "HEAD"
          path           = "apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }]
    }
    configs = {
      projects = {
        default = {
          description = "Default project"
          sourceRepos = [var.argocd_repo_url_internal]
          destinations = [{
            server    = "https://kubernetes.default.svc"
            namespace = "*"
          }]
          clusterResourceWhitelist = [{
            group = "*"
            kind  = "*"
          }]
        }
      }
    }
  })]
}
