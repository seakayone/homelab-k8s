resource "proxmox_virtual_environment_download_file" "debian_12_lxc_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.target_node_name
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
}

resource "proxmox_virtual_environment_container" "nfs_server" {
  description = "NFS server for Kubernetes persistent volumes"

  node_name = var.target_node_name
  vm_id     = 2000

  tags = ["nfs", "terraform"]

  unprivileged  = false
  start_on_boot = true

  initialization {
    hostname = "nfs-server"

    ip_config {
      ipv4 {
        address = "192.168.178.200/24"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 20
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_12_lxc_template.id
    type             = "debian"
  }
}

resource "terraform_data" "nfs_provisioner" {
  depends_on = [proxmox_virtual_environment_container.nfs_server]

  triggers_replace = [proxmox_virtual_environment_container.nfs_server.vm_id]

  provisioner "local-exec" {
    command = "bash ${path.module}/../scripts/provision-nfs.sh"

    environment = {
      SSH_KEY_PATH = pathexpand(var.ssh_private_key_path)
      SSH_USER     = var.ssh_agent_username
      PROXMOX_HOST = var.target_node_ip
      CONTAINER_ID = "2000"
    }
  }
}
