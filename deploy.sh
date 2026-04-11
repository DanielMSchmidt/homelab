#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-nuc}"

echo "Deploying to ${HOST}..."
echo "This will build on the target and activate the new configuration."
echo ""

colmena apply --on "${HOST}" --verbose

echo ""
echo "Deployment complete. If something is broken, SSH into the NUC and run:"
echo "  sudo nixos-rebuild switch --rollback"
