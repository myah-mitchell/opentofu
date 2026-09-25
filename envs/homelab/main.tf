module "vm" {
  source   = "../../modules/vm"
  for_each = var.vms

  name           = each.key
  node_name      = var.node_name
  template_vm_id = var.template_vm_id
  datastore_id   = var.datastore_id
  template_tags  = var.template_tags

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
  description = "Name, VMID and address of every VM this environment manages."
  value = {
    for name, vm in module.vm : name => {
      vm_id        = vm.vm_id
      ipv4_address = vm.ipv4_address
    }
  }
}
