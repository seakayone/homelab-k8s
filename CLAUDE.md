# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Homelab Kubernetes infrastructure-as-code: provisions a 3-node Talos Linux cluster on Proxmox with Tailscale networking and ArgoCD for GitOps.

**Stack**: OpenTofu (IaC) · Talos Linux (immutable K8s OS) · Proxmox (hypervisor) · Tailscale (mesh VPN) · ArgoCD (GitOps) · Helm · Just (task runner)

## Commands

All commands use **OpenTofu** (`tofu`), not Terraform. The `just` task runner wraps common workflows:

```bash
just apply              # tofu apply -auto-approve
just kubeconfig         # Extract kubeconfig from tofu state → ~/.kube/config
just talosconfig        # Extract talosconfig from tofu state → ~/.talos/config
just destroy-and-setup  # Full teardown + rebuild pipeline
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
        ├── talos-vms.tf    — 3 Proxmox VMs (1 controlplane @ 2C/2G, 2 workers @ 2C/4G)
        ├── talos.tf        — Talos secrets, machine configs, bootstrap, health check, kubeconfig
        └── main.tf         — proxmox + talos provider config

scripts/
  └── destroy.sh            — Proxmox API calls to stop/delete VMs + clear state

apps/                                            — ArgoCD Application definitions (app-of-apps pattern)
  ├── root.yaml                            — Root app: syncs apps/ folder itself
  └── argocd/
        ├── application.yaml               — ArgoCD self-manages from manifests/argocd/
        └── ingress.yaml                   — Tailscale Ingress → argocd.lungfish-ide.ts.net

manifests/
  ├── argocd/install.yaml                  — Full ArgoCD installation (do not hand-edit)
  └── tailscale-operator/
        ├── operator.yaml                  — Tailscale K8s operator CRDs + deployment
        ├── authproxy-rbac.yaml            — RBAC for API server auth proxy
        ├── kustomization.yaml             — Kustomize: patches + secret generation
        └── apply.sh                       — Kustomize apply with env-based OAuth secrets
```

**Deployment flow**: `tofu apply` → VMs created → Talos bootstrapped → health check (10m timeout) → `just kubeconfig` / `just talosconfig` → deploy operators + ArgoCD → cluster ready.

**Full rebuild**: `just destroy-and-setup` chains destroy → apply → config extraction → operator install → node verification.

## Key Details

- **VM IDs**: controlplane=1000, workers=1010/1011. Talos image: `v1.12.5` from factory.talos.dev.
- **Providers pinned**: `bpg/proxmox` v0.98.1, `siderolabs/talos` v0.10.1.
- **Secrets**: All in `.envrc` via `TF_VAR_*` environment variables (direnv). Never commit `.envrc` or `*.tfvars`.
- **Cluster endpoint**: Dynamically resolved from control plane IP (filters out loopback/link-local/pod CIDRs).
- **ArgoCD syncs from**: `github.com/seakayone/homelab-k8s.git` using app-of-apps pattern (`apps/` → `manifests/`).
- **ArgoCD UI**: `https://argocd.lungfish-ide.ts.net` via Tailscale Ingress.
- **Tailscale operator**: Deployed via Helm with API server proxy mode (`--set apiServerProxyConfig.mode=true`).
- Terraform state is local (not remote). `destroy.sh` wipes state files directly.
