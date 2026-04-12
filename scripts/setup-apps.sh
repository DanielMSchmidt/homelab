#!/usr/bin/env bash
set -euo pipefail

# Sets up initial accounts for AdGuard Home and Home Assistant,
# then stores credentials in the existing 1Password "Homelab NUC" item.
#
# Usage: bash scripts/setup-apps.sh

TARGET="nuc"
FORCE=false
if [[ "${1:-}" == "--force" ]]; then
  FORCE=true
fi

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

# Generate passwords (alphanumeric only — safe for shell/JSON/YAML)
ADGUARD_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | head -c 30)
HA_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | head -c 30)

# --- AdGuard Home ---
echo "Setting up AdGuard Home..."

AG_HAS_USERS=$(ssh "${TARGET}" 'sudo grep -A1 "^users:" /var/lib/AdGuardHome/AdGuardHome.yaml | grep -c "name:" 2>/dev/null || echo 0' | tail -1)

if [[ "${AG_HAS_USERS}" -gt 0 ]] && ! $FORCE; then
  echo "  Already has users configured. Skipping. (use --force to recreate)"
  ADGUARD_PASS="(already configured)"
else
  echo "  Generating password hash (downloads python+bcrypt on first run)..."

  # Send password to NUC via temp file, generate bcrypt hash there
  echo -n "${ADGUARD_PASS}" | ssh "${TARGET}" 'cat > /tmp/.ag-pass'

  # Write the hash script and run it
  cat <<'REMOTE_SCRIPT' | ssh "${TARGET}" 'cat > /tmp/setup-adguard.sh && chmod +x /tmp/setup-adguard.sh'
#!/usr/bin/env bash
set -euo pipefail

# Generate bcrypt hash from password file
HASH=$(nix-shell -p python3Packages.bcrypt --run "python3 -c \"
import bcrypt
pw = open('/tmp/.ag-pass','rb').read()
print(bcrypt.hashpw(pw, bcrypt.gensalt()).decode())
\"")
rm -f /tmp/.ag-pass

# Stop AdGuard
sudo systemctl stop adguardhome

# Replace users section using awk (handles both empty [] and existing users)
sudo awk -v hash="$HASH" '
BEGIN { skip=0 }
/^users:/ {
  print "users:"
  print "- name: admin"
  print "  password: " hash
  skip=1
  next
}
skip && /^[^ -]/ { skip=0 }
skip { next }
{ print }
' /var/lib/AdGuardHome/AdGuardHome.yaml > /tmp/adguard-fixed.yaml

sudo cp /tmp/adguard-fixed.yaml /var/lib/AdGuardHome/AdGuardHome.yaml
rm -f /tmp/adguard-fixed.yaml

# Restart AdGuard
sudo systemctl start adguardhome
echo "DONE"
REMOTE_SCRIPT

  RESULT=$(ssh "${TARGET}" "bash /tmp/setup-adguard.sh; rm -f /tmp/setup-adguard.sh" 2>&1)

  if echo "${RESULT}" | grep -q "DONE"; then
    echo "  ✓ AdGuard Home account created (user: admin)"
  else
    echo "  Error setting up AdGuard Home:"
    echo "  ${RESULT}"
    ADGUARD_PASS="(setup failed)"
  fi
fi

# --- Home Assistant ---
echo "Setting up Home Assistant..."

HA_ONBOARD=$(ssh "${TARGET}" 'curl -sf http://localhost:8123/api/onboarding' 2>/dev/null || echo "[]")

if ! echo "${HA_ONBOARD}" | grep -q '"step":"user","done":false'; then
  if $FORCE; then
    echo "  Already onboarded. Cannot recreate HA account via API."
    echo "  The password from the original setup will not be stored."
  fi
  echo "  Already onboarded. Skipping."
  HA_PASS="(already configured)"
else
  # Write JSON payload to NUC, then curl from there
  cat > /tmp/.ha-payload.json <<EOF
{
  "client_id": "http://localhost:8123/",
  "name": "Admin",
  "username": "admin",
  "password": "${HA_PASS}",
  "language": "en"
}
EOF
  scp -q /tmp/.ha-payload.json "${TARGET}":/tmp/.ha-payload.json
  rm -f /tmp/.ha-payload.json

  HA_RESPONSE=$(ssh "${TARGET}" 'curl -sf http://localhost:8123/api/onboarding/users -H "Content-Type: application/json" -d @/tmp/.ha-payload.json; rm -f /tmp/.ha-payload.json' 2>/dev/null)

  if echo "${HA_RESPONSE}" | grep -q "auth_code"; then
    echo "  ✓ Home Assistant account created (user: admin)"

    # Complete remaining onboarding steps
    HA_AUTH=$(echo "${HA_RESPONSE}" | grep -o '"auth_code":"[^"]*"' | cut -d'"' -f4)
    HA_TOKEN_RESP=$(ssh "${TARGET}" "curl -sf http://localhost:8123/auth/token -d 'grant_type=authorization_code&code=${HA_AUTH}&client_id=http://localhost:8123/'" 2>/dev/null || true)

    if [[ -n "${HA_TOKEN_RESP}" ]]; then
      HA_TOKEN=$(echo "${HA_TOKEN_RESP}" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
      for step in core_config analytics integration; do
        ssh "${TARGET}" "curl -sf http://localhost:8123/api/onboarding/${step} -H 'Authorization: Bearer ${HA_TOKEN}' -H 'Content-Type: application/json' -d '{\"client_id\":\"http://localhost:8123/\"}'" > /dev/null 2>&1 || true
      done
      echo "  ✓ Home Assistant onboarding completed"
    fi
  else
    echo "  Error: ${HA_RESPONSE}"
    HA_PASS="(setup failed — configure manually at http://192.168.178.83:8123)"
  fi
fi

# --- Norish ---
echo "Setting up Norish..."

NORISH_KEY_EXISTS=$(ssh "${TARGET}" 'sudo test -f /etc/nixos/secrets/norish-env && echo "yes" || echo "no"' | tail -1)

if [[ "${NORISH_KEY_EXISTS}" == "yes" ]] && ! $FORCE; then
  echo "  Master key already exists. Skipping. (use --force to recreate)"
  NORISH_KEY="(already configured)"
else
  NORISH_KEY=$(openssl rand -base64 32)
  echo "MASTER_KEY=${NORISH_KEY}" | ssh "${TARGET}" "sudo tee /etc/nixos/secrets/norish-env > /dev/null"
  ssh "${TARGET}" "sudo chmod 644 /etc/nixos/secrets/norish-env"
  echo "  ✓ Norish master key generated and written to /etc/nixos/secrets/norish-env"
fi

# Create initial admin account (first user becomes server owner)
# Use -s (not -sf) so we can read the response body even on 4xx errors
NORISH_PASS=$(head -c 32 /dev/urandom | base64 | tr -d '/+=\n' | head -c 30)

NORISH_SIGNUP=$(ssh "${TARGET}" "curl -s -X POST http://localhost:8083/api/auth/sign-up/email \
  -H 'Content-Type: application/json' \
  -d '{\"name\":\"Admin\",\"email\":\"admin@norish.local\",\"password\":\"${NORISH_PASS}\",\"callbackURL\":\"/\"}'")

if echo "${NORISH_SIGNUP}" | grep -qi "isServerOwner"; then
  echo "  ✓ Norish admin account created (admin@norish.local)"
elif echo "${NORISH_SIGNUP}" | grep -qi "disabled"; then
  echo "  Admin account already exists. Skipping."
  NORISH_PASS="(already configured)"
else
  echo "  Warning: Could not create admin account. Create manually at http://192.168.178.83:8083"
  echo "  Response: ${NORISH_SIGNUP}"
  NORISH_PASS="(setup failed — configure manually)"
fi

# --- Store in 1Password ---
echo ""
echo "Storing credentials in 1Password..."

if [[ "${ADGUARD_PASS}" != "(already configured)" && "${ADGUARD_PASS}" != "(setup failed)" ]]; then
  # Delete existing item if present
  op item delete "Homelab - AdGuard Home" --archive 2>/dev/null || true
  op item create \
    --category=login \
    --title="Homelab - AdGuard Home" \
    --url="http://192.168.178.83:3000" \
    "username=admin" \
    "password=${ADGUARD_PASS}" \
    "Tunnel URL[url]=https://adguard.danielmschmidt.de" \
    > /dev/null
  echo "  ✓ Created 'Homelab - AdGuard Home' in 1Password"
fi

if [[ "${HA_PASS}" != "(already configured)" && "${HA_PASS}" != "(setup failed"* ]]; then
  op item delete "Homelab - Home Assistant" --archive 2>/dev/null || true
  op item create \
    --category=login \
    --title="Homelab - Home Assistant" \
    --url="http://192.168.178.83:8123" \
    "username=admin" \
    "password=${HA_PASS}" \
    "Tunnel URL[url]=https://hass.danielmschmidt.de" \
    > /dev/null
  echo "  ✓ Created 'Homelab - Home Assistant' in 1Password"
fi

if [[ "${NORISH_PASS}" != "(already configured)" && "${NORISH_PASS}" != "(setup failed"* ]]; then
  op item delete "Homelab - Norish" --archive 2>/dev/null || true
  op item create \
    --category=login \
    --title="Homelab - Norish" \
    --url="http://192.168.178.83:8083" \
    "username=admin@norish.local" \
    "password=${NORISH_PASS}" \
    "master_key[password]=${NORISH_KEY:-$(ssh "${TARGET}" 'sudo grep MASTER_KEY /etc/nixos/secrets/norish-env | cut -d= -f2')}" \
    "Tunnel URL[url]=https://norish.danielmschmidt.de" \
    "Local URL[url]=http://norish.home.lan" \
    > /dev/null
  echo "  ✓ Created 'Homelab - Norish' in 1Password"
fi

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "  AdGuard Home:    http://192.168.178.83:3000  (admin)"
echo "  Home Assistant:  http://192.168.178.83:8123  (admin)"
echo "  Norish:          http://192.168.178.83:8083"
echo "  Dashboard:       http://192.168.178.83:8082"
echo ""
