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
