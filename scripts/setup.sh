#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Enable flakes on the live USB where they're not enabled by default
export NIX_CONFIG="experimental-features = nix-command flakes"

echo "========================================"
echo "  NixOS Homelab Setup"
echo "========================================"
echo ""

# Check we're running as root (required for partitioning/installing)
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root."
  echo "  sudo -E bash scripts/setup.sh"
  exit 1
fi

# Detect disk
echo "Available disks:"
lsblk -d -o NAME,SIZE,TYPE | grep disk
echo ""
read -rp "Target disk (e.g., sda or nvme0n1): " DISK_NAME
TARGET_DISK="/dev/${DISK_NAME}"

if [[ ! -b "${TARGET_DISK}" ]]; then
  echo "Error: ${TARGET_DISK} is not a valid block device."
  exit 1
fi

echo ""
echo "WARNING: This will ERASE ALL DATA on ${TARGET_DISK}."
read -rp "Type 'yes' to continue: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

# Update disk device in disk.nix if needed
CURRENT_DEVICE=$(grep 'device =' "${REPO_DIR}/hosts/nuc/disk.nix" | head -1 | sed 's/.*"\(.*\)".*/\1/')
if [[ "${TARGET_DISK}" != "${CURRENT_DEVICE}" ]]; then
  echo "Updating disk.nix to use ${TARGET_DISK}..."
  sed -i "s|device = lib.mkDefault \".*\"|device = lib.mkDefault \"${TARGET_DISK}\"|" "${REPO_DIR}/hosts/nuc/disk.nix"
fi

# Partition and format with disko
echo ""
echo "Partitioning ${TARGET_DISK}..."
nix run github:nix-community/disko -- --mode disko "${REPO_DIR}/hosts/nuc/disk.nix"
echo "Disk partitioned and mounted at /mnt."

# hardware.nix is committed to the repo — no generation needed.
# Disko manages filesystems (disk.nix), hardware.nix only has kernel/CPU config.
# If you change hardware, update hosts/nuc/hardware.nix manually:
#   nixos-generate-config --root /mnt --show-hardware-config
#   Then remove fileSystems and swapDevices blocks (disko owns those).

# Secrets setup
echo ""
echo "========================================"
echo "  Secrets Setup"
echo "========================================"
mkdir -p /mnt/etc/nixos/secrets

echo ""
echo "Cloudflare Tunnel credentials JSON."
echo "Create a tunnel first: cloudflared tunnel create homelab"
echo "Then copy the credentials file path shown in the output."
echo "Leave blank to skip (you can set it up manually after boot)."
read -rp "Path to credentials JSON: " CF_CREDS
if [[ -n "${CF_CREDS}" && -f "${CF_CREDS}" ]]; then
  cp "${CF_CREDS}" /mnt/etc/nixos/secrets/cloudflared-tunnel.json
  chmod 600 /mnt/etc/nixos/secrets/cloudflared-tunnel.json
  echo "Saved."
else
  echo "Skipped. Set up Cloudflare Tunnel manually after boot."
fi

# Copy repo to target for the flake reference
echo ""
echo "Copying configuration to /mnt/etc/nixos/homelab..."
mkdir -p /mnt/etc/nixos
rm -rf /mnt/etc/nixos/homelab
cp -r "${REPO_DIR}" /mnt/etc/nixos/homelab

# Install NixOS
echo ""
echo "Installing NixOS (this may take a while)..."
nixos-install --flake "/mnt/etc/nixos/homelab#nuc" --no-root-passwd

echo ""
echo "========================================"
echo "  Installation Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Remove the USB drive"
echo "  2. Reboot: reboot"
echo "  3. SSH in: ssh admin@<nuc-ip> (initial password: changeme)"
echo "  4. Access AdGuard Home at http://<nuc-ip>:3000"
echo "  5. Access Home Assistant at http://<nuc-ip>:8123"
echo "  6. Point your router's DNS to the NUC's IP"
echo ""
