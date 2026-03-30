#!/bin/bash
# Create storage account and the blob container watched by Event Grid
set -euo pipefail
source "$(dirname "$0")/../.env"

echo "Creating storage account: $AZURE_STORAGE_ACCOUNT"
az storage account create \
  --name "$AZURE_STORAGE_ACCOUNT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --output table

echo "Creating container: $AZURE_STORAGE_CONTAINER"
az storage container create \
  --name "$AZURE_STORAGE_CONTAINER" \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --auth-mode login \
  --output table

echo "Done."
