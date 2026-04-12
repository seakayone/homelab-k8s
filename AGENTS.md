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
just argocd-sync-app <app>         # Sync root app and wait for <app> to be healthy
just backup-now <app>              # Manually trigger a backup job (mealie, vikunja, miniflux, authentik)
just list-backups <app>            # List backup files for an app
just miniflux-create-admin         # Create the initial Miniflux admin user
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
        ├── variables.tf    — Input variables
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
  ├── miniflux/
  │     └── application.yaml               — Miniflux RSS reader from manifests/miniflux/
  ├── vikunja/
  │     └── application.yaml               — Vikunja task manager from manifests/vikunja/
  ├── authentik/
  │     └── application.yaml               — Authentik identity provider from manifests/authentik/
  ├── homepage/
  │     └── application.yaml               — Homepage dashboard from manifests/homepage/
  ├── it-tools/
  │     └── application.yaml               — IT-Tools utilities from manifests/it-tools/
  ├── sealed-secrets/
  │     └── application.yaml               — Sealed-secrets controller (Bitnami Helm chart v2.18.4)
  ├── nfs-csi/
  │     └── application.yaml               — NFS CSI driver (default StorageClass "nfs")
  └── nfs-nas/
        └── application.yaml               — NFS backup StorageClass "nfs-backup" (NAS-backed)

manifests/
  ├── argocd/
  │     ├── install.yaml                   — Full ArgoCD installation (do not hand-edit)
  │     ├── apply.sh                       — Script to apply ArgoCD manifests
  │     ├── repositories.yaml              — ArgoCD repository configuration
  │     └── gitorgana-repo-sealed-secret.yaml — Sealed secret for repo credentials
  ├── mealie/                              — Deployment, Service, PVC, Tailscale Ingress, backup CronJob
  ├── miniflux/                            — Deployment, Service, PVC, Tailscale Ingress, backup CronJob, SealedSecret
  ├── vikunja/                             — Deployment, Service, PVC, Tailscale Ingress, backup CronJob, SealedSecret
  ├── authentik/                           — Deployment, Service, PVC, Tailscale Ingress, backup CronJob, SealedSecret
  ├── homepage/                            — Deployment, Service, Tailscale Ingress, RBAC, Kustomize, config/
  ├── it-tools/                            — Deployment, Service, Tailscale Ingress
  ├── nfs-nas/
  │     └── storageclass.yaml              — StorageClass "nfs-backup" (NAS at 192.168.178.39:/volume1/k8s-backup)
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
- **ArgoCD syncs from**: `https://github.com/seakayone/homelab-k8s.git` using app-of-apps pattern (`apps/` → `manifests/`).
- **ArgoCD UI**: `https://argocd.lungfish-ide.ts.net` via Tailscale Ingress.
- **Grafana UI**: `https://grafana.lungfish-ide.ts.net` via Tailscale Ingress.
- **Mealie UI**: `https://mealie.lungfish-ide.ts.net` via Tailscale Ingress.
- **Miniflux UI**: `https://miniflux.lungfish-ide.ts.net` via Tailscale Ingress.
- **Vikunja UI**: `https://vikunja.lungfish-ide.ts.net` via Tailscale Ingress.
- **Authentik UI**: `https://authentik.lungfish-ide.ts.net` via Tailscale Ingress.
- **Homepage UI**: `https://hp.lungfish-ide.ts.net` via Tailscale Ingress.
- **IT-Tools UI**: `https://it-tools.lungfish-ide.ts.net` via Tailscale Ingress.
- **Tailscale operator**: Deployed via Kustomize with API server proxy mode.
- **NFS storage**: Default StorageClass `nfs` backed by NFS server VM at 192.168.178.200:/export/k8s. Used by Loki (3Gi), Prometheus (5Gi), Grafana (2Gi), Mealie PVC, and other app PVCs.
- **NFS backup storage**: StorageClass `nfs-backup` backed by NAS at 192.168.178.39:/volume1/k8s-backup. Used by backup CronJobs for Mealie, Miniflux, Vikunja, and Authentik.
- **Observability stack**: kube-prometheus-stack (Prometheus + Grafana + Alertmanager) + Loki + Grafana Alloy for log collection.
- **Sealed Secrets**: Bitnami sealed-secrets controller in `kube-system` namespace. Allows encrypting Kubernetes Secrets so they can be safely committed to Git. ArgoCD-managed via Helm chart.
- Terraform state is local (not remote). `destroy.sh` wipes state files directly.

## Sealed Secrets

[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) encrypts Kubernetes Secrets client-side so they can be stored in Git. The controller in-cluster decrypts them back into regular Secrets.

### Workflow

1. **Create a plain Kubernetes Secret** (do NOT commit this):
   ```yaml
   # my-secret.yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: my-secret
     namespace: default
   type: Opaque
   stringData:
     password: "super-secret-value"
   ```

2. **Seal it** using the `just` task:
   ```bash
   just seal-secret my-secret.yaml > my-sealed-secret.yaml
   ```
   This runs `kubeseal` against the cluster's controller to produce a `SealedSecret` resource encrypted with the controller's public key.

3. **Commit the SealedSecret** (`my-sealed-secret.yaml`) to Git. ArgoCD syncs it to the cluster, and the controller decrypts it into a regular Secret.

4. **Delete the plain Secret file** — only the sealed version belongs in the repo.

### Key Backup & Restore

The controller's encryption key is critical — if lost, existing SealedSecrets cannot be decrypted.

```bash
# Backup the key (store securely, NEVER commit)
just backup-sealed-secrets-key
# → writes sealed-secrets-key-backup.yaml (gitignored)

# Restore the key (before deploying controller on a new cluster)
kubectl apply -f sealed-secrets-key-backup.yaml
# Then restart the controller to pick up the restored key
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets-controller
```

### Key Details

- **Controller**: `sealed-secrets-controller` in `kube-system` (Helm chart v2.18.4)
- **CLI tool**: `kubeseal` (version managed by `.mise.toml`)
- **Key backup file**: `sealed-secrets-key-backup.yaml` (gitignored)
- Secrets are scoped to a specific name + namespace by default (cannot be reused elsewhere)
