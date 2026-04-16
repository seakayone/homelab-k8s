#!/usr/bin/env bash
# Install ArgoCD and apply the root app-of-apps.
#
# Usage:
#   ./apply.sh              # kubectl apply
#   ./apply.sh --dry-run    # kubectl apply --dry-run=client
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply "$@" --server-side --force-conflicts -n argocd -f "$SCRIPT_DIR/install.yaml"
echo "Waiting for argocd-server deployment to exist..."
until kubectl -n argocd get deployment/argocd-server &>/dev/null; do sleep 2; done
kubectl -n argocd wait --for=condition=available deployment/argocd-server --timeout=300s
kubectl apply "$@" -R -f "$REPO_ROOT/apps/"
