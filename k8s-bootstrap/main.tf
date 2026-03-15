terraform {
  required_version = ">= 1.11.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

resource "helm_release" "tailscale_operator" {
  name             = "tailscale-operator"
  repository       = "https://pkgs.tailscale.com/helmcharts"
  chart            = "tailscale-operator"
  namespace        = "tailscale"
  create_namespace = true
  wait             = true

  set_sensitive {
    name  = "oauth.clientId"
    value = var.tailscale_oauth_client_id
  }

  set_sensitive {
    name  = "oauth.clientSecret"
    value = var.tailscale_oauth_client_secret
  }

  set {
    name  = "apiServerProxyConfig.mode"
    value = "true"
  }
}

resource "kubectl_manifest" "tailscale_egress_proxy_group" {
  yaml_body = yamlencode({
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "ProxyGroup"
    metadata = {
      name = "egress"
    }
    spec = {
      type     = "Egress"
      replicas = 1
    }
  })

  depends_on = [helm_release.tailscale_operator]
}

resource "kubectl_manifest" "tailscale_egress_git_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "ts-git-organa-one"
      namespace = "tailscale"
      annotations = {
        "tailscale.com/proxy-group"  = "egress"
        "tailscale.com/tailnet-fqdn" = "git.organa.one"
      }
    }
    spec = {
      type         = "ExternalName"
      externalName = "placeholder"
    }
  })

  depends_on = [helm_release.tailscale_operator]
}

resource "null_resource" "tailscale_kubeconfig" {
  depends_on = [helm_release.tailscale_operator]

  provisioner "local-exec" {
    command = <<-EOT
      tailscale configure kubeconfig tailscale-operator
      echo "Triggering Tailscale HTTPS cert provisioning..."
      curl -sk -o /dev/null https://tailscale-operator.lungfish-ide.ts.net/version || true
      echo "Waiting for valid TLS cert..."
      until curl -sf -o /dev/null https://tailscale-operator.lungfish-ide.ts.net/version; do
        sleep 5
      done
    EOT
  }
}
