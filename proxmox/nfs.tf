resource "proxmox_virtual_environment_download_file" "debian_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.target_node_name
  url          = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  file_name    = "debian-12-genericcloud-amd64.img"
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "nfs_server" {
  name      = "nfs-server"
  vm_id     = 2000
  node_name = var.target_node_name

  description = "NFS server for Kubernetes persistent volumes"

  tags = ["nfs", "terraform"]

  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.debian_cloud_image.id
    file_format  = "raw"
    interface    = "scsi0"
    size         = 20
    discard      = "on"
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    dns {
      servers = [var.network_gateway]
    }

    ip_config {
      ipv4 {
        address = "192.168.178.200/24"
        gateway = var.network_gateway
      }
    }

    user_account {
      username = "debian"
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  serial_device {}

  operating_system {
    type = "l26"
  }
}

resource "terraform_data" "nfs_provisioner" {
  depends_on = [proxmox_virtual_environment_vm.nfs_server]

  triggers_replace = [proxmox_virtual_environment_vm.nfs_server.vm_id]

  provisioner "local-exec" {
    command = "bash ${path.module}/../scripts/provision-nfs.sh"

    environment = {
      SSH_KEY_PATH    = pathexpand(var.ssh_private_key_path)
      NFS_SERVER_IP   = "192.168.178.200"
      NFS_SERVER_USER = "debian"
    }
  }
}
