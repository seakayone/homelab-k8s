resource "proxmox_virtual_environment_download_file" "talos_cloud_image" {
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = var.target_node_name
  url                     = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.12.5/nocloud-amd64.raw.zst"
  decompression_algorithm = "zst"
  file_name               = "talos-v1.12.5-nocloud-qemu-guest-amd64.img"
  overwrite               = false
}

resource "proxmox_virtual_environment_vm" "talos_control_plane" {
  name      = "talos-controlplane-01"
  vm_id     = 1000
  node_name = var.target_node_name

  tags = ["terraform", "k8s"]

  stop_on_destroy = true

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2560
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.talos_cloud_image.id
    interface    = "scsi0"
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
  }

  serial_device {}

  operating_system {
    type = "l26"
  }
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  count = 1

  name      = "talos-worker-${format("%02d", count.index + 1)}"
  vm_id     = 1010 + count.index
  node_name = var.target_node_name

  tags = ["terraform", "k8s"]

  stop_on_destroy = true

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.talos_cloud_image.id
    interface    = "scsi0"
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
  }

  serial_device {}

  operating_system {
    type = "l26"
  }
}
