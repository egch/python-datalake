#!/bin/bash
# Create Event Hub for ACJ consumer (reuses existing namespace)
set -euo pipefail
source "$(dirname "$0")/../../.env"

echo "Creating Event Hub: $ACJ_EVENTHUB_NAME in namespace $AZURE_EVENTHUB_NAMESPACE"
az eventhubs eventhub create \
  --name "$ACJ_EVENTHUB_NAME" \
  --namespace-name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --partition-count 2 \
  --output table

echo "Done."
