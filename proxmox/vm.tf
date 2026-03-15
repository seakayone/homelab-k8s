resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.target_node_name
  url          = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  file_name    = "jammy-server-cloudimg-amd64.img"
}

resource "proxmox_virtual_environment_vm" "small_vm" {
  name      = "small-ubuntu-vm"
  node_name = var.target_node_name

  tags = ["terraform"]

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
    file_id   = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    interface = "scsi0"
    size         = 10
    discard      = "on"
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  serial_device {}

  operating_system {
    type = "l26"
  }
}
