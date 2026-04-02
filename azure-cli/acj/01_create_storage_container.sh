#!/bin/bash
# Create the blob container watched by Event Grid for the ACJ consumer
set -euo pipefail
source "$(dirname "$0")/../../.env"

echo "Creating container: $ACJ_STORAGE_CONTAINER in $AZURE_STORAGE_ACCOUNT"
az storage container create \
  --name "$ACJ_STORAGE_CONTAINER" \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --auth-mode login \
  --output table

echo "Done."
