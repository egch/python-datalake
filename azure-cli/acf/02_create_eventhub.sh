#!/bin/bash
# Create Event Hub namespace and hub
set -euo pipefail
source "$(dirname "$0")/../.env"

echo "Creating Event Hub namespace: $AZURE_EVENTHUB_NAMESPACE"
az eventhubs namespace create \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --sku Standard \
  --output table

echo "Creating Event Hub: $AZURE_EVENTHUB_NAME"
az eventhubs eventhub create \
  --name "$AZURE_EVENTHUB_NAME" \
  --namespace-name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --partition-count 2 \
  --output table

echo "Done."
