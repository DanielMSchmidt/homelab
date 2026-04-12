#!/usr/bin/env bash
set -euo pipefail

# Creates a Cloudflare Tunnel and DNS routes for all homelab services.
# Run from your laptop before or after NixOS setup.
#
# Usage: bash scripts/setup-tunnel.sh
#
# Prerequisites:
#   - Nix installed
#   - cloudflared logged in (nix run nixpkgs#cloudflared -- tunnel login)

TUNNEL_NAME="homelab"
DOMAIN="danielmschmidt.de"
SUBDOMAINS=("adguard" "hass" "home" "norish")
CLOUDFLARED="nix run nixpkgs#cloudflared --"

echo "========================================"
echo "  Set Up Cloudflare Tunnel"
echo "========================================"
echo ""

# Check if tunnel already exists
if ${CLOUDFLARED} tunnel list | grep -q "${TUNNEL_NAME}"; then
  echo "Tunnel '${TUNNEL_NAME}' already exists."
else
  echo "Creating tunnel '${TUNNEL_NAME}'..."
  ${CLOUDFLARED} tunnel create "${TUNNEL_NAME}"
fi

echo ""
echo "Setting up DNS routes..."

for sub in "${SUBDOMAINS[@]}"; do
  FQDN="${sub}.${DOMAIN}"
  echo -n "  ${FQDN} → "
  if ${CLOUDFLARED} tunnel route dns "${TUNNEL_NAME}" "${FQDN}" 2>&1 | grep -q "already exists"; then
    echo "already exists"
  else
    echo "created"
  fi
done

# Find credentials file
CREDS_FILE=$(find ~/.cloudflared -name "*.json" -not -name "cert.pem" | head -1)
CERT_FILE="${HOME}/.cloudflared/cert.pem"

echo ""
echo "========================================"
echo "  Tunnel Ready!"
echo "========================================"
echo ""
echo "Credentials: ${CREDS_FILE:-not found}"
echo "Origin cert: ${CERT_FILE}"
echo ""
echo "Next steps:"
echo "  1. Run the NixOS setup script (scripts/setup.sh)"
echo "     It will ask for these file paths."
echo ""
echo "  Or copy them manually to the NUC:"
echo "     scp ${CREDS_FILE} nuc:/tmp/cf-creds.json"
echo "     scp ${CERT_FILE} nuc:/tmp/cf-cert.pem"
echo ""
