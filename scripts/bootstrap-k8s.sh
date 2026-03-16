#!/usr/bin/env bash
set -euo pipefail

# install the tailscale-operator
helm upgrade \
  --install \
  tailscale-operator \
  tailscale/tailscale-operator \
  --namespace=tailscale \
  --create-namespace \
  --set-string oauth.clientId="${TF_VAR_tailscale_oauth_client_id}" \
  --set-string oauth.clientSecret="${TF_VAR_tailscale_oauth_client_secret}" \
  --set-string apiServerProxyConfig.mode="true" \
  --wait

# after the tailscale operator is installed setup the k8s context
tailscale configure kubeconfig tailscale-operator

# install Argo CD
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

