#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-nuc}"

echo "Deploying to ${HOST}..."
echo "This will build on the target and activate the new configuration."
echo ""

nix develop --command colmena apply --on "${HOST}" --verbose --impure

echo ""
echo "Deployment complete. If something is broken:"
echo "  ssh nuc 'sudo nixos-rebuild switch --rollback'"
