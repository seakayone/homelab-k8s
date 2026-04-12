locals {
  # Standard Talos/Kubernetes CoreDNS Corefile with an added rewrite rule
  # that redirects git.organa.one to the in-cluster Tailscale egress proxy
  # (egress-git-organa.tailscale.svc.cluster.local), so ArgoCD can reach the
  # tailnet-only Gitea instance without the nodes being on the tailnet.
  #
  # Traffic flow:
  #   pod → CoreDNS rewrite → egress proxy ClusterIP
  #       → Tailscale proxy pod → 100.65.186.120:443 (Traefik)
  #       → Traefik (Host: git.organa.one) → Gitea
  #
  # The proxy is L4, so TLS SNI and the cert hostname (git.organa.one) are
  # preserved end-to-end.
  coredns_corefile = <<-EOT
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        log . {
            class error
        }
        prometheus :9153
        rewrite name git.organa.one egress-git-organa.tailscale.svc.cluster.local
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
        }
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30 {
           disable success cluster.local
           disable denial cluster.local
        }
        loop
        reload
        loadbalance
    }
    EOT

  coredns_configmap = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "coredns"
      namespace = "kube-system"
    }
    data = {
      Corefile = local.coredns_corefile
    }
  })

  coredns_patch = yamlencode({
    cluster = {
      inlineManifests = [
        {
          name     = "coredns-organa-rewrite"
          contents = local.coredns_configmap
        }
      ]
    }
  })
}
