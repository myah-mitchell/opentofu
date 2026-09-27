variable "name" {
  description = "VM name. Cloud-init uses it as the hostname, so it must be a valid DNS label."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be a lowercase DNS label."
  }
}

variable "node_name" {
  description = "Proxmox node the VM is created on."
  type        = string
}

variable "template_vm_id" {
  description = "VMID of the cloud-init template to clone."
  type        = number
}

variable "template_node_name" {
  description = <<-EOT
    Node the template lives on. Null means node_name. On another node of the
    same cluster, the clone is made there and migrated to node_name.
  EOT
  type        = string
  default     = null
}

variable "vm_id" {
  description = "VMID for the new VM. Null lets Proxmox pick the next free one."
  type        = number
  default     = null
}

variable "datastore_id" {
  description = "Datastore for the cloned disks and the cloud-init drive."
  type        = string
}

variable "cores" {
  description = "Number of vCPU cores."
  type        = number
  default     = 2
}

variable "cpu_type" {
  description = "CPU type. Check `qm config <template-vmid>` and match it. If the template sets none, Proxmox uses its own default for new VMs."
  type        = string
  default     = "x86-64-v2-AES"
}

variable "numa" {
  description = "Enable NUMA. The template is built with --numa 1."
  type        = bool
  default     = true
}

variable "memory_mb" {
  description = "Dedicated memory in MB."
  type        = number
  default     = 2048
}

variable "balloon_mb" {
  description = "Balloon minimum in MB. 0 disables ballooning. The template uses 1024. The default of 0 gives every VM a fixed amount of memory. Set it above 0 to let Proxmox reclaim memory from an idle guest under host pressure."
  type        = number
  default     = 0
}

variable "on_boot" {
  description = "Start the VM when the Proxmox node boots. The template leaves this off."
  type        = bool
  default     = true
}

variable "bridge" {
  description = "Bridge for the primary network device."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag for the primary network device. Null keeps the tag carried by the template."
  type        = number
  default     = null
}

variable "ipv4_address" {
  description = "Static address in CIDR form, for example 192.0.2.10/24."
  type        = string

  validation {
    condition     = can(cidrhost(var.ipv4_address, 0))
    error_message = "ipv4_address must be in CIDR form, for example 192.0.2.10/24."
  }
}

variable "ipv4_gateway" {
  description = "Gateway for the VLAN this VM sits on."
  type        = string
}

variable "dns_servers" {
  description = "Nameservers written to cloud-init. Empty leaves the template's setting."
  type        = list(string)
  default     = []
}

variable "extra_disks" {
  description = "Disks added on top of the two the template already carries (scsi0 and scsi1). The interface is explicit, for example scsi2."
  type = map(object({
    interface    = string
    size_gb      = number
    datastore_id = optional(string)
  }))
  default = {}
}

variable "template_tags" {
  description = "Tags the template carries (see `qm config <template-vmid>`). Kept on every clone. Update this if the template's tags change."
  type        = list(string)
  default     = ["26.04", "cloudinit", "ubuntu"]
}

variable "tags" {
  description = "Proxmox tags added to the template's tags and the `tofu` tag."
  type        = list(string)
  default     = []
}

variable "started" {
  description = "Start the VM after creation."
  type        = bool
  default     = true
}

variable "agent_timeout" {
  description = "How long to wait for the QEMU guest agent to report an address. A clone without a running agent blocks for this long, so keep it short."
  type        = string
  default     = "5m"
}
