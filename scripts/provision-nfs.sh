#!/usr/bin/env bash
set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i ${SSH_KEY_PATH}"

echo "Waiting for NFS server VM to become reachable..."
for i in $(seq 1 60); do
  if ssh ${SSH_OPTS} "${NFS_SERVER_USER}@${NFS_SERVER_IP}" true 2>/dev/null; then
    break
  fi
  echo "  Attempt ${i}/60 - waiting..."
  sleep 5
done

echo "Waiting for cloud-init to finish..."
ssh ${SSH_OPTS} "${NFS_SERVER_USER}@${NFS_SERVER_IP}" "sudo cloud-init status --wait" 2>/dev/null || true

echo "Installing and configuring NFS server..."
ssh ${SSH_OPTS} "${NFS_SERVER_USER}@${NFS_SERVER_IP}" bash <<'EOF'
  set -euo pipefail
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update
  sudo apt-get install -y nfs-kernel-server
  sudo mkdir -p /export/k8s
  echo "/export/k8s 192.168.178.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee /etc/exports
  sudo exportfs -ra
  sudo systemctl enable --now nfs-kernel-server
EOF

echo "NFS server provisioned successfully."
