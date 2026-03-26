#!/usr/bin/env bash
set -euo pipefail

echo "Provisioning NFS server in container ${CONTAINER_ID}..."

ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_PATH}" "${SSH_USER}@${PROXMOX_HOST}" bash <<EOF
  # Ensure NFS kernel module is loaded on the Proxmox host
  modprobe nfsd || true

  # Wait for container to be running
  echo "Waiting for container ${CONTAINER_ID} to start..."
  for i in \$(seq 1 30); do
    pct status ${CONTAINER_ID} | grep -q running && break
    sleep 2
  done

  # Install and configure NFS server
  echo "Installing nfs-kernel-server..."
  pct exec ${CONTAINER_ID} -- bash -c '
    apt-get update &&
    apt-get install -y nfs-kernel-server &&
    mkdir -p /export/k8s &&
    echo "/export/k8s 192.168.178.0/24(rw,sync,no_subtree_check,no_root_squash)" > /etc/exports &&
    exportfs -ra &&
    systemctl enable --now nfs-kernel-server
  '

  echo "NFS server provisioned successfully."
EOF
