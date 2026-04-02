#!/bin/bash
# Wire Event Grid subscription: storage container → Event Hub
set -euo pipefail
source "$(dirname "$0")/../.env"

STORAGE_RESOURCE_ID=$(az storage account show \
  --name "$AZURE_STORAGE_ACCOUNT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

EVENTHUB_RESOURCE_ID=$(az eventhubs eventhub show \
  --name "$AZURE_EVENTHUB_NAME" \
  --namespace-name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

echo "Creating Event Grid subscription"
az eventgrid event-subscription create \
  --name "sub-${AZURE_STORAGE_CONTAINER}" \
  --source-resource-id "$STORAGE_RESOURCE_ID" \
  --endpoint-type eventhub \
  --endpoint "$EVENTHUB_RESOURCE_ID" \
  --included-event-types Microsoft.Storage.BlobCreated Microsoft.Storage.BlobUpdated \
  --subject-begins-with "/blobServices/default/containers/${AZURE_STORAGE_CONTAINER}" \
  --output table

echo "Done."
