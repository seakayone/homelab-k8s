# NFS Persistent Storage for Talos K8s Cluster

## Overview

Add an NFS server as an LXC container on Proxmox, reachable from the Talos K8s cluster, with dynamic persistent volume provisioning via the NFS CSI driver.

## LXC Container (OpenTofu)

- **Resource**: `proxmox_virtual_environment_container`
- **ID**: 2000
- **Hostname**: `nfs-server`
- **OS Template**: Debian 12 (Bookworm) standard
- **Resources**: 1 CPU core, 512 MB RAM, 20 GB disk on `local-lvm`
- **Network**: `vmbr0`, static IP `192.168.178.200/24`, gateway `192.168.178.1`
- **NFS Export**: `/export/k8s` shared to `192.168.178.0/24` with `rw,no_subtree_check,no_root_squash`

### Provisioning

After container creation, a `terraform_data` resource with `local-exec` provisioner runs commands via `pct exec 2000` through SSH to the Proxmox host:

1. `apt-get update && apt-get install -y nfs-kernel-server`
2. Create `/export/k8s` directory
3. Write `/etc/exports`
4. `exportfs -ra && systemctl enable --now nfs-kernel-server`

## Kubernetes Integration

### NFS CSI Driver

- **Chart**: `csi-driver-nfs` from `https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts`
- **Deployed via**: ArgoCD Helm Application
- **Runs in**: `kube-system` namespace

### StorageClass

- **Name**: `nfs`
- **Provisioner**: `nfs.csi.k8s.io`
- **Server**: `192.168.178.200`
- **Share**: `/export/k8s`
- **Reclaim Policy**: Delete
- **Default**: Yes (so existing PVCs like Mealie's work automatically)

## ArgoCD App-of-Apps

```
apps/
  nfs-csi/
    application.yaml          # Helm-based ArgoCD app for CSI driver + StorageClass

manifests/
  nfs-csi/
    storageclass.yaml         # StorageClass pointing at NFS server
```

## File Changes Summary

| File | Action | Purpose |
|------|--------|---------|
| `proxmox/nfs.tf` | New | LXC container + NFS provisioning |
| `proxmox/variables.tf` | Edit | Add `network_gateway` variable |
| `variables.tf` | Edit | Add `network_gateway` variable (root) |
| `main.tf` | Edit | Pass `network_gateway` to module |
| `apps/nfs-csi/application.yaml` | New | ArgoCD app for NFS CSI driver |
| `manifests/nfs-csi/storageclass.yaml` | New | NFS StorageClass |
| `scripts/destroy.sh` | Edit | Add container ID 2000 to cleanup |

## Notes

- Talos Linux includes NFS kernel modules by default; no node-level changes needed.
- The CSI driver handles NFS mounting from within pods.
- Dynamic provisioning creates subdirectories under `/export/k8s` per PVC.
