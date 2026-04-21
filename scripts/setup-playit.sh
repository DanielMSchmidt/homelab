#!/usr/bin/env bash
set -euo pipefail

# Sets up a playit.gg tunnel for the Minecraft Bedrock server (GeyserMC).
# Run from your laptop after deploying the Minecraft module.
#
# Usage: bash scripts/setup-playit.sh
#
# Prerequisites:
#   - NUC deployed with the minecraft module
#   - A playit.gg account (https://playit.gg)

TARGET="nuc"
SECRET_PATH="/etc/nixos/secrets/playit-secret.toml"

echo "========================================"
echo "  Set Up playit.gg Tunnel"
echo "========================================"
echo ""

# Check SSH
if ! ssh -o ConnectTimeout=5 "${TARGET}" 'true' &>/dev/null; then
  echo "Error: Cannot SSH into ${TARGET}."
  exit 1
fi

# Check if secret already exists
SECRET_EXISTS=$(ssh "${TARGET}" "sudo test -f ${SECRET_PATH} && echo 'yes' || echo 'no'" | tail -1)

if [[ "${SECRET_EXISTS}" == "yes" ]]; then
  echo "Secret already exists at ${SECRET_PATH}."
  read -rp "Overwrite? [y/N] " overwrite
  if [[ "${overwrite}" != "y" && "${overwrite}" != "Y" ]]; then
    echo "Skipping. Restart the service if needed:"
    echo "  ssh ${TARGET} 'sudo systemctl restart playit'"
    exit 0
  fi
fi

echo ""
echo "To get your playit.gg secret:"
echo "  1. Go to https://playit.gg and sign in"
echo "  2. Click 'Add Tunnel' > select 'Custom UDP'"
echo "  3. Set local port to 19132"
echo "  4. Create an agent and copy the secret key"
echo ""
read -rp "Paste your playit.gg secret key: " PLAYIT_SECRET

if [[ -z "${PLAYIT_SECRET}" ]]; then
  echo "Error: No secret provided."
  exit 1
fi

# Write the secret to the NUC
echo "${PLAYIT_SECRET}" | ssh "${TARGET}" "sudo tee ${SECRET_PATH} > /dev/null"
ssh "${TARGET}" "sudo chmod 600 ${SECRET_PATH}"

echo ""
echo "  Secret written to ${SECRET_PATH}"

# Restart the playit service
ssh "${TARGET}" "sudo systemctl restart playit"
echo "  playit service restarted"

# Check if it's running
sleep 2
PLAYIT_STATUS=$(ssh "${TARGET}" "systemctl is-active playit" 2>/dev/null || echo "failed")

echo ""
echo "========================================"
if [[ "${PLAYIT_STATUS}" == "active" ]]; then
  echo "  playit.gg Tunnel Active!"
  echo "========================================"
  echo ""
  echo "  On your Switch, add a server with"
  echo "  the address from your playit.gg dashboard."
  echo ""
  echo "  For LAN play: 192.168.178.83:19132"
else
  echo "  playit.gg service failed to start"
  echo "========================================"
  echo ""
  echo "  Check logs: ssh ${TARGET} 'journalctl -u playit -n 50'"
  echo ""
  echo "  The secret format might need to be a TOML file."
  echo "  Check playit.gg docs for the expected format."
fi
