#!/usr/bin/env bash
set -euo pipefail

# Restores service data from restic backup on the USB stick.
# Run from your laptop after a fresh install + secrets-from-op.sh.
#
# Usage: bash scripts/restore-backup.sh [snapshot]
#   snapshot: restic snapshot ID (default: latest)

TARGET="nuc"
SNAPSHOT="${1:-latest}"
REPO="/mnt/backup/restic"
PASS="/etc/nixos/secrets/restic-password"

echo "========================================"
echo "  Restore Homelab from Backup"
echo "========================================"
echo ""

# Check SSH access
if ! ssh -o ConnectTimeout=5 "${TARGET}" 'true' &>/dev/null; then
  echo "Error: Cannot SSH into ${TARGET}."
  exit 1
fi

# Check backup drive is mounted
if ! ssh "${TARGET}" 'mountpoint -q /mnt/backup' &>/dev/null; then
  echo "Error: Backup USB not mounted at /mnt/backup."
  echo "  Plug in the USB stick and run: ssh nuc 'sudo mount /dev/disk/by-label/backup /mnt/backup'"
  exit 1
fi

# Check restic password exists
if ! ssh "${TARGET}" "test -f ${PASS}" &>/dev/null; then
  echo "Error: Restic password not found at ${PASS}."
  echo "  Run scripts/secrets-from-op.sh first to restore secrets."
  exit 1
fi

# List available snapshots
echo "Available snapshots:"
ssh "${TARGET}" "sudo restic -r ${REPO} --password-file ${PASS} snapshots --compact"
echo ""

if [[ "${SNAPSHOT}" == "latest" ]]; then
  echo "Restoring from latest snapshot..."
else
  echo "Restoring from snapshot: ${SNAPSHOT}..."
fi
echo ""

# Stop services
echo "Stopping services..."
ssh "${TARGET}" "sudo systemctl stop home-assistant adguardhome"
echo "  ✓ Services stopped"

# Restore
echo "Restoring data (this may take a moment)..."
ssh "${TARGET}" "sudo restic -r ${REPO} --password-file ${PASS} restore ${SNAPSHOT} --target /"
echo "  ✓ Data restored"

# Restart services
echo "Starting services..."
ssh "${TARGET}" "sudo systemctl start adguardhome home-assistant"
echo "  ✓ Services started"

echo ""
echo "========================================"
echo "  Restore Complete!"
echo "========================================"
echo ""
echo "Verify everything works:"
echo "  AdGuard Home:   http://192.168.178.83:3000"
echo "  Home Assistant:  http://192.168.178.83:8123"
echo "  Dashboard:       http://192.168.178.83:8082"
