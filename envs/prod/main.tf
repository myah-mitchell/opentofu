# One provider per server. The keys must be known before the plan, which
# OpenTofu 1.9 and later allow for variables. Removing a server while its VMs
# are still in the state leaves them without a provider, so the plan fails.
provider "proxmox" {
  alias    = "server"
  for_each = var.servers

  endpoint  = each.value.endpoint
  insecure  = each.value.insecure
  api_token = lookup(var.server_api_tokens, each.key, null)
}

# Where each managed VM runs now, so a VM without a pinned node_name is left
# there instead of being moved back to where it was created. Only VMs tagged
# "tofu" count, which leaves templates and hand-built VMs out.
data "proxmox_virtual_environment_vms" "managed" {
  provider = proxmox.server[each.key]
  for_each = var.servers

  tags = ["tofu"]
}

locals {
  # server => VM name => node. Grouped with ... so two VMs of the same name
  # cannot fail the plan; names are unique per server in practice.
  current_node = {
    for server, list in data.proxmox_virtual_environment_vms.managed : server => {
      for vm in list.vms : vm.name => vm.node_name...
    }
  }
}

module "vm" {
  source   = "../../modules/vm"
  for_each = var.vms

  providers = {
    proxmox = proxmox.server[each.value.server]
  }

  name               = each.key
  template_vm_id     = var.servers[each.value.server].template_vm_id
  template_node_name = var.servers[each.value.server].template_node
  datastore_id       = coalesce(each.value.datastore_id, var.servers[each.value.server].datastore_id)
  template_tags      = var.servers[each.value.server].template_tags

  # A pinned node wins. Otherwise the VM stays where it runs now, and a new one
  # is created next to the template, so it needs no migration.
  node_name = coalesce(
    each.value.node_name,
    try(local.current_node[each.value.server][each.key][0], null),
    var.servers[each.value.server].template_node,
  )

  vm_id         = each.value.vm_id
  cores         = each.value.cores
  cpu_type      = each.value.cpu_type
  numa          = each.value.numa
  memory_mb     = each.value.memory_mb
  balloon_mb    = each.value.balloon_mb
  on_boot       = each.value.on_boot
  bridge        = each.value.bridge
  vlan_id       = each.value.vlan_id
  ipv4_address  = each.value.ipv4_address
  ipv4_gateway  = each.value.ipv4_gateway
  dns_servers   = each.value.dns_servers
  extra_disks   = each.value.extra_disks
  tags          = each.value.tags
  started       = each.value.started
  agent_timeout = each.value.agent_timeout
}

output "vms" {
  description = <<-EOT
    Every VM in var.vms, created or not: its server, node, VMID and address.
    Node and VMID are null until the VM exists.
  EOT
  value = {
    for name, vm in var.vms : name => {
      server       = vm.server
      node_name    = try(module.vm[name].node_name, null)
      vm_id        = try(module.vm[name].vm_id, null)
      ipv4_address = split("/", vm.ipv4_address)[0]
    }
  }
}
