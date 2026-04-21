#!/usr/bin/env bash
set -euo pipefail

# Sets up a playit.gg tunnel for the Minecraft Bedrock server (GeyserMC).
# Run from your laptop after deploying the Minecraft module.
#
# This script runs the playit-cli claim flow locally, then copies
# the resulting secret TOML file to the NUC.
#
# Usage: bash scripts/setup-playit.sh
#
# Prerequisites:
#   - NUC deployed with the minecraft module
#   - A playit.gg account (https://playit.gg)
#   - Nix installed locally

TARGET="nuc"
SECRET_PATH="/etc/nixos/secrets/playit-secret.toml"
LOCAL_SECRET="$HOME/.config/playit_gg/playit.toml"

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

echo "Starting playit-cli to claim a new agent..."
echo ""
echo "  1. A URL will appear — open it in your browser"
echo "  2. Sign in to playit.gg and claim the agent"
echo "  3. Once claimed, the agent starts running — press Ctrl+C to stop it"
echo "  4. Then configure your tunnel at https://playit.gg/account/tunnels"
echo "     (Custom UDP, local port 19132)"
echo ""
read -rp "Press Enter to continue..."

# Run the playit-cli claim flow
nix run github:pedorich-n/playit-nixos-module#playit-cli -- start

# Check if secret was created
if [[ ! -f "${LOCAL_SECRET}" ]]; then
  echo ""
  echo "Error: Secret file not found at ${LOCAL_SECRET}"
  echo "The claim may not have completed. Try again."
  exit 1
fi

echo ""
echo "Agent claimed. Copying secret to NUC..."

# Copy secret to NUC
scp "${LOCAL_SECRET}" "${TARGET}:/tmp/playit-secret.toml"
ssh "${TARGET}" "sudo mv /tmp/playit-secret.toml ${SECRET_PATH} && sudo chmod 600 ${SECRET_PATH}"

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
  echo "  Next steps:"
  echo "    1. Go to https://playit.gg/account/tunnels"
  echo "    2. Add a tunnel: Custom UDP, local port 19132"
  echo "    3. On your Switch, add a server with the"
  echo "       playit.gg address shown in the dashboard"
  echo ""
  echo "  For LAN play: 192.168.178.83:19132"
else
  echo "  playit.gg service failed to start"
  echo "========================================"
  echo ""
  echo "  Check logs: ssh ${TARGET} 'journalctl -u playit -n 50'"
fi
