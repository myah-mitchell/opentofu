# opentofu

OpenTofu configuration that creates the fleet's VMs on Proxmox by cloning the cloud-init template the `ansible` repo builds. It replaces the manual `qm clone`, `qm set` and `qm start` steps in `docker-stacks/docs/provision-a-vm.md`.

Cloud-init still provisions each VM on first boot through the template's vendor snippet, so nothing here needs to hand off to Ansible. The Komodo onboarding key remains a manual step.

## Layout

```
modules/vm/           one VM: clone, cores/memory, VLAN, static IP, extra disks
envs/prod/         the environment: providers, backend, encryption, VM map
  terraform.tfvars.example
```

Real values (servers, node names, IPs, VLANs) go in a tfvars file in the private repo, at `opentofu/prod.tfvars` in `fleet-private`, next to the Ansible inventory. `*.tfvars` is git-ignored here. No secret belongs in this repo or in the tfvars.

## Runtime configuration

Everything sensitive arrives as environment variables:

| Variable | Purpose |
|---|---|
| `TF_VAR_server_api_tokens` | JSON map of API tokens, one per server in `servers`, each `user@realm!tokenid=secret`: a scoped token, not `root@pam` |
| `PROXMOX_VE_API_TOKEN` | The token for a server missing from that map. Only one server can use it, since two servers never share a token |
| `PROXMOX_VE_ENDPOINT` | The API URL for a server whose `endpoint` is null |
| `PROXMOX_VE_INSECURE` | `true` only while the API certificate is not yet trusted, for a server whose `insecure` is null |
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
cd envs/prod
tofu init
tofu plan  -var-file=../../../fleet-private/opentofu/prod.tfvars
tofu apply -var-file=../../../fleet-private/opentofu/prod.tfvars
```

The path assumes `fleet-private` is checked out next to this repo.

`prevent_destroy` is set on the VM resource. Removing a VM means editing `modules/vm/main.tf` on purpose.

Existing VMs are not imported. Only new VMs are managed here, so a plan cannot touch a running host.

## Servers and clusters

`servers` lists every Proxmox API the VMs live behind, and each gets its own provider (provider `for_each`, new in OpenTofu 1.9). A standalone node is a server of its own. A cluster is one server, reached through any node. Each VM names its `server`, and optionally a `node_name`:

- With `node_name`, the VM is pinned. It is created there, and a VM moved elsewhere in Proxmox is migrated back by the next apply that includes it.
- Without it, a new VM is created on the server's `template_node`, and after that it is left wherever it runs. A data source lists the VMs tagged `tofu` on each server, and the VM's current node is used as its `node_name`, so moving it in Proxmox, or HA doing so, causes no change.

A cluster has one cloud-init template, on its `template_node`. A pinned VM for another node is cloned there and migrated, which the provider does itself when the storage is not shared. The vendor snippet has to be on every node, since each node reads it from its own `local` storage; the ansible repo's `pve` role puts it there. The clone source only matters at creation, so the module ignores later changes to it, and a new template VMID never plans a replacement.

Every plan reads each server's VM list, so it needs the API even when nothing changes, and the token needs `VM.Audit` on the VMs (the role below has it). A node that is down is left out of the list with a warning, and an unpinned VM on it is then planned back onto the template node. That apply fails while the node is down, and a run against that VM would fail anyway.

Removing a server from `servers` while its VMs are still in the state leaves them without a provider, and the plan fails. Moving a VM to another server is a new VM, which `prevent_destroy` refuses.

## Driven from Ansible

The ansible repo's `site.yml` runs this configuration through its `vms` role. It checks this repo out, copies the private repo's `opentofu/prod.tfvars` in as `envs/prod/private.auto.tfvars`, and applies with `-target` for the hosts in that run only, each matched to a VM by its `serverHostname` in lower case. A host with no VM in the file matches nothing. Every other VM is still in the input, so the plan leaves it alone, and the role refuses any plan that would destroy something. The tokens and the other environment variables are read from the `ansible-playbook` process. The role's `vms_backend: local` swaps in a local state file for trying it away from Semaphore.

The `vms` output lists every VM in the input, created or not, with its server, node, VMID and bare IPv4 address. The role uses it to tell a VM from a host built by hand, and checks the address against the host's `ansible_host`.

Running `tofu` by hand and running `site.yml` against the same state both work, as long as both use the same tfvars. A VM that is in the state but missing from the input is a VM the plan wants to destroy, which `prevent_destroy` stops.

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

Also confirmed on that clone: a second `tofu plan` reports no changes, so the inherited disks cause no drift, and cloud-init reached `status: done`. A later apply on the same clone merged its tags as the table shows.

`template_tags` is a plain variable, not read from the template. If the template's tags change, update it to match.

## Scoped token

A second clone (`example02`) was created with a privilege-separated token that has no access on `/`. The role `TofuVM` is granted to the user and the token on `/vms`, `/storage/local-zfs` and `/sdn/zones/localnetwork`:

```
Datastore.AllocateSpace Datastore.Audit SDN.Use Sys.Audit VM.Allocate VM.Audit
VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk
VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options
VM.GuestAgent.Audit VM.Migrate VM.PowerMgmt
```

`VM.Migrate` was added afterwards for clones placed on a node other than the template's, and is untested. Each standalone server and each cluster needs its own user, role and token.

`VM.GuestAgent.Audit` is required on current Proxmox versions to read the guest agent (the old `VM.Monitor` no longer exists). The token can still act on every VM under `/vms`. A tighter setup puts managed VMs in a pool and grants on `/pool/<name>`, which needs a `pool_id` in the module.

## Apply returns before provisioning finishes

`tofu apply` completes once the guest agent reports an address. The agent starts early in first boot, so apply can finish while cloud-init and the Ansible provisioning are still running, by a few minutes in the first test. Do not chain a follow-up job on apply completing. Wait for `cloud-init status --wait` on the host first.

That command exits 2, not 0, when cloud-init finishes as `degraded done`. Clones currently do this: Proxmox generates the user-data with a `user:` key that cloud-init has deprecated (removal is scheduled for 27.2), and cloud-init reports it as a recoverable error. Treat exit codes 0 and 2 as success and 1 as failure. `errors: []` in `cloud-init status --long` means nothing actually failed.

A `BrokenPipeError` traceback from `cloud-init` in the console at the end of first boot is cosmetic. Python is upgraded while the final stage is still running, so cloud-init cannot report completion over its status socket. `cloud-final` still finishes and no units fail.

## Not yet verified

- The `pg` backend end to end, and a real run of `tofu` from inside Semaphore (its image ships 1.9.0, and this configuration validates and plans on it).
- A real apply through the ansible repo's `vms` role. Its check-mode plan was tested offline with OpenTofu 1.9.0 and a local backend, including a two-node cluster and a standalone server.
- A clone migrated to another node of a cluster, and the privileges that needs.
- A pinned VM moved back after a manual migration, and an unpinned one left where it was. The provider's source finds a moved VM on its new node when it refreshes, and the plan was tested against a mocked VM list, but neither has run against a real cluster.
- An existing state from before `servers`: its VMs were created under the old single provider. OpenTofu should move them to the new one on the next plan, as long as they stay in the input, but this has not been tried.
