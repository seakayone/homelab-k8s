# Sealed Secrets Guide

[Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) encrypts Kubernetes Secrets client-side so they can be safely stored in Git. The controller in-cluster decrypts them back into regular Secrets.

## Workflow

If an app needs credentials (passwords, API keys, tokens), use Sealed Secrets so the encrypted values can be committed safely to Git.

### 1. Create a plain Secret
Write a plain Kubernetes Secret to a temporary location (never inside the repo).

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

### 2. Seal it
Run the `just` task to encrypt the secret with the cluster's public key.

```bash
just seal-secret /tmp/<app>-secret.yaml > manifests/<app>/sealed-secret.yaml
```

### 3. Delete the plain file
Only the sealed version belongs in the repository.

```bash
rm /tmp/<app>-secret.yaml
```

### 4. Reference the Secret
Commit `sealed-secret.yaml`. The in-cluster controller decrypts it into a regular `Secret` with the same `name` and `namespace`. You can then reference it in your deployment:

```yaml
env:
  - name: MY_PASSWORD
    valueFrom:
      secretKeyRef:
        name: <app>-secrets
        key: MY_PASSWORD
```

## Key Backup & Restore

The controller's encryption key is critical — if lost, existing SealedSecrets cannot be decrypted.

### Backup the Key
Store the key securely in a password manager or vault. **NEVER commit the key to Git.**

```bash
just backup-sealed-secrets-key
# → writes sealed-secrets-key-backup.yaml (gitignored)
```

### Restore the Key
Restore the key before deploying the controller on a new cluster.

```bash
kubectl apply -f sealed-secrets-key-backup.yaml
# Then restart the controller to pick up the restored key
kubectl delete pod -n kube-system -l app.kubernetes.io/name=sealed-secrets-controller
```

## Important Details

- **Scoping**: Sealed Secrets are scoped to a specific name + namespace by default. A secret sealed for `myapp/myapp-secrets` cannot be used in another namespace or with another name.
- **Controller**: Managed by ArgoCD via the `sealed-secrets` app (Helm chart v2.18.4) in the `kube-system` namespace.
- **CLI tool**: `kubeseal` (version managed by `.mise.toml`).
