# Extract talosconfig from tofu state and write to ~/.talos/config
talosconfig:
    tofu state pull | jq -r '.resources[] | select(.module=="module.proxmox" and .type=="talos_client_configuration") | .instances[0].attributes.talos_config' > ~/.talos/config
    @echo "Wrote talosconfig to ~/.talos/config"

# Extract kubeconfig from tofu state and write to ~/.kube/config
kubeconfig:
    tofu state pull | jq -r '.resources[] | select(.module=="module.proxmox" and .type=="talos_cluster_kubeconfig") | .instances[0].attributes.kubeconfig_raw' > ~/.kube/config
    @echo "Wrote kubeconfig to ~/.kube/config"
