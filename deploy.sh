#!/usr/bin/env bash
set -euo pipefail

if ! command -v colmena &>/dev/null; then
  echo "Error: colmena not found. Run 'nix develop' first to enter the dev shell."
  exit 1
fi

HOST="${1:-nuc}"

echo "Deploying to ${HOST}..."
echo "This will build on the target and activate the new configuration."
echo ""

colmena apply --on "${HOST}" --verbose --impure

echo ""
echo "Deployment complete. If something is broken:"
echo "  ssh nuc 'sudo nixos-rebuild switch --rollback'"
