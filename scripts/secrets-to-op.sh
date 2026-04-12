#!/usr/bin/env bash
set -euo pipefail

# Stores all homelab secrets in 1Password so a fresh install can pull them automatically.
# Run this once from your laptop after initial setup.
#
# Usage: bash scripts/secrets-to-op.sh
#
# Prerequisites:
#   - op CLI installed and signed in (run `eval $(op signin)` first)
#   - SSH access to the NUC (ssh nuc)
#   - Cloudflare credentials in ~/.cloudflared/

ITEM_NAME="Homelab NUC"

echo "========================================"
echo "  Store Homelab Secrets in 1Password"
echo "========================================"
echo ""

# Check op is authenticated
if ! op whoami &>/dev/null; then
  echo "Error: 1Password CLI not signed in."
  echo "  Run: eval \$(op signin)"
  exit 1
fi

# Check SSH access
if ! ssh -o ConnectTimeout=5 nuc 'true' &>/dev/null; then
  echo "Error: Cannot SSH into NUC. Make sure 'ssh nuc' works."
  exit 1
fi

echo "Fetching secrets from NUC..."

# Fetch secrets from the NUC
RESTIC_PASSWORD=$(ssh nuc 'sudo cat /etc/nixos/secrets/restic-password')
echo "  ✓ Restic password"

TUNNEL_CREDS=$(ssh nuc 'sudo cat /etc/nixos/secrets/cloudflared-tunnel.json')
echo "  ✓ Cloudflare tunnel credentials"

ORIGIN_CERT=$(ssh nuc 'sudo cat /etc/nixos/secrets/cloudflared-cert.pem')
echo "  ✓ Cloudflare origin certificate"

NORISH_ENV=$(ssh nuc 'sudo cat /etc/nixos/secrets/norish-env')
echo "  ✓ Norish env file"

CROWDSEC_BOUNCER=$(ssh nuc 'sudo cat /etc/nixos/secrets/crowdsec-bouncer.yaml')
echo "  ✓ CrowdSec bouncer config"

echo ""

# Delete existing item if it exists (to avoid duplicates)
if op item get "${ITEM_NAME}" &>/dev/null; then
  echo "Updating existing '${ITEM_NAME}' item..."
  op item delete "${ITEM_NAME}" --archive
fi

echo "Creating '${ITEM_NAME}' in 1Password..."

# Create the item with all secrets as fields
op item create \
  --category=login \
  --title="${ITEM_NAME}" \
  --url="http://192.168.178.83:8082" \
  "username=admin" \
  "password=changeme" \
  "restic_password[password]=${RESTIC_PASSWORD}" \
  "tunnel_credentials[password]=${TUNNEL_CREDS}" \
  "origin_cert[password]=${ORIGIN_CERT}" \
  "norish_env[password]=${NORISH_ENV}" \
  "crowdsec_bouncer[password]=${CROWDSEC_BOUNCER}" \
  "SSH Command[text]=ssh nuc" \
  "AdGuard Home[text]=http://192.168.178.83:3000" \
  "Home Assistant[text]=http://192.168.178.83:8123" \
  > /dev/null

echo ""
echo "✓ All secrets stored in 1Password as '${ITEM_NAME}'"
echo ""
echo "To restore on a fresh install, run:"
echo "  bash scripts/secrets-from-op.sh"
