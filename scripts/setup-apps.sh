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

# Generate random passwords
ADGUARD_PASS=$(head -c 16 /dev/urandom | base64 | tr -d '/+=' | head -c 20)
HA_PASS=$(head -c 16 /dev/urandom | base64 | tr -d '/+=' | head -c 20)

# --- AdGuard Home ---
echo "Setting up AdGuard Home..."

# Check if AdGuard already has users configured
AG_USERS=$(ssh "${TARGET}" 'curl -sf http://localhost:3000/control/profile' 2>/dev/null || echo "AUTH_REQUIRED")

if [[ "${AG_USERS}" == "AUTH_REQUIRED" ]]; then
  echo "  AdGuard Home already has an account configured. Skipping."
  ADGUARD_PASS="(already configured)"
else
  # Generate bcrypt hash on the NUC
  AG_HASH=$(ssh "${TARGET}" "nix-shell -p apacheHttpd --run \"htpasswd -nbBC 10 '' '${ADGUARD_PASS}' | cut -d: -f2\"" 2>/dev/null)

  if [[ -z "${AG_HASH}" ]]; then
    # Fallback: use python3 for bcrypt
    AG_HASH=$(ssh "${TARGET}" "python3 -c \"import hashlib, base64, os; import crypt; print(crypt.crypt('${ADGUARD_PASS}', crypt.mksalt(crypt.METHOD_BLOWFISH)))\"" 2>/dev/null || true)
  fi

  if [[ -z "${AG_HASH}" ]]; then
    echo "  Warning: Could not generate bcrypt hash. Setting password via web API..."
    # Use the web API to set the password directly
    ssh "${TARGET}" "curl -sf http://localhost:3000/control/users/add \
      -H 'Content-Type: application/json' \
      -d '{\"name\":\"${ADGUARD_USER}\",\"password\":\"${ADGUARD_PASS}\"}'" > /dev/null
  else
    ssh "${TARGET}" "curl -sf http://localhost:3000/control/users/add \
      -H 'Content-Type: application/json' \
      -d '{\"name\":\"${ADGUARD_USER}\",\"password\":\"${ADGUARD_PASS}\"}'" > /dev/null
  fi
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
  HA_RESPONSE=$(ssh "${TARGET}" "curl -sf http://localhost:8123/api/onboarding/users \
    -H 'Content-Type: application/json' \
    -d '{
      \"client_id\": \"http://localhost:8123/\",
      \"name\": \"${HA_NAME}\",
      \"username\": \"${HA_USER}\",
      \"password\": \"${HA_PASS}\",
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
    echo "  Warning: Home Assistant onboarding returned unexpected response."
    echo "  ${HA_RESPONSE}"
    HA_PASS="(setup failed — configure manually)"
  fi
fi

# --- Store in 1Password ---
echo ""
echo "Updating 1Password..."

if op item get "${OP_ITEM}" &>/dev/null; then
  # Update existing item with app credentials
  op item edit "${OP_ITEM}" \
    "username=${ADGUARD_USER}" \
    "password=${ADGUARD_PASS}" \
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
