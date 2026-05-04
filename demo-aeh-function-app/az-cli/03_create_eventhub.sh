#!/bin/bash
# Create Event Hub namespace and hub with public network access disabled.
# Trusted service access is enabled so Event Grid (managed identity) can still deliver.
set -euo pipefail
source "$(dirname "$0")/.env"

echo "Creating Event Hub namespace: $AZURE_EVENTHUB_NAMESPACE (public network: Disabled)"
az eventhubs namespace create \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --sku Standard \
  --public-network-access Disabled \
  --output table

echo "Enabling trusted Microsoft services bypass"
NAMESPACE_ID=$(az eventhubs namespace show \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

az rest \
  --method PUT \
  --url "${NAMESPACE_ID}/networkRuleSets/default?api-version=2024-01-01" \
  --body '{"properties": {"trustedServiceAccessEnabled": true, "defaultAction": "Allow"}}'

echo "Creating Event Hub: $AZURE_EVENTHUB_NAME"
az eventhubs eventhub create \
  --name "$AZURE_EVENTHUB_NAME" \
  --namespace-name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --partition-count 2 \
  --output table

echo "Done."
