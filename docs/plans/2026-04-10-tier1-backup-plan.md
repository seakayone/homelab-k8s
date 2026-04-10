# Tier 1 Backup Plan — Application-Level Backups

**Date**: 2026-04-10  
**Scope**: Mealie, Vikunja, Miniflux, Forgejo  
**Goal**: Scheduled, consistent, GitOps-managed backups of all stateful application data, stored on NFS, without introducing new operators or external dependencies.

---

## 1. Data Inventory

| App | State Type | PVC(s) | Size | Secret |
|---|---|---|---|---|
| **Mealie** | SQLite at `/app/data` (DB + recipe images) | `mealie-data` | 2Gi | none needed |
| **Vikunja** | PostgreSQL DB | `vikunja-postgres-data` | 2Gi | `vikunja-secrets/database-password` |
| **Vikunja** | File attachments at `/app/vikunja/files` | `vikunja-files` | 5Gi | none needed |
| **Miniflux** | PostgreSQL DB | `miniflux-postgres-data` | 2Gi | `miniflux-secrets/database-password` |
| **Forgejo** | PostgreSQL DB | `forgejo-postgres-data` | 5Gi | `forgejo-secrets/database-password` |
| **Forgejo** | Git repos + LFS at `/var/lib/gitea` | `forgejo-data` | 10Gi | none needed |
| **Forgejo** | App config at `/etc/gitea` | `forgejo-config` | 100Mi | none needed |

Miniflux has **no file PVC** — all state lives in PostgreSQL only.  
Mealie has **no PostgreSQL** — all state is SQLite inside the data PVC.

---

## 2. Architecture Decisions

### CronJobs live in each app's own namespace

The backup CronJob for each app runs **in the same namespace as the app**. This is the most important design choice because:
- Kubernetes Secrets are namespace-scoped. A backup job in `miniflux` can directly reference `miniflux-secrets` without any cross-namespace RBAC gymnastics.
- The backup manifests (`backup-pvc.yaml`, `backup-cronjob.yaml`) are placed alongside the existing app manifests in `manifests/<app>/`. ArgoCD already syncs these directories — no new ArgoCD Application objects are needed.

### pg_dump over the network for PostgreSQL

For Vikunja, Miniflux, and Forgejo, the CronJob runs a `postgres:18` container (same image already used for init containers) and connects to the PostgreSQL **Service** (`<app>-postgres.<namespace>.svc.cluster.local:5432`). The PostgreSQL data PVC (`*-postgres-data`) is **never mounted** by the backup job — directly copying a live PostgreSQL data directory produces a corrupt, inconsistent backup. `pg_dump` over the network is safe while the database is running.

### tar + gzip for file PVCs

For Mealie (`mealie-data`) and Vikunja (`vikunja-files`) and Forgejo (`forgejo-data`, `forgejo-config`), the backup job mounts the source PVC alongside the backup PVC and runs `tar czf`. 

**SQLite note**: Mealie's SQLite database is written in WAL mode by default, which makes live file copies safe. The tar backup captures the SQLite DB file, WAL file, and all recipe images in one consistent pass.

**Forgejo note**: Forgejo has a built-in `forgejo dump` CLI, but it requires running inside the Forgejo container and produces a single monolithic ZIP mixing DB + files. Separating `pg_dump` and `tar` is simpler to implement as standard CronJobs and gives more granular restore options. The trade-off is a brief window between the DB dump and the files tar where a new commit could be made — acceptable for a homelab.

### Per-namespace backup PVC

Each app gets a dedicated backup PVC (`<app>-backup`) in its own namespace, backed by the **`nfs-backup` StorageClass** (`organa.local` / `192.168.178.39`, share `/volume1/k8s-backup`). This NAS share is backed up to Glacier, providing offsite durability for free as part of the NAS setup.

The `nfs-backup` StorageClass uses `reclaimPolicy: Retain` — deleting a backup PVC (e.g. via `argocd app delete`) will **not** delete the underlying NFS data. This is intentional: backup data must survive cluster operations.

The existing `nfs` StorageClass (`192.168.178.200:/export/k8s`, `reclaimPolicy: Delete`) remains the default for all app PVCs and is unchanged.

Backups accumulate in the PVC as timestamped files. A retention script in the CronJob prunes files older than 7 days.

### PVC access modes — a critical consideration

The app file PVCs (`mealie-data`, `vikunja-files`, `forgejo-data`, `forgejo-config`) are currently declared as **ReadWriteOnce (RWO)**. Kubernetes allows multiple pods to mount the same RWO PVC only if they are scheduled on **the same node**. Since this cluster has a single worker node today, all pods land on the same node and concurrent mounts work in practice.

However, for correctness the file PVCs that need to be shared with a backup pod **should be changed to ReadWriteMany (RWX)**. The NFS CSI driver fully supports RWX. This is the right access mode for NFS-backed volumes that may be read by more than one pod.

**The PVCs requiring access mode migration are:**
- `mealie-data` → RWX
- `vikunja-files` → RWX
- `forgejo-data` → RWX
- `forgejo-config` → RWX

**Migration path** (causes brief downtime per app):
1. Scale app deployment to 0
2. Delete the PVC (data on NFS is NOT deleted by the NFS CSI driver on PVC deletion by default — verify `reclaimPolicy: Retain` is in effect)
3. Re-apply PVC with `ReadWriteMany`
4. The NFS CSI driver will bind a new PV to the same underlying NFS path if `storageClassName: nfs` and the same name are used — or the path will need to be re-specified. **Verify the reclaim policy before doing this.**

> **Action before implementation**: check the NFS CSI StorageClass reclaim policy with `kubectl get storageclass nfs -o yaml`. The existing `nfs` StorageClass uses `reclaimPolicy: Delete` — confirmed in `apps/nfs-csi/application.yaml`. For PVCs on the `nfs` StorageClass, deleting and recreating the PVC will lose the NFS data. Test the RWO constraint first with the single-node assumption before migrating PVCs to RWX.

---

## 3. Backup Schedule & Retention

Staggered daily schedule to avoid NFS contention:

| App | Schedule (UTC) | Retention |
|---|---|---|
| Miniflux | `0 1 * * *` (01:00) | 7 daily backups |
| Vikunja | `15 1 * * *` (01:15) | 7 daily backups |
| Mealie | `30 1 * * *` (01:30) | 7 daily backups |
| Forgejo | `45 1 * * *` (01:45) | 7 daily backups |

Retention is enforced by the CronJob itself: after writing the new backup file, delete any files older than 7 days in the backup directory.

**Estimated backup storage per day:**

| App | Estimated compressed size |
|---|---|
| Miniflux DB dump | ~5–20 MB |
| Vikunja DB dump | ~5–20 MB |
| Vikunja files tar | variable (user uploads) |
| Mealie data tar | ~50–200 MB (recipe images) |
| Forgejo DB dump | ~10–50 MB |
| Forgejo repos + config tar | ~100 MB–several GB (depends on repos hosted) |

---

## 4. Files to Create

All new files are placed alongside existing app manifests. No new ArgoCD apps needed.

```
manifests/
  mealie/
    backup-pvc.yaml            ← NFS PVC for mealie backup files (5Gi)
    backup-cronjob.yaml        ← tar+gzip of mealie-data PVC → mealie-backup PVC
  vikunja/
    backup-pvc.yaml            ← NFS PVC for vikunja backup files (5Gi)
    backup-cronjob.yaml        ← pg_dump + tar of vikunja-files → vikunja-backup PVC
  miniflux/
    backup-pvc.yaml            ← NFS PVC for miniflux backup files (2Gi)
    backup-cronjob.yaml        ← pg_dump miniflux → miniflux-backup PVC
  forgejo/
    backup-pvc.yaml            ← NFS PVC for forgejo backup files (15Gi)
    backup-cronjob.yaml        ← pg_dump + tar of forgejo-data + forgejo-config → forgejo-backup PVC
```

**No new RBAC or ServiceAccounts are needed.** The CronJobs use the default ServiceAccount (they only need access to Secrets that are already in their namespace, which default SA can read).

Wait — actually the default ServiceAccount cannot read Secrets by default in modern Kubernetes. A dedicated **ServiceAccount + Role + RoleBinding** is required per namespace to allow the CronJob pod to read the `*-secrets` Secret. These are added to the same backup manifests.

Updated files:
```
manifests/
  mealie/
    backup-pvc.yaml
    backup-cronjob.yaml        ← no secret access needed (SQLite, no DB password)
  vikunja/
    backup-pvc.yaml
    backup-cronjob.yaml        ← needs vikunja-secrets → RBAC inline in same file
  miniflux/
    backup-pvc.yaml
    backup-cronjob.yaml        ← needs miniflux-secrets → RBAC inline in same file
  forgejo/
    backup-pvc.yaml
    backup-cronjob.yaml        ← needs forgejo-secrets → RBAC inline in same file
```

---

## 5. CronJob Design Detail

### Miniflux — pg_dump only

```
Container:   postgres:18
Command:     pg_dump --host miniflux-postgres --username miniflux --dbname miniflux
             | gzip > /backup/miniflux-$(date +%Y%m%d-%H%M%S).sql.gz
             find /backup -name "*.sql.gz" -mtime +7 -delete
Env:         PGPASSWORD from miniflux-secrets/database-password
Mounts:      miniflux-backup → /backup
```

### Vikunja — pg_dump + files tar

Two steps in one CronJob (sequential containers or a shell script):
```
Step 1 — DB:
  Container:   postgres:18
  Command:     pg_dump | gzip > /backup/vikunja-db-$(date +%Y%m%d-%H%M%S).sql.gz
  Env:         PGPASSWORD from vikunja-secrets/database-password
  Mounts:      vikunja-backup → /backup

Step 2 — Files:
  Container:   busybox or alpine
  Command:     tar czf /backup/vikunja-files-$(date +%Y%m%d-%H%M%S).tar.gz -C /files .
               find /backup -name "vikunja-files-*.tar.gz" -mtime +7 -delete
  Mounts:      vikunja-files → /files (READ)
               vikunja-backup → /backup
```

Both steps are combined into a single init+main container pattern or a single shell script in one container image.

### Mealie — files tar only

```
Container:   busybox or alpine
Command:     tar czf /backup/mealie-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
             find /backup -name "mealie-data-*.tar.gz" -mtime +7 -delete
Mounts:      mealie-data → /data (READ)
             mealie-backup → /backup
```

No secrets needed.

### Forgejo — pg_dump + repos + config tar

```
Step 1 — DB:
  Container:   postgres:18
  Command:     pg_dump | gzip > /backup/forgejo-db-$(date +%Y%m%d-%H%M%S).sql.gz
               find /backup -name "forgejo-db-*.sql.gz" -mtime +7 -delete
  Env:         PGPASSWORD from forgejo-secrets/database-password
  Mounts:      forgejo-backup → /backup

Step 2 — Data + Config:
  Container:   busybox or alpine
  Command:     STAMP=$(date +%Y%m%d-%H%M%S)
               tar czf /backup/forgejo-data-${STAMP}.tar.gz -C /data .
               tar czf /backup/forgejo-config-${STAMP}.tar.gz -C /config .
               find /backup -name "forgejo-data-*.tar.gz" -mtime +7 -delete
               find /backup -name "forgejo-config-*.tar.gz" -mtime +7 -delete
  Mounts:      forgejo-data   → /data   (READ)
               forgejo-config → /config (READ)
               forgejo-backup → /backup
```

---

## 6. Restore Procedures

### PostgreSQL restore (Vikunja / Miniflux / Forgejo)

```bash
# 1. Scale down the application deployment
kubectl scale deployment <app> -n <namespace> --replicas=0
kubectl scale deployment <app>-postgres -n <namespace> --replicas=0

# 2. Scale up postgres alone
kubectl scale deployment <app>-postgres -n <namespace> --replicas=1

# 3. Run a restore Job (one-shot pod) in the namespace:
#    - drop and recreate the database
#    - gunzip | psql from the chosen backup file on the backup PVC

# 4. Scale postgres back down, then scale app back up
kubectl scale deployment <app>-postgres -n <namespace> --replicas=1
kubectl scale deployment <app> -n <namespace> --replicas=1
```

A `just restore-db <app> <backup-filename>` task will be provided that automates steps 1–4 by running a one-shot Job manifest.

### File PVC restore (Vikunja files / Mealie data / Forgejo repos+config)

```bash
# 1. Scale down the application
kubectl scale deployment <app> -n <namespace> --replicas=0

# 2. Run a restore Job that:
#    - mounts the backup PVC (read) and the target PVC (write)
#    - clears the target directory
#    - extracts the chosen tar.gz into the target directory

# 3. Scale app back up
kubectl scale deployment <app> -n <namespace> --replicas=1
```

A `just restore-files <app> <backup-filename>` task will automate this.

### Full app restore (after cluster rebuild)

1. `just destroy-and-setup` → cluster running
2. `kubectl apply -f sealed-secrets-key-backup.yaml` → sealed-secrets controller picks up key
3. ArgoCD syncs → namespaces, deployments, PVCs, and backup PVCs all created (empty)
4. Copy backup files from wherever they are stored (USB drive, offsite — Tier 2) into the backup PVCs
5. Run restore jobs for DB + files per app
6. Verify applications are healthy

---

## 7. Just Tasks to Add

```
just backup-now <app>                  # Manually trigger a CronJob run immediately
just list-backups <app>                # List files on the app's backup PVC
just restore-db <app> <file>           # Run one-shot DB restore Job from backup PVC
just restore-files <app> <file>        # Run one-shot files restore Job from backup PVC
```

`backup-now` creates a one-off Job from the CronJob spec using `kubectl create job --from=cronjob/<app>-backup`.

---

## 8. What This Plan Does NOT Cover

- **Offsite copy**: Backup PVCs are on the NAS (`organa.local`), which is already backed up to Glacier — so offsite durability is provided automatically. A formal Tier 2 plan for rclone is not needed unless an additional copy target is desired.
- **Monitoring/alerting**: No alerting if a backup CronJob fails. A future improvement is a PrometheusRule or an AlertManager rule watching for failed Jobs in the backup-related namespaces.
- **Backup verification**: Backups are not automatically tested for restorability. Periodic manual restore drills are recommended.
- **Loki / Prometheus data**: Considered ephemeral — no backup planned.
- **Terraform state**: Local state file. Back up the directory or use remote state (out of scope here).
