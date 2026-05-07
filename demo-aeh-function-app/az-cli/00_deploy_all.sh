#!/bin/bash
# Run all deployment scripts in order.
# Skips: 04b (merged into 04), 06 (optional private endpoint), 07/07b (migration scripts), 99 (post-check).
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"

run() {
  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo "  Running: $1"
  echo "════════════════════════════════════════════════════════════"
  bash "$SCRIPT_DIR/$1"
}

run 00_login.sh
run 01_create_rg_vnet_subnet.sh
run 02_create_storage.sh
run 03_create_eventhub.sh
run 04_create_eventgrid.sh
run 05_deploy_function.sh

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Deployment complete"
echo "════════════════════════════════════════════════════════════"
echo ""
