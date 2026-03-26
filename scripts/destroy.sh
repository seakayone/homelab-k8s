#!/usr/bin/env bash
set -euo pipefail

PVE_URL="${TF_VAR_endpoint}"
API_TOKEN="${TF_VAR_api_token}"
NODE="pve"
VM_IDS=(1000 1010 1011)
ISO_FILE="talos-v1.12.5-nocloud-qemu-guest-amd64.img"

CT_IDS=(2000)

AUTH_HEADER="Authorization: PVEAPIToken=${API_TOKEN}"

for vmid in "${VM_IDS[@]}"; do
  echo "Stopping VM ${vmid}..."
  curl -sk -X POST -H "${AUTH_HEADER}" "${PVE_URL}/api2/json/nodes/${NODE}/qemu/${vmid}/status/stop" 2>/dev/null || true
done

for ctid in "${CT_IDS[@]}"; do
  echo "Stopping container ${ctid}..."
  curl -sk -X POST -H "${AUTH_HEADER}" "${PVE_URL}/api2/json/nodes/${NODE}/lxc/${ctid}/status/stop" 2>/dev/null || true
done

echo "Waiting for VMs and containers to stop..."
sleep 5

for vmid in "${VM_IDS[@]}"; do
  echo "Destroying VM ${vmid}..."
  curl -sk -X DELETE -H "${AUTH_HEADER}" "${PVE_URL}/api2/json/nodes/${NODE}/qemu/${vmid}" 2>/dev/null || true
done

for ctid in "${CT_IDS[@]}"; do
  echo "Destroying container ${ctid}..."
  curl -sk -X DELETE -H "${AUTH_HEADER}" "${PVE_URL}/api2/json/nodes/${NODE}/lxc/${ctid}" 2>/dev/null || true
done

echo "Removing ISO ${ISO_FILE}..."
curl -sk -X DELETE -H "${AUTH_HEADER}" "${PVE_URL}/api2/json/nodes/${NODE}/storage/local/content/local:iso/${ISO_FILE}" 2>/dev/null || true

echo "Clearing tofu state..."
rm -f terraform.tfstate terraform.tfstate.backup

echo "Done."
