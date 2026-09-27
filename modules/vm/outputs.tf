output "vm_id" {
  description = "VMID assigned by Proxmox."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "VM name."
  value       = proxmox_virtual_environment_vm.this.name
}

output "ipv4_address" {
  description = "Address the VM was given, without the prefix length."
  value       = split("/", var.ipv4_address)[0]
}

output "node_name" {
  description = "Node the VM runs on."
  value       = proxmox_virtual_environment_vm.this.node_name
}
