# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Homelab Kubernetes infrastructure-as-code: provisions a Talos Linux cluster on Proxmox with Tailscale networking and ArgoCD for GitOps.

**Stack**: OpenTofu (IaC) · Talos Linux (immutable K8s OS) · Proxmox (hypervisor) · Tailscale (mesh VPN) · ArgoCD (GitOps) · Helm · Just (task runner)

## Commands

All commands use **OpenTofu** (`tofu`), not Terraform. The `just` task runner wraps common workflows:

```bash
just tf-apply           # tofu apply -auto-approve
just kubeconfig         # Extract kubeconfig from tofu state → ~/.kube/config
just talosconfig        # Extract talosconfig from tofu state → ~/.talos/config
just destroy-and-setup  # Full teardown + rebuild pipeline
just argocd-initial-admin-secret   # Print ArgoCD initial admin password
just argocd-update-admin-secret    # Log in and update ArgoCD admin password
just grafana-initial-admin-secret  # Print Grafana initial admin password
```

Format and validate:
```bash
tofu fmt
tofu validate
tofu plan
```

Tailscale operator deployment:
```bash
bash manifests/tailscale-operator/apply.sh          # apply
bash manifests/tailscale-operator/apply.sh --dry-run # dry-run
```

Destroy:
```bash
bash scripts/destroy.sh          # API-based VM cleanup + state wipe
```

## Architecture

```
Root module (main.tf)
  └── proxmox/ module
        ├── talos-vms.tf    — Talos VMs (controlplane + worker nodes)
        ├── talos.tf        — Talos secrets, machine configs, bootstrap, health check, kubeconfig
        ├── nfs.tf          — Debian NFS server VM (VM ID 2000, IP 192.168.178.200)
        ├── outputs.tf      — Module outputs
        └── main.tf         — proxmox + talos provider config

scripts/
  ├── destroy.sh            — Proxmox API calls to stop/delete VMs + clear state
  └── provision-nfs.sh      — SSH-based NFS server setup (called by nfs.tf provisioner)

apps/                                            — ArgoCD Application definitions (app-of-apps pattern)
  ├── root.yaml                            — Root app: syncs apps/ folder itself
  ├── argocd/
  │     ├── application.yaml               — ArgoCD self-manages from manifests/argocd/
  │     └── ingress.yaml                   — Tailscale Ingress → argocd.lungfish-ide.ts.net
  ├── monitoring/
  │     ├── application.yaml               — kube-prometheus-stack + dashboards configmap
  │     └── ingress.yaml                   — Tailscale Ingress → grafana
  ├── loki/
  │     └── application.yaml               — Loki (SingleBinary, NFS-backed, 30d retention)
  ├── alloy/
  │     └── application.yaml               — Grafana Alloy DaemonSet (pod log collection → Loki)
  ├── mealie/
  │     └── application.yaml               — Mealie recipe manager from manifests/mealie/
  └── nfs-csi/
        └── application.yaml               — NFS CSI driver (default StorageClass "nfs")

manifests/
  ├── argocd/install.yaml                  — Full ArgoCD installation (do not hand-edit)
  ├── mealie/                              — Deployment, Service, PVC, Tailscale Ingress
  ├── monitoring/
  │     └── dashboards-configmap.yaml      — Grafana dashboard ConfigMaps
  └── tailscale-operator/
        ├── operator.yaml                  — Tailscale K8s operator CRDs + deployment
        ├── authproxy-rbac.yaml            — RBAC for API server auth proxy
        ├── kustomization.yaml             — Kustomize: patches + secret generation
        └── apply.sh                       — Kustomize apply with env-based OAuth secrets
```

**Deployment flow**: `tofu apply` → VMs created (Talos nodes + NFS server) → NFS provisioned via SSH → Talos bootstrapped → health check (10m timeout) → `just kubeconfig` / `just talosconfig` → deploy operators + ArgoCD → cluster ready.

**Full rebuild**: `just destroy-and-setup` chains destroy → `tf-apply` → config extraction → Tailscale operator install → node verification.

## Key Details

- **VM IDs**: controlplane=1000, worker=1010. NFS server=2000 (Debian, 192.168.178.200). Talos image: `v1.12.5` from factory.talos.dev.
- **Providers pinned**: `bpg/proxmox` v0.98.1, `siderolabs/talos` v0.10.1.
- **Secrets**: All in `.envrc` via `TF_VAR_*` environment variables (direnv). Never commit `.envrc` or `*.tfvars`.
- **Cluster endpoint**: Dynamically resolved from control plane IP (filters out loopback/link-local/pod CIDRs).
- **ArgoCD syncs from**: `github.com/seakayone/homelab-k8s.git` using app-of-apps pattern (`apps/` → `manifests/`).
- **ArgoCD UI**: `https://argocd.lungfish-ide.ts.net` via Tailscale Ingress.
- **Grafana UI**: `https://grafana.lungfish-ide.ts.net` via Tailscale Ingress.
- **Mealie UI**: `https://mealie.lungfish-ide.ts.net` via Tailscale Ingress.
- **Tailscale operator**: Deployed via Kustomize with API server proxy mode.
- **NFS storage**: Default StorageClass `nfs` backed by NFS server at 192.168.178.200:/export/k8s. Used by Loki (3Gi), Prometheus (5Gi), Grafana (2Gi), Mealie PVC.
- **Observability stack**: kube-prometheus-stack (Prometheus + Grafana + Alertmanager) + Loki + Grafana Alloy for log collection.
- Terraform state is local (not remote). `destroy.sh` wipes state files directly.
