#!/usr/bin/env bash
set -euo pipefail

# Pulls homelab secrets from 1Password and writes them to the NUC.
# Run this from your laptop during a fresh install, after NixOS is installed
# and SSH works.
#
# Usage: bash scripts/secrets-from-op.sh [target]
#   target: SSH host (default: nuc)
#
# Prerequisites:
#   - op CLI installed and signed in (run `eval $(op signin)` first)
#   - SSH access to the target
#   - '${ITEM_NAME}' item exists in 1Password (created by secrets-to-op.sh)

ITEM_NAME="Homelab NUC"
TARGET="${1:-nuc}"

echo "========================================"
echo "  Restore Homelab Secrets from 1Password"
echo "========================================"
echo ""

# Check op is authenticated
if ! op whoami &>/dev/null; then
  echo "Error: 1Password CLI not signed in."
  echo "  Run: eval \$(op signin)"
  exit 1
fi

# Check the item exists
if ! op item get "${ITEM_NAME}" &>/dev/null; then
  echo "Error: '${ITEM_NAME}' not found in 1Password."
  echo "  Run secrets-to-op.sh first to store the secrets."
  exit 1
fi

# Check SSH access
if ! ssh -o ConnectTimeout=5 "${TARGET}" 'true' &>/dev/null; then
  echo "Error: Cannot SSH into ${TARGET}."
  exit 1
fi

echo "Fetching secrets from 1Password..."

RESTIC_PASSWORD=$(op item get "${ITEM_NAME}" --fields restic_password)
echo "  ✓ Restic password"

TUNNEL_CREDS=$(op item get "${ITEM_NAME}" --fields tunnel_credentials)
echo "  ✓ Cloudflare tunnel credentials"

ORIGIN_CERT=$(op item get "${ITEM_NAME}" --fields origin_cert)
echo "  ✓ Cloudflare origin certificate"

echo ""
echo "Writing secrets to ${TARGET}..."

ssh "${TARGET}" "sudo mkdir -p /etc/nixos/secrets"

echo "${RESTIC_PASSWORD}" | ssh "${TARGET}" "sudo tee /etc/nixos/secrets/restic-password > /dev/null"
ssh "${TARGET}" "sudo chmod 644 /etc/nixos/secrets/restic-password"
echo "  ✓ Restic password"

echo "${TUNNEL_CREDS}" | ssh "${TARGET}" "sudo tee /etc/nixos/secrets/cloudflared-tunnel.json > /dev/null"
ssh "${TARGET}" "sudo chmod 644 /etc/nixos/secrets/cloudflared-tunnel.json"
echo "  ✓ Cloudflare tunnel credentials"

echo "${ORIGIN_CERT}" | ssh "${TARGET}" "sudo tee /etc/nixos/secrets/cloudflared-cert.pem > /dev/null"
ssh "${TARGET}" "sudo chmod 644 /etc/nixos/secrets/cloudflared-cert.pem"
echo "  ✓ Cloudflare origin certificate"

echo ""
echo "✓ All secrets restored to ${TARGET}"
echo ""
echo "Restart affected services:"
echo "  ssh ${TARGET} 'sudo systemctl restart cloudflared-tunnel-homelab restic-backups-usb.timer'"
