#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "========================================"
echo "  NixOS Homelab Setup"
echo "========================================"
echo ""

# Check we're running as root (required for partitioning/installing)
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root."
  echo "  sudo bash scripts/setup.sh"
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

# Generate hardware config
echo ""
echo "Generating hardware configuration..."
nixos-generate-config --root /mnt --show-hardware-config > "${REPO_DIR}/hosts/nuc/hardware.nix"
echo "Hardware config written to hosts/nuc/hardware.nix"

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
read -rp "Path to credentials JSON (e.g., ~/.cloudflared/<uuid>.json): " CF_CREDS
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
echo "  3. After boot, access AdGuard Home at http://192.168.1.50:3000"
echo "     (Run the setup wizard to set your admin password)"
echo "  4. Access Home Assistant at http://192.168.1.50:8123"
echo "     (Run the setup wizard to create your account)"
echo "  5. Point your router's DNS to the NUC's IP (192.168.1.50)"
echo "  6. Set up Colmena on your laptop for future deployments (see README)"
echo ""
