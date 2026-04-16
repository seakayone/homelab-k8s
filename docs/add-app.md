# Adding a New App

This guide walks through adding a new application to the cluster. There are two patterns depending on how the app is packaged:

- **Plain manifests / Kustomize** — put YAML under `manifests/<app>/` and register the app in the `root` ApplicationSet (`apps/root.yaml`). The ApplicationSet generates the `Application` for you.
- **Helm chart** — create a standalone `apps/<app>/application.yaml` that references the chart repo. The ApplicationSet is **not** used here; the file is applied at cluster bootstrap via `manifests/argocd/apply.sh` (`kubectl apply -R -f apps/`).

Both patterns share the remaining steps: optional Sealed Secrets, a Tailscale Ingress for access, and Homepage auto-discovery via Ingress annotations — no separate Homepage config edit needed.

See [Example: it-tools](#example-it-tools) at the bottom for a complete worked example of the plain-manifest pattern, and [Example: Helm chart](#example-helm-chart) for the Helm pattern.

---

## 1. Create the manifests

Create a directory `manifests/<app>/` and add the standard Kubernetes resources.

**Minimum set:**

```
manifests/<app>/
  deployment.yaml
  service.yaml
  pvc.yaml          # if the app needs persistent storage
```

Use the `<app>` namespace consistently across all resources. Example deployment skeleton:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app>
  namespace: <app>
  labels:
    app: <app>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <app>
  template:
    metadata:
      labels:
        app: <app>
    spec:
      containers:
        - name: <app>
          image: <image>:<tag>
          ports:
            - containerPort: <port>
          resources:
            requests:
              memory: 256Mi
              cpu: 100m
            limits:
              memory: 512Mi
```

Storage uses the default `nfs` StorageClass — no `storageClassName` needed in PVCs.

---

## 2. Register the app with ArgoCD

### Plain manifests / Kustomize

Add an entry to the `list` generator in `apps/root.yaml`:

```yaml
- app: <app>
  path: manifests/<app>
```

The `root` ApplicationSet uses this list to generate a matching `Application` for each entry. The generated Application syncs `manifests/<app>/` to a namespace named `<app>`, with `prune`, `selfHeal`, `CreateNamespace=true`, and `ServerSideApply=true` — so you don't need to create an `apps/<app>/application.yaml` file at all for this pattern.

### Helm chart

Create `apps/<app>/application.yaml` referencing the chart directly:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app>
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://charts.example.com/      # chart repo URL
    chart: <chart-name>
    targetRevision: <version>
    helm:
      releaseName: <app>
      values: |
        # chart values here
  destination:
    server: https://kubernetes.default.svc
    namespace: <target-namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

Existing examples: `apps/sealed-secrets/`, `apps/nfs-csi/`, `apps/loki/`, `apps/alloy/`, `apps/monitoring/`, `apps/metrics-server/`.

**Bootstrap:** Helm-based Applications are not created by the ApplicationSet. They are applied to the cluster once via `manifests/argocd/apply.sh` (`kubectl apply -R -f apps/`). On an existing cluster, apply the new Application manually:

```bash
kubectl apply -f apps/<app>/application.yaml
```

After that, ArgoCD owns it and git is the source of truth.

## 3. Sealed Secrets

If the app needs credentials (passwords, API keys, tokens), use Sealed Secrets so the encrypted values can be committed safely to Git.

Refer to the [Sealed Secrets Guide](sealed-secrets.md) for detailed instructions on:
- Creating and sealing secrets.
- Referencing secrets in deployments.
- Backing up and restoring the controller's encryption key.

Briefly:
1. Write a plain Secret to a temporary file (outside the repo).
2. Seal it using `just seal-secret /tmp/secret.yaml > manifests/<app>/sealed-secret.yaml`.
3. Delete the temporary file.
4. Reference the Secret in your deployment.

---

## 4. Tailscale Ingress

To expose the app on the Tailnet, create `manifests/<app>/ingress.yaml`. The `gethomepage.dev/*` annotations make Homepage auto-discover the app and render it as a tile.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>
  namespace: <app>
  annotations:
    tailscale.com/funnel: "false"
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: <Display Name>
    gethomepage.dev/description: Short description
    gethomepage.dev/group: Productivity        # or Infrastructure
    gethomepage.dev/icon: <app>.png            # name from dashboard-icons or full URL
    gethomepage.dev/href: https://<hostname>.lungfish-ide.ts.net
    gethomepage.dev/app: <app>                 # deployment/pod label value for status
    gethomepage.dev/pod-selector: app=<app>    # optional, for pod-level stats
spec:
  ingressClassName: tailscale
  rules:
    - host: <hostname>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <app>
                port:
                  number: <port>
  tls:
    - hosts:
        - <hostname>
```

The `host` value becomes the subdomain: `<hostname>.lungfish-ide.ts.net`. For example, `host: myapp` gives `https://myapp.lungfish-ide.ts.net`.

Set `tailscale.com/funnel: "true"` only if the service must be reachable from the public internet (outside the Tailnet).

**Important:** The Ingress must live under `manifests/<app>/` (synced by the app's ArgoCD Application), not under `apps/<app>/`. Ingresses placed in `apps/<app>/` are not managed by any Application, so annotation changes won't reach the cluster.

---

## 5. Homepage auto-discovery

If you added the `gethomepage.dev/*` annotations in [step 4](#4-tailscale-ingress), no further action is needed — Homepage reads Ingress resources cluster-wide (see `manifests/homepage/config/kubernetes.yaml`) and populates tiles automatically. Groups (`Productivity`, `Infrastructure`, etc.) are created from the `gethomepage.dev/group` annotation; their ordering lives in `manifests/homepage/config/settings.yaml` under `layout:`.

Icons are resolved from the [Dashboard Icons](https://github.com/homarr-labs/dashboard-icons) library by name (`<app>.png`). Use a full URL if the app is not in that library:

```yaml
gethomepage.dev/icon: https://example.com/logo.png
```

Only edit `manifests/homepage/config/services.yaml` for services that have no Ingress (e.g., external links like Proxmox).

---

## Example: it-tools

[it-tools](https://github.com/CorentinTh/it-tools) is a stateless web app (collection of developer utilities) — no database, no persistent storage, no secrets. It is the simplest possible app to add.

**Files created:**

```
manifests/it-tools/
  deployment.yaml
  service.yaml
  ingress.yaml
```

**File edited:** `apps/root.yaml` — one new entry in the list generator. No `apps/it-tools/application.yaml` is needed; the ApplicationSet generates it.

### `manifests/it-tools/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: it-tools
  namespace: it-tools
  labels:
    app: it-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: it-tools
  template:
    metadata:
      labels:
        app: it-tools
    spec:
      containers:
        - name: it-tools
          image: corentinth/it-tools:latest
          ports:
            - containerPort: 80
          resources:
            requests:
              memory: 64Mi
              cpu: 50m
            limits:
              memory: 128Mi
```

### `manifests/it-tools/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: it-tools
  namespace: it-tools
  labels:
    app: it-tools
spec:
  selector:
    app: it-tools
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
```

### `manifests/it-tools/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: it-tools
  namespace: it-tools
  annotations:
    tailscale.com/funnel: "false"
    gethomepage.dev/enabled: "true"
    gethomepage.dev/name: IT-Tools
    gethomepage.dev/description: Collection of handy online tools for developers
    gethomepage.dev/group: Productivity
    gethomepage.dev/icon: it-tools.png
    gethomepage.dev/href: https://it-tools.lungfish-ide.ts.net
    gethomepage.dev/app: it-tools
    gethomepage.dev/pod-selector: app=it-tools
spec:
  ingressClassName: tailscale
  rules:
    - host: it-tools
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: it-tools
                port:
                  number: 80
  tls:
    - hosts:
        - it-tools
```

### `apps/root.yaml` entry

Add to the list under `spec.generators[0].list.elements`:

```yaml
- app: it-tools
  path: manifests/it-tools
```

The `root` ApplicationSet templates this into a full Application pointing at `manifests/it-tools` in the `it-tools` namespace.

The app is accessible at `https://it-tools.lungfish-ide.ts.net` once ArgoCD syncs. Homepage auto-discovers the tile from the Ingress annotations — no changes to `manifests/homepage/config/services.yaml` are required.

---

## Example: Helm chart

[metrics-server](https://github.com/kubernetes-sigs/metrics-server) ships as a Helm chart and isn't user-facing, so it has no Ingress or Homepage tile — just a single `Application` that points at the upstream chart.

**File created:** `apps/metrics-server/application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metrics-server
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://kubernetes-sigs.github.io/metrics-server/
    chart: metrics-server
    targetRevision: 3.12.2
    helm:
      releaseName: metrics-server
      values: |
        args:
          - --kubelet-insecure-tls
          - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
  destination:
    server: https://kubernetes.default.svc
    namespace: kube-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**Bootstrap on the running cluster:**

```bash
kubectl apply -f apps/metrics-server/application.yaml
```

From then on ArgoCD manages the chart release. On a fresh cluster the same file is picked up by `manifests/argocd/apply.sh`'s recursive apply, so no manual step is needed during a full rebuild.

For a user-facing Helm app (e.g. one that ships with an Ingress), you can still annotate the Helm-managed Ingress via chart values — for example kube-prometheus-stack's `grafana.ingress.annotations`. If the chart's Ingress support is too limited, disable it in the chart values and add a standalone `manifests/<app>/ingress.yaml` under a *separate* plain-manifest Application (Kustomize pattern above) pointing at the same namespace.
