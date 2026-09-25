variable "node_name" {
  description = "Proxmox node the VMs are created on."
  type        = string
}

variable "template_vm_id" {
  description = "VMID of the cloud-init template, the same one the runbook clones."
  type        = number
}

variable "datastore_id" {
  description = "Datastore for cloned disks and the cloud-init drive."
  type        = string
}

variable "template_tags" {
  description = "Tags the template carries. Kept on every clone."
  type        = list(string)
  default     = ["26.04", "cloudinit", "ubuntu"]
}

variable "vms" {
  description = "VMs to create, keyed by name."
  type = map(object({
    vm_id         = optional(number)
    cores         = optional(number, 2)
    cpu_type      = optional(string, "x86-64-v2-AES")
    numa          = optional(bool, true)
    memory_mb     = optional(number, 2048)
    balloon_mb    = optional(number, 0)
    on_boot       = optional(bool, true)
    bridge        = optional(string, "vmbr0")
    vlan_id       = optional(number)
    ipv4_address  = string
    ipv4_gateway  = string
    dns_servers   = optional(list(string), [])
    tags          = optional(list(string), [])
    started       = optional(bool, true)
    agent_timeout = optional(string, "5m")
    extra_disks = optional(map(object({
      interface    = string
      size_gb      = number
      datastore_id = optional(string)
    })), {})
  }))
  default = {}
}
