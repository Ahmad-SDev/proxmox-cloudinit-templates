# proxmox-cloudinit-templates

Build **Proxmox VE** VM templates from official Debian and Ubuntu cloud images in one command. Every clone boots in seconds with its user, SSH key and IP set by cloud-init, which is how I provision customer VPS at scale.

## Supported images

| `--distro` | Image |
|---|---|
| `debian12` | Debian 12 Bookworm genericcloud |
| `debian13` | Debian 13 Trixie genericcloud |
| `ubuntu2204` | Ubuntu 22.04 Jammy cloud image |
| `ubuntu2404` | Ubuntu 24.04 Noble cloud image |

## What the template gets

- Image **checksum verified** against the vendor's SHA sums before import
- VirtIO SCSI single with **iothread, discard and SSD** emulation for fast thin disks
- `cpu host`, serial console, **QEMU guest agent** with fstrim on clone
- Cloud-init drive with DHCP default and package upgrade on first boot
- Disk resized to your chosen size, then converted to a template

## Usage

Run on a Proxmox node as root:

```bash
./make-template.sh --vmid 9000 --distro debian12 --storage local-lvm --disk-size 20G
./make-template.sh --vmid 9001 --distro ubuntu2404 --storage local-lvm
```

Then create a VM from it:

```bash
qm clone 9000 200 --name web01 --full
qm set 200 --ciuser deploy --sshkeys ~/.ssh/id_ed25519.pub \
           --ipconfig0 ip=203.0.113.10/24,gw=203.0.113.1
qm start 200
```

The same `qm clone` + `qm set` calls are what a billing system's provisioning module runs when a customer orders a VPS.

Requires Proxmox VE 8 or newer (`qm disk import`).

## License

MIT
