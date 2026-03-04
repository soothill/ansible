# Proxmox Ubuntu VM Deployment

Ansible playbook and interactive wrapper script for spinning up a fully configured Ubuntu 24.04 (Noble) VM on a Proxmox VE host. The cloud-init template is created automatically on the first run — no manual preparation required.

## What it does

**Play 1 — Proxmox (runs on the Proxmox host)**

1. Fetches SSH public keys from a GitHub user's profile
2. Checks whether the cloud-init template exists; if not, downloads the Ubuntu Noble cloud image and builds the template automatically
3. Clones the template into a new full VM with the requested hostname, CPU, RAM, disk, and network settings
4. Configures DHCP, the deploy user, and SSH keys via cloud-init
5. Starts the VM and waits for the QEMU guest agent to report a live IP address

**Play 2 — Ubuntu VM (runs on the new guest)**

1. Sets the hostname and `/etc/hosts`
2. Full `dist-upgrade` — brings all packages up to date
3. Installs: `lldpd`, `avahi-daemon` (Zeroconf / mDNS), `openssh-server`, and common utilities
4. Hardens SSH — disables password auth and root login
5. Creates the deploy user with passwordless sudo and GitHub SSH keys
6. Configures LLDP on all interfaces
7. Enables mDNS `.local` resolution via NSS
8. Enables `unattended-upgrades` for automatic security patches
9. Reboots if a kernel or library update requires it

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Proxmox VE host | Reachable at `proxmox.local` (or override with `PROXMOX_HOST`) |
| SSH access to Proxmox | Key-based recommended; password auth is supported as a fallback |
| Ansible ≥ 2.9 | On the machine running the playbook |
| `community.general` collection | Installed automatically by the wrapper script if missing |
| Internet access on the Proxmox host | Required on first run to download the Ubuntu Noble cloud image (~700 MB) |
| GitHub account with SSH keys | Public keys are pulled from `github.com/<user>.keys` |

### Set up SSH key auth to Proxmox (recommended)

```bash
ssh-copy-id root@proxmox.local
```

---

## Quick start

```bash
./deploy_ubuntu_vm.sh
```

The script prompts for every setting, shows a deployment summary, and asks for confirmation before running.

### Example session

```
=== VM Configuration ===

New VM hostname (required): webserver
Proxmox host address [proxmox.local]:
Proxmox SSH user [root]:
Proxmox node name [proxmox]:
Proxmox API user [root]:
Ubuntu cloud-init template VMID [9000]:
vCPU cores [2]: 4
RAM (MB) [2048]: 4096
Disk size (e.g. 20G, 50G) [20G]: 40G
Proxmox storage pool [RaidZ]:
Network bridge [vmbr10g]:
GitHub user for SSH keys [soothill]:
Linux user to create on VM [darren]:
```

Once deployed, connect with:

```bash
ssh darren@webserver.local
```

---

## Script options

```
./deploy_ubuntu_vm.sh [OPTIONS]

OPTIONS
  --non-interactive   Skip all prompts; use environment variables or built-in defaults
  --dry-run           Print the ansible-playbook command without executing it
  --help              Show this help and exit
```

### Non-interactive / CI usage

Set any combination of environment variables and pass `--non-interactive`:

```bash
NEW_HOSTNAME=ci-runner \
VM_CORES=4 \
VM_MEMORY=8192 \
VM_DISK_SIZE=50G \
./deploy_ubuntu_vm.sh --non-interactive
```

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `NEW_HOSTNAME` | *(required)* | Hostname for the new VM |
| `PROXMOX_HOST` | `proxmox.local` | Proxmox host address |
| `PROXMOX_SSH_USER` | `root` | SSH user for the Proxmox host |
| `PROXMOX_NODE` | `proxmox` | Proxmox node name |
| `PROXMOX_API_USER` | `root` | Proxmox API user |
| `TEMPLATE_VMID` | `9000` | VMID of the Ubuntu cloud-init template |
| `VM_CORES` | `2` | vCPU cores |
| `VM_MEMORY` | `2048` | RAM in MB |
| `VM_DISK_SIZE` | `20G` | Disk size (e.g. `20G`, `100G`, `1T`) |
| `VM_STORAGE` | `RaidZ` | Proxmox storage pool |
| `VM_NETWORK_BRIDGE` | `vmbr10g` | Network bridge |
| `GITHUB_USER` | `soothill` | GitHub username to pull SSH keys from |
| `DEPLOY_USER` | `darren` | Linux user to create on the VM |

---

## Direct playbook usage

Run without the wrapper script by passing variables with `-e`:

```bash
ansible-playbook proxmox_ubuntu_deploy.yml \
  -i proxmox.local, \
  -e "new_hostname=webserver" \
  -e "vm_cores=4" \
  -e "vm_memory=4096" \
  -e "vm_disk_size=40G"
```

### All playbook variables

| Variable | Default | Description |
|---|---|---|
| `new_hostname` | *(required)* | Hostname for the new VM |
| `proxmox_node` | `proxmox` | Proxmox node name |
| `proxmox_api_user` | `root` | Proxmox API user |
| `template_vmid` | `9000` | VMID of the Ubuntu cloud-init template |
| `vm_cores` | `2` | Number of vCPU cores |
| `vm_memory` | `2048` | RAM in MB |
| `vm_disk_size` | `20G` | Disk size to resize to |
| `vm_storage` | `RaidZ` | Proxmox storage pool name |
| `vm_network_bridge` | `vmbr10g` | Proxmox network bridge |
| `github_user` | `soothill` | GitHub username to pull SSH keys from |
| `deploy_user` | `darren` | Linux user to create on the new VM |

---

## Cloud-init template auto-creation

If no VM exists at `template_vmid` (default: `9000`), the playbook builds one automatically:

1. Downloads `noble-server-cloudimg-amd64.img` from `cloud-images.ubuntu.com`
2. Creates a Proxmox VM with `virtio-scsi-pci` storage controller
3. Imports the cloud image disk into the configured storage pool
4. Attaches the disk, adds a cloud-init drive (`ide2`), sets the boot order, enables the QEMU guest agent
5. Converts the VM to a template
6. Removes the downloaded image

This only happens once. Subsequent deployments clone the existing template and complete in seconds.

To use a pre-existing template at a different VMID:

```bash
TEMPLATE_VMID=8000 ./deploy_ubuntu_vm.sh
```

---

## What the VM ends up with

| Item | Detail |
|---|---|
| OS | Ubuntu 24.04 LTS (Noble), fully patched |
| Network | DHCP via cloud-init; reachable at `<hostname>.local` |
| SSH | Key-only auth; root login disabled |
| User | `darren` (or configured) with passwordless sudo and GitHub SSH keys |
| LLDP | `lldpd` running on all interfaces |
| mDNS | Avahi daemon enabled; `.local` names resolve via NSS |
| Auto-updates | `unattended-upgrades` enabled for nightly security patches |

---

## Files

| File | Description |
|---|---|
| `proxmox_ubuntu_deploy.yml` | Ansible playbook (two plays: Proxmox provisioning + VM configuration) |
| `deploy_ubuntu_vm.sh` | Interactive wrapper — prompts, validates, and runs the playbook |
