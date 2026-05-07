#!/bin/bash
# Delete all resources by removing both resource groups.
# WARNING: this is irreversible — all resources will be permanently deleted.
set -euo pipefail
source "$(dirname "$0")/.env"

echo "Deleting resource group: $AZURE_RESOURCE_GROUP"
az group delete --name "$AZURE_RESOURCE_GROUP" --yes --no-wait

echo "Deleting resource group: $AZURE_NETWORK_RESOURCE_GROUP"
az group delete --name "$AZURE_NETWORK_RESOURCE_GROUP" --yes --no-wait

echo "Deletion triggered for both resource groups (running in background)."
