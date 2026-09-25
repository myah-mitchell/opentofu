terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name
  vm_id     = var.vm_id
  # Setting tags on a clone replaces the template's, so they are merged in
  # here. The "tofu" tag marks VMs this configuration manages.
  tags    = sort(distinct(concat(var.template_tags, ["tofu"], var.tags)))
  started = var.started
  on_boot = var.on_boot

  clone {
    vm_id        = var.template_vm_id
    datastore_id = var.datastore_id
    full         = true
  }

  # Set explicitly because the provider's own defaults (qemu64, no NUMA)
  # would otherwise override what the template carries. The template is built
  # with --numa 1 and no CPU type.
  cpu {
    cores = var.cores
    type  = var.cpu_type
    numa  = var.numa
  }

  memory {
    dedicated = var.memory_mb
    floating  = var.balloon_mb
  }

  agent {
    enabled = true
    timeout = var.agent_timeout
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  # The template already carries the scsi0 boot disk and the scsi1 data disk,
  # and a full clone copies both. Only disks beyond those are declared here.
  dynamic "disk" {
    for_each = var.extra_disks
    content {
      datastore_id = coalesce(disk.value.datastore_id, var.datastore_id)
      interface    = disk.value.interface
      size         = disk.value.size_gb
      file_format  = "raw"
      discard      = "on"
      iothread     = true
      ssd          = true
    }
  }

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    dynamic "dns" {
      for_each = length(var.dns_servers) > 0 ? [1] : []
      content {
        servers = var.dns_servers
      }
    }
  }

  # Destroying a fleet VM has to be a deliberate edit of this file, not a
  # side effect of a plan.
  lifecycle {
    prevent_destroy = true
  }
}
