# Adding a New App

This guide walks through adding a new application to the cluster. The pattern is: manifests in `manifests/<app>/`, an ArgoCD Application in `apps/<app>/application.yaml`, optional Sealed Secrets for credentials, a Tailscale Ingress for access, and an entry in the Homepage dashboard.

See [Example: it-tools](#example-it-tools) at the bottom for a complete worked example.

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

## 2. Add the ArgoCD Application

Create `apps/<app>/application.yaml`:

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
    repoURL: https://forgejo.argocd.svc.cluster.local/christian/homelab-k8s.git
    targetRevision: main
    path: manifests/<app>
  destination:
    server: https://kubernetes.default.svc
    namespace: <app>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

The root app (`apps/root.yaml`) recurses the entire `apps/` directory, so ArgoCD picks this up automatically on the next sync — no other registration needed.

---

## 3. Sealed Secrets

If the app needs credentials (passwords, API keys, tokens), use Sealed Secrets so the encrypted values can be committed safely to Git.

**Step 1 — Write a plain Secret to a temp location (never inside the repo):**

```yaml
# /tmp/<app>-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: <app>-secrets
  namespace: <app>
type: Opaque
stringData:
  MY_PASSWORD: "a-strong-random-value"
  API_KEY: "another-secret"
```

**Step 2 — Seal it:**

```bash
just seal-secret /tmp/<app>-secret.yaml > manifests/<app>/sealed-secret.yaml
```

**Step 3 — Delete the plain file:**

```bash
rm /tmp/<app>-secret.yaml
```

**Step 4 — Commit `sealed-secret.yaml`.** The in-cluster controller decrypts it into a regular `Secret` with the same `name` and `namespace`.

Reference the secret from the deployment:

```yaml
env:
  - name: MY_PASSWORD
    valueFrom:
      secretKeyRef:
        name: <app>-secrets
        key: MY_PASSWORD
```

> Sealed Secrets are scoped to a specific name + namespace. A secret sealed for `<app>/<app>-secrets` cannot be used elsewhere. If the controller key is ever lost, restore it first with `just backup-sealed-secrets-key` before deploying the controller on a new cluster.

---

## 4. Tailscale Ingress

To expose the app on the Tailnet, create `manifests/<app>/ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <app>
  namespace: <app>
  annotations:
    tailscale.com/funnel: "false"
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

---

## 5. Add to Homepage

Edit `manifests/homepage/config/services.yaml` and append an entry under the `Homelab` group:

```yaml
- Homelab:
    # ... existing entries ...
    - My App:
        href: https://<hostname>.lungfish-ide.ts.net
        description: Short description
        icon: <app>.png   # or a URL; see https://gethomepage.dev/configs/services/
```

The Homepage ConfigMap is generated from this file via Kustomize `configMapGenerator`. Committing the change produces a new ConfigMap hash, which triggers a rolling restart of the Homepage pod so the new entry appears immediately.

Icons are resolved from the [Dashboard Icons](https://github.com/walkxcode/dashboard-icons) library by name. Use a full URL if the app is not in that library:

```yaml
icon: https://example.com/logo.png
```

---

## Example: it-tools

[it-tools](https://github.com/CorentinTh/it-tools) is a stateless web app (collection of developer utilities) — no database, no persistent storage, no secrets. It is the simplest possible app to add.

**Files created:**

```
manifests/it-tools/
  deployment.yaml
  service.yaml
  ingress.yaml
apps/it-tools/
  application.yaml
```

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

### `apps/it-tools/application.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: it-tools
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://forgejo.argocd.svc.cluster.local/christian/homelab-k8s.git
    targetRevision: main
    path: manifests/it-tools
  destination:
    server: https://kubernetes.default.svc
    namespace: it-tools
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Homepage entry (`manifests/homepage/config/services.yaml`)

```yaml
- IT-Tools:
    href: https://it-tools.lungfish-ide.ts.net
    description: Collection of handy online tools for developers
    icon: it-tools.png
```

The app is accessible at `https://it-tools.lungfish-ide.ts.net` once ArgoCD syncs.
