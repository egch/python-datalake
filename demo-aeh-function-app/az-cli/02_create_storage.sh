#!/bin/bash
# Create storage account and blob container watched by Event Grid
set -euo pipefail
export MSYS_NO_PATHCONV=1  # prevent Git Bash from mangling /subscriptions/... Azure resource IDs into Windows paths
source "$(dirname "$0")/.env"

echo "Creating storage account: $AZURE_STORAGE_ACCOUNT"
az storage account create \
  --name "$AZURE_STORAGE_ACCOUNT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --output table

echo "Waiting for storage account to be ready..."
until az storage account show --name "$AZURE_STORAGE_ACCOUNT" --resource-group "$AZURE_RESOURCE_GROUP" --query provisioningState --output tsv 2>/dev/null | grep -q "Succeeded"; do
  sleep 5
done

STORAGE_KEY=$(az storage account keys list \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query "[0].value" --output tsv)

echo "Creating container: $AZURE_STORAGE_CONTAINER"
az storage container create \
  --name "$AZURE_STORAGE_CONTAINER" \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --account-key "$STORAGE_KEY" \
  --output table

echo "Done."
