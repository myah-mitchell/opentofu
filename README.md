# opentofu

OpenTofu configuration that creates the fleet's VMs on Proxmox by cloning the cloud-init template the `ansible` repo builds. It replaces the manual `qm clone`, `qm set` and `qm start` steps in `docker-stacks/docs/provision-a-vm.md`.

Cloud-init still provisions each VM on first boot through the template's vendor snippet, so nothing here needs to hand off to Ansible. The Komodo onboarding key remains a manual step.

## Layout

```
modules/vm/           one VM: clone, cores/memory, VLAN, static IP, extra disks
envs/homelab/         the environment: provider, backend, encryption, VM map
  terraform.tfvars.example
```

Real values (node name, datastore, IPs, VLANs) go in `terraform.tfvars` in a private overlay, the same pattern as `ansible-private`. `*.tfvars` is git-ignored here. No secret belongs in this repo or in the tfvars.

## Runtime configuration

Everything sensitive arrives as environment variables:

| Variable | Purpose |
|---|---|
| `PROXMOX_VE_ENDPOINT` | Proxmox API URL |
| `PROXMOX_VE_API_TOKEN` | `user@realm!tokenid=secret`, a scoped token, not `root@pam` |
| `PROXMOX_VE_INSECURE` | `true` only while the API certificate is not yet trusted |
| `PG_CONN_STR` | Postgres connection string for the `pg` state backend. On ci01 this is `postgres://tofu:<password>@postgres:5432/tofu_state?sslmode=disable`, a second database on Semaphore's Postgres (see `docker-stacks/docs/semaphore-setup.md`), reachable only from Semaphore's container |
| `TF_ENCRYPTION` | State and plan encryption config (see below) |

`TF_ENCRYPTION` holds the key provider and method:

```hcl
key_provider "pbkdf2" "main" { passphrase = "<at least 16 characters>" }
method "aes_gcm" "main" { keys = key_provider.pbkdf2.main }
state { method = method.aes_gcm.main }
plan  { method = method.aes_gcm.main }
```

The code marks state and plan encryption as `enforced`, so OpenTofu refuses to run without it. When `TF_ENCRYPTION` is missing the error is `Invalid expression` on the `state {` line (OpenTofu 1.12) or `Missing encryption method` (1.9). That is the encryption check failing, not a syntax problem, and no state is written.

## Usage

```
cd envs/homelab
tofu init
tofu plan  -var-file=terraform.tfvars
tofu apply -var-file=terraform.tfvars
```

`prevent_destroy` is set on the VM resource. Removing a VM means editing `modules/vm/main.tf` on purpose.

Existing VMs are not imported. Only new VMs are managed here, so a plan cannot touch a running host.

## Verified

Checked with OpenTofu 1.12.6 and 1.9.0 (the version in Semaphore's v2.13.13 image, so `required_version` is `>= 1.9.0`), without a Proxmox server:

- `tofu fmt` is clean and `tofu validate` passes.
- The example tfvars parse, and a bad VM name or a non-CIDR address is rejected.
- An offline plan renders the expected resource.
- With `TF_ENCRYPTION` set, state is written encrypted. Without it, nothing is written.

## Verified against a real Proxmox node (first test clone)

- The `initialization` block leaves the template's `cicustom` vendor snippet, `ciuser` and `sshkeys` intact.
- The template's VLAN tag, both inherited disks (`scsi0` 20G, `scsi1` 40G) and NUMA carry over to the clone.
- The QEMU guest agent runs in the clone and reports its address.

Differences from the template that the module sets on purpose (all overridable per VM):

| Setting | Template | Clone | Variable |
|---|---|---|---|
| CPU type | none (Proxmox default) | `x86-64-v2-AES` | `cpu_type` |
| Balloon | 1024 | 0 (off) | `balloon_mb` |
| Start on node boot | off | on | `on_boot` |
| Tags | `26.04;cloudinit;ubuntu` | template tags, `tofu`, and the ones you pass | `template_tags`, `tags` |

Also confirmed on that clone: a second `tofu plan` reports no changes, so the inherited disks cause no drift, and cloud-init reached `status: done`.

`template_tags` is a plain variable, not read from the template. If the template's tags change, update it to match.

## Scoped token

A second clone (`example02`) was created with a privilege-separated token that has no access on `/`. The role `TofuVM` is granted to the user and the token on `/vms`, `/storage/local-zfs` and `/sdn/zones/localnetwork`:

```
Datastore.AllocateSpace Datastore.Audit SDN.Use Sys.Audit VM.Allocate VM.Audit
VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk
VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options
VM.GuestAgent.Audit VM.PowerMgmt
```

`VM.GuestAgent.Audit` is required on current Proxmox versions to read the guest agent (the old `VM.Monitor` no longer exists). The token can still act on every VM under `/vms`. A tighter setup puts managed VMs in a pool and grants on `/pool/<name>`, which needs a `pool_id` in the module.

## Apply returns before provisioning finishes

`tofu apply` completes once the guest agent reports an address. The agent starts early in first boot, so apply can finish while cloud-init and the Ansible provisioning are still running, by a few minutes in the first test. Do not chain a follow-up job on apply completing. Wait for `cloud-init status --wait` on the host first.

That command exits 2, not 0, when cloud-init finishes as `degraded done`. Clones currently do this: Proxmox generates the user-data with a `user:` key that cloud-init has deprecated (removal is scheduled for 27.2), and cloud-init reports it as a recoverable error. Treat exit codes 0 and 2 as success and 1 as failure. `errors: []` in `cloud-init status --long` means nothing actually failed.

A `BrokenPipeError` traceback from `cloud-init` in the console at the end of first boot is cosmetic. Python is upgraded while the final stage is still running, so cloud-init cannot report completion over its status socket. `cloud-final` still finishes and no units fail.

## Not yet verified

- The tag merge against a real node.
- The `pg` backend end to end, and a real run of `tofu` from inside Semaphore (its image ships 1.9.0, and this configuration validates and plans on it).
- The `pg` backend end to end, and a real run of `tofu` from inside Semaphore (its image ships 1.9.0, and this configuration validates and plans on it).
