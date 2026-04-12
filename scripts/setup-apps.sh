#!/usr/bin/env bash
set -euo pipefail

# Sets up initial accounts for AdGuard Home and Home Assistant,
# then stores credentials in the existing 1Password "Homelab NUC" item.
#
# Run from your laptop after first boot (before manually visiting the web UIs).
#
# Usage: bash scripts/setup-apps.sh
#
# Prerequisites:
#   - SSH access to NUC (ssh nuc)
#   - op CLI signed in (eval $(op signin))
#   - Services running on the NUC

TARGET="nuc"
OP_ITEM="Homelab NUC"
ADGUARD_USER="admin"
HA_USER="admin"
HA_NAME="Admin"

echo "========================================"
echo "  Set Up Homelab App Accounts"
echo "========================================"
echo ""

# Check SSH
if ! ssh -o ConnectTimeout=5 "${TARGET}" 'true' &>/dev/null; then
  echo "Error: Cannot SSH into ${TARGET}."
  exit 1
fi

# Check op
if ! op whoami &>/dev/null; then
  echo "Error: 1Password CLI not signed in."
  echo "  Run: eval \$(op signin)"
  exit 1
fi

# Generate strong passwords (30 chars, alphanumeric + symbols)
ADGUARD_PASS=$(op item create --generate-password='30,letters,digits,symbols' --dry-run --category=login --title=tmp 2>/dev/null | grep -o 'password.*' | head -1 | cut -d'"' -f3 || head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 30)
HA_PASS=$(op item create --generate-password='30,letters,digits,symbols' --dry-run --category=login --title=tmp 2>/dev/null | grep -o 'password.*' | head -1 | cut -d'"' -f3 || head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 30)

# Fallback if op password gen didn't work
if [[ -z "${ADGUARD_PASS}" ]]; then
  ADGUARD_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 30)
fi
if [[ -z "${HA_PASS}" ]]; then
  HA_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 30)
fi

# --- AdGuard Home ---
echo "Setting up AdGuard Home..."

# Check if AdGuard already has users configured
AG_CONFIG=$(ssh "${TARGET}" 'sudo grep "^users:" /var/lib/AdGuardHome/AdGuardHome.yaml' 2>/dev/null || echo "")
AG_HAS_USERS=$(ssh "${TARGET}" 'sudo grep -A1 "^users:" /var/lib/AdGuardHome/AdGuardHome.yaml | grep -c "name:" || echo 0' 2>/dev/null)

if [[ "${AG_HAS_USERS}" -gt 0 ]]; then
  echo "  AdGuard Home already has users configured. Skipping."
  ADGUARD_PASS="(already configured)"
else
  # Generate bcrypt hash on the NUC
  echo "  Generating password hash (may take a moment)..."
  ESCAPED_PASS=$(printf '%s' "${ADGUARD_PASS}" | sed 's/\\/\\\\/g; s/"/\\"/g')
  AG_HASH=$(ssh "${TARGET}" "nix-shell -p python3Packages.bcrypt --run 'python3 -c \"import bcrypt; print(bcrypt.hashpw(b\\\"${ESCAPED_PASS}\\\", bcrypt.gensalt()).decode())\"'" 2>/dev/null)

  if [[ -z "${AG_HASH}" ]]; then
    echo "  Error: Failed to generate bcrypt hash."
    exit 1
  fi

  # Stop AdGuard, inject user into config, restart
  ssh "${TARGET}" "sudo systemctl stop adguardhome"
  ssh "${TARGET}" "sudo sed -i 's/^users: \[\]/users:\n- name: ${ADGUARD_USER}\n  password: ${AG_HASH}/' /var/lib/AdGuardHome/AdGuardHome.yaml"
  ssh "${TARGET}" "sudo systemctl start adguardhome"

  echo "  ✓ AdGuard Home account created (user: ${ADGUARD_USER})"
fi

# --- Home Assistant ---
echo "Setting up Home Assistant..."

# Check if HA onboarding is still available
HA_ONBOARD=$(ssh "${TARGET}" 'curl -sf http://localhost:8123/api/onboarding' 2>/dev/null || echo "[]")
HA_USER_DONE=$(echo "${HA_ONBOARD}" | grep -o '"step":"user","done":false' || true)

if [[ -z "${HA_USER_DONE}" ]]; then
  echo "  Home Assistant already onboarded. Skipping."
  HA_PASS="(already configured)"
else
  # Create the initial user via onboarding API
  ESCAPED_HA_PASS=$(printf '%s' "${HA_PASS}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
  HA_RESPONSE=$(ssh "${TARGET}" "curl -sf http://localhost:8123/api/onboarding/users \
    -H 'Content-Type: application/json' \
    -d '{
      \"client_id\": \"http://localhost:8123/\",
      \"name\": \"${HA_NAME}\",
      \"username\": \"${HA_USER}\",
      \"password\": ${ESCAPED_HA_PASS},
      \"language\": \"en\"
    }'" 2>/dev/null)

  if echo "${HA_RESPONSE}" | grep -q "auth_code"; then
    echo "  ✓ Home Assistant account created (user: ${HA_USER})"

    # Complete remaining onboarding steps
    HA_AUTH=$(echo "${HA_RESPONSE}" | grep -o '"auth_code":"[^"]*"' | cut -d'"' -f4)

    # Get an access token
    HA_TOKEN_RESP=$(ssh "${TARGET}" "curl -sf http://localhost:8123/auth/token \
      -d 'grant_type=authorization_code&code=${HA_AUTH}&client_id=http://localhost:8123/'" 2>/dev/null || true)

    if [[ -n "${HA_TOKEN_RESP}" ]]; then
      HA_TOKEN=$(echo "${HA_TOKEN_RESP}" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

      # Complete core config step
      ssh "${TARGET}" "curl -sf http://localhost:8123/api/onboarding/core_config \
        -H 'Authorization: Bearer ${HA_TOKEN}' \
        -H 'Content-Type: application/json' \
        -d '{\"client_id\": \"http://localhost:8123/\"}'" > /dev/null 2>&1 || true

      # Skip analytics
      ssh "${TARGET}" "curl -sf http://localhost:8123/api/onboarding/analytics \
        -H 'Authorization: Bearer ${HA_TOKEN}' \
        -H 'Content-Type: application/json' \
        -d '{\"client_id\": \"http://localhost:8123/\"}'" > /dev/null 2>&1 || true

      # Skip integrations
      ssh "${TARGET}" "curl -sf http://localhost:8123/api/onboarding/integration \
        -H 'Authorization: Bearer ${HA_TOKEN}' \
        -H 'Content-Type: application/json' \
        -d '{\"client_id\": \"http://localhost:8123/\"}'" > /dev/null 2>&1 || true

      echo "  ✓ Home Assistant onboarding completed"
    fi
  else
    echo "  Warning: Unexpected response from Home Assistant."
    echo "  ${HA_RESPONSE}"
    HA_PASS="(setup failed — configure manually at http://192.168.178.83:8123)"
  fi
fi

# --- Store in 1Password ---
echo ""
echo "Updating 1Password..."

if op item get "${OP_ITEM}" &>/dev/null; then
  op item edit "${OP_ITEM}" \
    "AdGuard Home Username[text]=${ADGUARD_USER}" \
    "AdGuard Home Password[password]=${ADGUARD_PASS}" \
    "Home Assistant Username[text]=${HA_USER}" \
    "Home Assistant Password[password]=${HA_PASS}" \
    > /dev/null
  echo "  ✓ Updated '${OP_ITEM}' with app credentials"
else
  echo "  Warning: '${OP_ITEM}' not found in 1Password. Run secrets-to-op.sh first."
  echo ""
  echo "  Credentials (save these manually):"
  echo "    AdGuard Home: ${ADGUARD_USER} / ${ADGUARD_PASS}"
  echo "    Home Assistant: ${HA_USER} / ${HA_PASS}"
fi

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "  AdGuard Home:    http://192.168.178.83:3000  (${ADGUARD_USER})"
echo "  Home Assistant:  http://192.168.178.83:8123  (${HA_USER})"
echo "  Dashboard:       http://192.168.178.83:8082"
echo ""
