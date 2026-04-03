# List all available recipes
default:
    @just --list

# Extract talosconfig from tofu state and write to ~/.talos/config
talosconfig:
    mkdir -p ~/.talos
    tofu state pull | jq -r '.resources[] | select(.module=="module.proxmox" and .type=="talos_client_configuration") | .instances[0].attributes.talos_config' > ~/.talos/config
    @echo "Wrote talosconfig to ~/.talos/config"

# Extract kubeconfig from tofu state and write to ~/.kube/config
kubeconfig:
    mkdir -p ~/.kube
    tofu state pull | jq -r '.resources[] | select(.module=="module.proxmox" and .type=="talos_cluster_kubeconfig") | .instances[0].attributes.kubeconfig_raw' > ~/.kube/config
    @echo "Wrote kubeconfig to ~/.kube/config"

# Apply tofu changes without confirmation
tf-apply:
    tofu apply -auto-approve

# Destroy all VMs and rebuild the cluster from scratch
destroy-and-setup:
    ./scripts/destroy.sh
    just tf-apply
    just kubeconfig
    just talosconfig
    cd manifests/tailscale-operator && ./apply.sh
    kubectl -n tailscale wait --for=condition=available deployment/operator --timeout=180s
    @echo "Waiting for tailscale-operator peer to appear..."
    @for i in $(seq 1 60); do \
        tailscale configure kubeconfig tailscale-operator 2>/dev/null && break || true; \
        echo "  Attempt $$i/60 - peer not yet visible, waiting 5s..."; \
        sleep 5; \
    done
    @echo "Waiting for kubectl to become responsive..."
    @for i in $(seq 1 30); do \
        kubectl get nodes 2>/dev/null && break || true; \
        echo "  Attempt $$i/30 - API not yet responsive, waiting 5s..."; \
        sleep 5; \
    done
    just patch-coredns

# Patch CoreDNS to resolve git.organa.one via LAN
patch-coredns:
    kubectl apply -f manifests/coredns-patch.yaml
    kubectl rollout restart deployment coredns -n kube-system
    kubectl rollout status deployment coredns -n kube-system --timeout=60s

# Print the ArgoCD initial admin password
argocd-initial-admin-secret:
    kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo

# Log in to ArgoCD and update the admin password
argocd-update-admin-secret:
   argocd login ${ARGOCD_SERVER} --username admin --grpc-web
   argocd account update-password --grpc-web

# Print the Grafana initial admin password
grafana-initial-admin-secret:
    kubectl get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d && echo

# Seal a plain Kubernetes Secret for use with sealed-secrets
# Usage: just seal-secret path/to/secret.yaml > path/to/sealed-secret.yaml
seal-secret file:
    kubeseal --format yaml --controller-name sealed-secrets-controller --controller-namespace kube-system < {{file}}

# Backup the sealed-secrets controller key (store this somewhere safe!)
backup-sealed-secrets-key:
    kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
    @echo "Key written to sealed-secrets-key-backup.yaml — store this securely and do NOT commit it"

