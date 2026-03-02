#!/usr/bin/env bash
#
# deploy_ubuntu_vm.sh
# Copyright (c) 2026 Darren Soothill
#
# Interactive wrapper for proxmox_ubuntu_deploy.yml.
# Prompts for every variable with sensible defaults, then runs the playbook.
#
# Usage:
#   ./deploy_ubuntu_vm.sh                  # fully interactive
#   ./deploy_ubuntu_vm.sh --non-interactive # use env vars / defaults only, no prompts
#   ./deploy_ubuntu_vm.sh --help
#
# Environment variables (all optional – override any default without prompting):
#   NEW_HOSTNAME, PROXMOX_HOST, PROXMOX_NODE, PROXMOX_API_USER,
#   PROXMOX_API_PASSWORD, TEMPLATE_VMID, VM_CORES, VM_MEMORY,
#   VM_DISK_SIZE, VM_STORAGE, VM_NETWORK_BRIDGE, GITHUB_USER, DEPLOY_USER
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
banner()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }

# Read a value interactively, using $2 as the default.
# Usage: prompt_var VAR_NAME "Description" "default_value" [secret]
prompt_var() {
    local var_name="$1"
    local description="$2"
    local default_val="$3"
    local secret="${4:-}"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        # In non-interactive mode just use current value or default
        [[ -z "${!var_name:-}" ]] && printf -v "$var_name" '%s' "$default_val"
        return
    fi

    local prompt_str
    if [[ -n "$default_val" ]]; then
        prompt_str="${BOLD}${description}${RESET} [${YELLOW}${default_val}${RESET}]: "
    else
        prompt_str="${BOLD}${description}${RESET}: "
    fi

    local input
    if [[ "$secret" == "secret" ]]; then
        # Hide input for passwords
        read -r -s -p "$(echo -e "$prompt_str")" input
        echo   # newline after hidden input
    else
        read -r -p "$(echo -e "$prompt_str")" input
    fi

    if [[ -z "$input" ]]; then
        printf -v "$var_name" '%s' "$default_val"
    else
        printf -v "$var_name" '%s' "$input"
    fi
}

show_help() {
    cat <<EOF
${BOLD}deploy_ubuntu_vm.sh${RESET} – deploy an Ubuntu VM on Proxmox

USAGE
  ./deploy_ubuntu_vm.sh [OPTIONS]

OPTIONS
  --non-interactive   Skip all prompts; use environment variables or built-in defaults
  --dry-run           Print the ansible-playbook command without executing it
  --help              Show this help and exit

ENVIRONMENT VARIABLES (all optional)
  NEW_HOSTNAME          Hostname for the new VM
  PROXMOX_HOST          Proxmox host address       (default: proxmox.local)
  PROXMOX_NODE          Proxmox node name          (default: proxmox)
  PROXMOX_API_USER      Proxmox API user           (default: root@pam)
  PROXMOX_API_PASSWORD  Proxmox API password       (required, no default)
  TEMPLATE_VMID         Source cloud-init VMID     (default: 9000)
  VM_CORES              vCPU cores                 (default: 2)
  VM_MEMORY             RAM in MB                  (default: 2048)
  VM_DISK_SIZE          Disk size                  (default: 20G)
  VM_STORAGE            Proxmox storage pool       (default: local-lvm)
  VM_NETWORK_BRIDGE     Network bridge             (default: vmbr0)
  GITHUB_USER           GitHub user for SSH keys   (default: soothill)
  DEPLOY_USER           Linux user to create       (default: darren)

EXAMPLES
  # Fully interactive
  ./deploy_ubuntu_vm.sh

  # Supply mandatory values, use defaults for everything else
  NEW_HOSTNAME=webserver PROXMOX_API_PASSWORD=secret ./deploy_ubuntu_vm.sh --non-interactive

  # Dry-run to review the command before running
  ./deploy_ubuntu_vm.sh --dry-run
EOF
}

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
NON_INTERACTIVE=false
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --non-interactive) NON_INTERACTIVE=true ;;
        --dry-run)         DRY_RUN=true ;;
        --help|-h)         show_help; exit 0 ;;
        *) die "Unknown option: $arg  (try --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
banner "Checking dependencies"

for cmd in ansible-playbook ansible-galaxy; do
    if command -v "$cmd" &>/dev/null; then
        success "$cmd found ($(command -v "$cmd"))"
    else
        die "$cmd not found – please install Ansible first"
    fi
done

PLAYBOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOK="$PLAYBOOK_DIR/proxmox_ubuntu_deploy.yml"

[[ -f "$PLAYBOOK" ]] || die "Playbook not found: $PLAYBOOK"
success "Playbook found: $PLAYBOOK"

# Ensure community.general is present
if ansible-galaxy collection list 2>/dev/null | grep -q "community.general"; then
    success "community.general collection present"
else
    warn "community.general not found – installing now"
    ansible-galaxy collection install community.general
fi

# ---------------------------------------------------------------------------
# Gather variables
# ---------------------------------------------------------------------------
banner "VM Configuration"

# --- Required ---
prompt_var NEW_HOSTNAME        "New VM hostname (required)"        "${NEW_HOSTNAME:-}"
[[ -n "${NEW_HOSTNAME:-}" ]] || die "new_hostname is required"

prompt_var PROXMOX_API_PASSWORD "Proxmox API password (required)"  "${PROXMOX_API_PASSWORD:-}" secret
[[ -n "${PROXMOX_API_PASSWORD:-}" ]] || die "proxmox_api_password is required"

echo
info "Leave any field blank to accept the value shown in [brackets]"
echo

# --- Proxmox connection ---
prompt_var PROXMOX_HOST        "Proxmox host address"             "${PROXMOX_HOST:-proxmox.local}"
prompt_var PROXMOX_NODE        "Proxmox node name"                "${PROXMOX_NODE:-proxmox}"
prompt_var PROXMOX_API_USER    "Proxmox API user"                 "${PROXMOX_API_USER:-root@pam}"

# --- Template & hardware ---
prompt_var TEMPLATE_VMID       "Ubuntu cloud-init template VMID"  "${TEMPLATE_VMID:-9000}"
prompt_var VM_CORES            "vCPU cores"                       "${VM_CORES:-2}"
prompt_var VM_MEMORY           "RAM (MB)"                         "${VM_MEMORY:-2048}"
prompt_var VM_DISK_SIZE        "Disk size (e.g. 20G, 50G)"        "${VM_DISK_SIZE:-20G}"
prompt_var VM_STORAGE          "Proxmox storage pool"             "${VM_STORAGE:-local-lvm}"
prompt_var VM_NETWORK_BRIDGE   "Network bridge"                   "${VM_NETWORK_BRIDGE:-vmbr0}"

# --- Guest OS ---
prompt_var GITHUB_USER         "GitHub user for SSH keys"         "${GITHUB_USER:-soothill}"
prompt_var DEPLOY_USER         "Linux user to create on VM"       "${DEPLOY_USER:-darren}"

# ---------------------------------------------------------------------------
# Validate inputs
# ---------------------------------------------------------------------------
banner "Validating inputs"

validate_int() {
    [[ "$2" =~ ^[0-9]+$ ]] || die "$1 must be a positive integer (got: $2)"
}
validate_disk() {
    [[ "$2" =~ ^[0-9]+[GMTP]$ ]] || die "$1 must be like 20G, 100G, 1T (got: $2)"
}

validate_int "vm_cores"    "$VM_CORES"
validate_int "vm_memory"   "$VM_MEMORY"
validate_int "template_vmid" "$TEMPLATE_VMID"
validate_disk "vm_disk_size" "$VM_DISK_SIZE"

# Validate hostname (RFC 1123)
[[ "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] \
    || die "Invalid hostname '$NEW_HOSTNAME' (use only letters, digits, hyphens)"

# Check GitHub keys are reachable
info "Checking SSH keys at https://github.com/${GITHUB_USER}.keys ..."
if curl -sf "https://github.com/${GITHUB_USER}.keys" | grep -q "ssh-"; then
    success "SSH keys found for GitHub user: $GITHUB_USER"
else
    die "No SSH keys found at https://github.com/${GITHUB_USER}.keys – check the username"
fi

success "All inputs valid"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
banner "Deployment Summary"

echo -e "  ${BOLD}Hostname${RESET}          : $NEW_HOSTNAME"
echo -e "  ${BOLD}Proxmox host${RESET}      : $PROXMOX_HOST"
echo -e "  ${BOLD}Proxmox node${RESET}      : $PROXMOX_NODE"
echo -e "  ${BOLD}API user${RESET}          : $PROXMOX_API_USER"
echo -e "  ${BOLD}Template VMID${RESET}     : $TEMPLATE_VMID"
echo -e "  ${BOLD}vCPU cores${RESET}        : $VM_CORES"
echo -e "  ${BOLD}RAM${RESET}               : ${VM_MEMORY} MB"
echo -e "  ${BOLD}Disk size${RESET}         : $VM_DISK_SIZE"
echo -e "  ${BOLD}Storage pool${RESET}      : $VM_STORAGE"
echo -e "  ${BOLD}Network bridge${RESET}    : $VM_NETWORK_BRIDGE"
echo -e "  ${BOLD}GitHub SSH keys${RESET}   : github.com/${GITHUB_USER}"
echo -e "  ${BOLD}Deploy user${RESET}       : $DEPLOY_USER"
echo -e "  ${BOLD}mDNS address${RESET}      : ${NEW_HOSTNAME}.local"
echo

# ---------------------------------------------------------------------------
# Build the ansible-playbook command
# ---------------------------------------------------------------------------
CMD=(
    ansible-playbook
    "$PLAYBOOK"
    -i "${PROXMOX_HOST},"
    -e "new_hostname=${NEW_HOSTNAME}"
    -e "proxmox_node=${PROXMOX_NODE}"
    -e "proxmox_api_user=${PROXMOX_API_USER}"
    -e "proxmox_api_password=${PROXMOX_API_PASSWORD}"
    -e "template_vmid=${TEMPLATE_VMID}"
    -e "vm_cores=${VM_CORES}"
    -e "vm_memory=${VM_MEMORY}"
    -e "vm_disk_size=${VM_DISK_SIZE}"
    -e "vm_storage=${VM_STORAGE}"
    -e "vm_network_bridge=${VM_NETWORK_BRIDGE}"
    -e "github_user=${GITHUB_USER}"
    -e "deploy_user=${DEPLOY_USER}"
)

if [[ "$DRY_RUN" == "true" ]]; then
    banner "Dry Run – command that would be executed"
    # Mask the password in dry-run output
    echo -e "${CYAN}$(printf '%q ' "${CMD[@]}" | sed "s/${PROXMOX_API_PASSWORD}/*****/g")${RESET}"
    echo
    info "Re-run without --dry-run to execute."
    exit 0
fi

# ---------------------------------------------------------------------------
# Confirm before running
# ---------------------------------------------------------------------------
if [[ "$NON_INTERACTIVE" != "true" ]]; then
    echo -e "${BOLD}Proceed with deployment?${RESET} [y/N] \c"
    read -r confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
fi

# ---------------------------------------------------------------------------
# Run the playbook
# ---------------------------------------------------------------------------
banner "Running Playbook"

"${CMD[@]}"

EXIT_CODE=$?

echo
if [[ $EXIT_CODE -eq 0 ]]; then
    success "Deployment complete!  Connect with:"
    echo -e "  ${CYAN}ssh ${DEPLOY_USER}@${NEW_HOSTNAME}.local${RESET}"
else
    die "Playbook failed with exit code $EXIT_CODE"
fi
