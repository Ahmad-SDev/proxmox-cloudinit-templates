#!/usr/bin/env bash
# make-template.sh - build a Proxmox VE cloud-init VM template from an official cloud image.
# Run on a Proxmox node as root. Clones of the template boot in seconds with your
# user, SSH key and network set through cloud-init.
set -euo pipefail

VMID=""
DISTRO="debian12"
STORAGE="local-lvm"
BRIDGE="vmbr0"
CORES=2
MEMORY=2048
DISK_SIZE="20G"
CACHE_DIR="/var/lib/vz/template/cloud"

usage() {
  cat <<EOF
Usage: $0 --vmid ID [options]

  --vmid ID         VM id for the template (required, must be free)
  --distro NAME     debian12 | debian13 | ubuntu2204 | ubuntu2404 (default: $DISTRO)
  --storage NAME    target storage for the disk (default: $STORAGE)
  --bridge NAME     network bridge (default: $BRIDGE)
  --cores N         default vCPUs (default: $CORES)
  --memory MB       default RAM in MB (default: $MEMORY)
  --disk-size SIZE  disk size after resize, e.g. 20G (default: $DISK_SIZE)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vmid)      VMID="$2"; shift 2 ;;
    --distro)    DISTRO="$2"; shift 2 ;;
    --storage)   STORAGE="$2"; shift 2 ;;
    --bridge)    BRIDGE="$2"; shift 2 ;;
    --cores)     CORES="$2"; shift 2 ;;
    --memory)    MEMORY="$2"; shift 2 ;;
    --disk-size) DISK_SIZE="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

[[ $EUID -eq 0 ]] || die "run as root on a Proxmox node"
command -v qm >/dev/null || die "qm not found; this must run on Proxmox VE"
[[ "$VMID" =~ ^[0-9]+$ ]] || die "--vmid is required"
qm status "$VMID" &>/dev/null && die "VM $VMID already exists"
pvesm status --storage "$STORAGE" &>/dev/null || die "storage $STORAGE not found"

case "$DISTRO" in
  debian12)   BASE="https://cloud.debian.org/images/cloud/bookworm/latest"
              IMG="debian-12-genericcloud-amd64.qcow2"; SUMS="SHA512SUMS"; HASH="sha512sum" ;;
  debian13)   BASE="https://cloud.debian.org/images/cloud/trixie/latest"
              IMG="debian-13-genericcloud-amd64.qcow2"; SUMS="SHA512SUMS"; HASH="sha512sum" ;;
  ubuntu2204) BASE="https://cloud-images.ubuntu.com/jammy/current"
              IMG="jammy-server-cloudimg-amd64.img"; SUMS="SHA256SUMS"; HASH="sha256sum" ;;
  ubuntu2404) BASE="https://cloud-images.ubuntu.com/noble/current"
              IMG="noble-server-cloudimg-amd64.img"; SUMS="SHA256SUMS"; HASH="sha256sum" ;;
  *) die "unknown distro: $DISTRO" ;;
esac

mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

log "Downloading $IMG (cached if unchanged)"
curl -fsSL -o "$SUMS.$DISTRO" "$BASE/$SUMS"
curl -fL --progress-bar -z "$IMG" -o "$IMG" "$BASE/$IMG"

log "Verifying checksum"
grep -E "[ *]$IMG\$" "$SUMS.$DISTRO" | $HASH -c - \
  || die "checksum mismatch for $IMG; delete it and run again"

NAME="tpl-$DISTRO"
log "Creating VM $VMID ($NAME)"
qm create "$VMID" \
  --name "$NAME" \
  --ostype l26 \
  --cores "$CORES" --memory "$MEMORY" \
  --cpu host \
  --net0 "virtio,bridge=$BRIDGE" \
  --scsihw virtio-scsi-single \
  --serial0 socket --vga serial0 \
  --agent enabled=1,fstrim_cloned_disks=1

log "Importing disk to $STORAGE"
qm disk import "$VMID" "$IMG" "$STORAGE" --format raw >/dev/null
DISK="$(qm config "$VMID" | awk -F': ' '/^unused0:/ {print $2}')"
[[ -n "$DISK" ]] || die "imported disk not found"

qm set "$VMID" \
  --scsi0 "$DISK,discard=on,iothread=1,ssd=1" \
  --boot order=scsi0 \
  --ide2 "$STORAGE:cloudinit" \
  --ipconfig0 ip=dhcp \
  --ciupgrade 1 >/dev/null
qm disk resize "$VMID" scsi0 "$DISK_SIZE"

log "Converting to template"
qm template "$VMID"

cat <<EOF

Template $VMID ($NAME) is ready. Create a VM from it:

  qm clone $VMID 200 --name web01 --full
  qm set 200 --ciuser deploy --sshkeys ~/.ssh/id_ed25519.pub \\
             --ipconfig0 ip=203.0.113.10/24,gw=203.0.113.1
  qm start 200

Install qemu-guest-agent inside the VM (or via a cloud-init snippet) for IP reporting and clean shutdowns.
EOF
