#!/bin/bash
# Wire Event Grid → Event Hub via a system topic with managed identity.
#
# Why system topic + managed identity instead of a direct subscription?
# When the Event Hub has public network access disabled, Event Grid (a Microsoft
# service running outside our VNet) cannot use the private endpoint.  It can only
# reach the namespace through the "trusted Microsoft services" bypass — but that
# bypass requires Event Grid to authenticate with a proper identity, not a SAS key.
#
# Flow:
#   Storage account BlobCreated/Updated/Deleted
#     → Event Grid system topic  (system-assigned managed identity)
#       → delivers to Event Hub  (identity has Azure Event Hubs Data Sender role)
set -euo pipefail
source "$(dirname "$0")/.env"

STORAGE_RESOURCE_ID=$(az storage account show \
  --name "$AZURE_STORAGE_ACCOUNT" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

EVENTHUB_RESOURCE_ID=$(az eventhubs eventhub show \
  --name "$AZURE_EVENTHUB_NAME" \
  --namespace-name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

EVENTHUB_NAMESPACE_RESOURCE_ID=$(az eventhubs namespace show \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

# ── 1. Create system topic with system-assigned managed identity ──────────────
TOPIC_EXISTS=$(az eventgrid system-topic show \
  --name "$AZURE_EVENTGRID_SYSTEM_TOPIC_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query name --output tsv 2>/dev/null || true)

if [ -z "$TOPIC_EXISTS" ]; then
  echo "Creating Event Grid system topic: $AZURE_EVENTGRID_SYSTEM_TOPIC_NAME"
  az eventgrid system-topic create \
    --name "$AZURE_EVENTGRID_SYSTEM_TOPIC_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --location "$AZURE_REGION" \
    --source "$STORAGE_RESOURCE_ID" \
    --topic-type Microsoft.Storage.StorageAccounts \
    --mi-system-assigned \
    --output table
else
  echo "System topic $AZURE_EVENTGRID_SYSTEM_TOPIC_NAME already exists, skipping."
fi

# ── 2. Assign Azure Event Hubs Data Sender role to the topic identity ─────────
SYSTEM_TOPIC_PRINCIPAL_ID=$(az eventgrid system-topic show \
  --name "$AZURE_EVENTGRID_SYSTEM_TOPIC_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query "identity.principalId" --output tsv)

# Identity may not be ready immediately after create — enable it explicitly if missing
if [ -z "$SYSTEM_TOPIC_PRINCIPAL_ID" ]; then
  echo "Identity not yet assigned — enabling system-assigned identity"
  az eventgrid system-topic update \
    --name "$AZURE_EVENTGRID_SYSTEM_TOPIC_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --identity SystemAssigned \
    --output table

  echo "Waiting for identity to propagate..."
  sleep 20

  SYSTEM_TOPIC_PRINCIPAL_ID=$(az eventgrid system-topic show \
    --name "$AZURE_EVENTGRID_SYSTEM_TOPIC_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "identity.principalId" --output tsv)
fi

echo "Assigning Azure Event Hubs Data Sender to principal: $SYSTEM_TOPIC_PRINCIPAL_ID"
az role assignment create \
  --assignee "$SYSTEM_TOPIC_PRINCIPAL_ID" \
  --role "Azure Event Hubs Data Sender" \
  --scope "$EVENTHUB_NAMESPACE_RESOURCE_ID" \
  --output table

# ── 3. Create event subscription under the system topic ──────────────────────
echo "Creating Event Grid subscription: sub-${AZURE_STORAGE_CONTAINER}"

SYSTEM_TOPIC_RESOURCE_ID=$(az eventgrid system-topic show \
  --name "$AZURE_EVENTGRID_SYSTEM_TOPIC_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

SUBSCRIPTION_NAME="sub-${AZURE_STORAGE_CONTAINER}"

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
