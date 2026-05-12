#!/bin/bash
# Run all deployment scripts in order.
# Skips: 04b (merged into 04), 07/07b (migration scripts), 99 (post-check).
# Note: 06_create_private_endpoint.sh is required — the Event Hub namespace has
# public network access disabled, so the Function App listener can only reach it
# via the private endpoint + DNS zone created in that script.
set -euo pipefail
export MSYS_NO_PATHCONV=1  # prevent Git Bash from mangling /subscriptions/... Azure resource IDs into Windows paths

SCRIPT_DIR="$(dirname "$0")"

# Pre-flight: Docker daemon must be running (needed by 05_deploy_function.sh)
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not running. Please start Docker and retry." >&2
  exit 1
fi

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
run 06_create_private_endpoint.sh

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Deployment complete"
echo "════════════════════════════════════════════════════════════"
echo ""
