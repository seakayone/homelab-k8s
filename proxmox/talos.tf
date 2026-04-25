locals {
  cp_static_ip      = "192.168.178.201"
  worker_static_ips = ["192.168.178.202"]

  cp_ip            = local.cp_static_ip
  worker_ips       = local.worker_static_ips
  cluster_endpoint = "https://${local.cp_ip}:6443"

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

    rewrite name exact authentik.lungfish-ide.ts.net authentik-egress-clusterip.tailscale.svc.cluster.local

    hosts {
        192.168.178.87 git.organa.one
        fallthrough
    }
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
  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "ens18"
            dhcp      = false
            addresses = ["${local.cp_static_ip}/24"]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.network_gateway
            }]
          }]
          nameservers = [var.network_gateway]
        }
      }
      cluster = {
        inlineManifests = [
          {
            name = "coredns-config"
            contents = yamlencode({
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
          }
        ]
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  count = 1

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = local.worker_ips[count.index]
  config_patches = [
    yamlencode({
      machine = {
        network = {
          interfaces = [{
            interface = "ens18"
            dhcp      = false
            addresses = ["${local.worker_static_ips[count.index]}/24"]
            routes = [{
              network = "0.0.0.0/0"
              gateway = var.network_gateway
            }]
          }]
          nameservers = [var.network_gateway]
        }
      }
    })
  ]
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
