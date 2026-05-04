#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/.env"

EVENTHUB_RESOURCE_ID=$(az eventhubs eventhub show \
  --name "$AZURE_EVENTHUB_NAME" \
  --namespace-name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

SYSTEM_TOPIC_RESOURCE_ID=$(az eventgrid system-topic show \
  --name "$AZURE_EVENTGRID_SYSTEM_TOPIC_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

SUBSCRIPTION_NAME="sub-${AZURE_STORAGE_CONTAINER}"

echo "Creating Event Grid subscription: $SUBSCRIPTION_NAME"

az rest \
  --method PUT \
  --url "${SYSTEM_TOPIC_RESOURCE_ID}/eventSubscriptions/${SUBSCRIPTION_NAME}?api-version=2022-06-15" \
  --body "{
    \"properties\": {
      \"deliveryWithResourceIdentity\": {
        \"identity\": {\"type\": \"SystemAssigned\"},
        \"destination\": {
          \"endpointType\": \"EventHub\",
          \"properties\": {\"resourceId\": \"${EVENTHUB_RESOURCE_ID}\"}
        }
      },
      \"filter\": {
        \"subjectBeginsWith\": \"/blobServices/default/containers/${AZURE_STORAGE_CONTAINER}\",
        \"includedEventTypes\": [
          \"Microsoft.Storage.BlobCreated\",
          \"Microsoft.Storage.BlobUpdated\",
          \"Microsoft.Storage.BlobDeleted\",
          \"Microsoft.Storage.BlobTierChanged\"
        ]
      }
    }
  }"

echo "Done."
