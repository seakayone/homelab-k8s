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
    just apply
    just kubeconfig
    just talosconfig
    cd manifests/tailscale-operator && ./apply.sh
    kubectl -n tailscale wait --for=condition=available deployment/operator --timeout=180s
    tailscale configure kubeconfig tailscale-operator
    kubectl get nodes
    
# Print the ArgoCD initial admin password
argocd-initial-admin-secret:
    kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo

# Log in to ArgoCD and update the admin password
argocd-update-admin-secret:
   argocd login ${ARGOCD_SERVER} --username admin --grpc-web
   argocd account update-password --grpc-web

