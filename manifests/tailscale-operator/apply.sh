#!/usr/bin/env bash
# Build and apply the tailscale-operator kustomization.
# Reads TS credentials from the environment (set via .envrc / direnv).
#
# Usage:
#   ./apply.sh              # kubectl apply
#   ./apply.sh --dry-run    # kubectl apply --dry-run=client
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/operator-oauth.env"

# Map the TF_VAR names from .envrc to what the Secret expects
: "${TF_VAR_tailscale_oauth_client_id:?Set TF_VAR_tailscale_oauth_client_id (via .envrc / direnv)}"
: "${TF_VAR_tailscale_oauth_client_secret:?Set TF_VAR_tailscale_oauth_client_secret (via .envrc / direnv)}"

cleanup() { rm -f "$ENV_FILE"; }
trap cleanup EXIT

cat > "$ENV_FILE" <<EOF
client_id=${TF_VAR_tailscale_oauth_client_id}
client_secret=${TF_VAR_tailscale_oauth_client_secret}
EOF

kubectl kustomize "$SCRIPT_DIR" | kubectl apply "$@" -f -
