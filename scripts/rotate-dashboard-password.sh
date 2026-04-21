#!/usr/bin/env bash
set -euo pipefail

# Rotates the homepage dashboard basic auth credentials.
# Generates new random username + password, updates caddy.nix, deploys, and stores in 1Password.
#
# Usage: bash scripts/rotate-dashboard-password.sh
#
# Prerequisites:
#   - op CLI installed and signed in (run `eval $(op signin)` first)
#   - SSH access to the NUC (ssh nuc)
#   - Run from the repo root

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CADDY_NIX="${REPO_ROOT}/modules/caddy.nix"
OP_ITEM_NAME="Homelab Dashboard (home.danielmschmidt.de)"

echo "========================================"
echo "  Rotate Dashboard Credentials"
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

# Check we're in the repo root
if [[ ! -f "${CADDY_NIX}" ]]; then
  echo "Error: Cannot find ${CADDY_NIX}. Run this script from the repo root."
  exit 1
fi

# Generate new credentials
NEW_USER=$(openssl rand -hex 8)
NEW_PASS=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
echo "  Generated new username: ${NEW_USER}"
echo "  Generated new password: (hidden)"

# Hash the password using caddy on the NUC (find binary path from the systemd service)
CADDY_BIN=$(ssh nuc "grep -oP '/nix/store/[^ ]+/bin/caddy' /etc/systemd/system/caddy.service | head -1")
if [[ -z "${CADDY_BIN}" ]]; then
  echo "Error: Cannot find caddy binary on NUC."
  exit 1
fi
NEW_HASH=$(echo "${NEW_PASS}" | ssh nuc "${CADDY_BIN} hash-password --algorithm bcrypt")
echo "  Hashed password via caddy on NUC"

# Update caddy.nix — replace the basicauth line
# Match the line with a username (hex) and bcrypt hash
if ! grep -q 'basicauth' "${CADDY_NIX}"; then
  echo "Error: No basicauth block found in ${CADDY_NIX}."
  exit 1
fi

# Use perl with env vars to avoid bash expanding $ signs in the bcrypt hash
NEW_USER="${NEW_USER}" NEW_HASH="${NEW_HASH}" \
  perl -pi -e 's/[0-9a-f]{16} \$2a\$[^ ]+/$ENV{NEW_USER} $ENV{NEW_HASH}/' "${CADDY_NIX}"
echo "  Updated ${CADDY_NIX}"

# Deploy
echo ""
echo "Deploying..."
(cd "${REPO_ROOT}" && ./deploy.sh)

# Store in 1Password (update existing or create new)
echo ""
echo "Storing credentials in 1Password..."
if op item get "${OP_ITEM_NAME}" &>/dev/null; then
  op item edit "${OP_ITEM_NAME}" \
    "username=${NEW_USER}" \
    "password=${NEW_PASS}" \
    > /dev/null
  echo "  Updated existing '${OP_ITEM_NAME}' item"
else
  op item create \
    --category=login \
    --title="${OP_ITEM_NAME}" \
    --url="https://home.danielmschmidt.de" \
    "username=${NEW_USER}" \
    "password=${NEW_PASS}" \
    > /dev/null
  echo "  Created '${OP_ITEM_NAME}' item"
fi

echo ""
echo "Done. New credentials are live and saved in 1Password."
echo "Your browser will prompt for the new credentials on next visit."
