#!/bin/bash
# Post-deployment checks: verify the full blob → Event Grid → Event Hub → Function chain.
set -euo pipefail
source "$(dirname "$0")/.env"

EVENTHUB_NAMESPACE_RESOURCE_ID=$(az eventhubs namespace show \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

# ── 1. Event Grid subscription status ────────────────────────────────────────
echo "── 1. Event Grid subscription status"
az eventgrid system-topic event-subscription show \
  --name "sub-${AZURE_STORAGE_CONTAINER}" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --system-topic-name "$AZURE_EVENTGRID_SYSTEM_TOPIC_NAME" \
  --query "{status:provisioningState, destination:destination}" \
  --output table

# ── 2. Upload a test blob to trigger the flow ─────────────────────────────────
echo "── 2. Uploading test blob to trigger the flow"
az storage blob upload \
  --account-name "$AZURE_STORAGE_ACCOUNT" \
  --container-name "$AZURE_STORAGE_CONTAINER" \
  --name "test.txt" \
  --data "hello" \
  --auth-mode login \
  --overwrite

# ── 3. Check Event Hub incoming messages ──────────────────────────────────────
echo "── 3. Event Hub incoming messages (last 5 minutes)"
az monitor metrics list \
  --resource "$EVENTHUB_NAMESPACE_RESOURCE_ID" \
  --metric "IncomingMessages" \
  --interval PT1M \
  --output table

# ── 4. NSG check on subnets ──────────────────────────────────────────────────
echo "── 4. NSG attached to Function App outbound subnet ($AZURE_SUBNET_NAME)"
az network vnet subnet show \
  --name "$AZURE_SUBNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET_NAME" \
  --query "networkSecurityGroup.id" --output tsv

echo "── 4b. NSG attached to private endpoint subnet ($AZURE_PE_SUBNET_NAME)"
az network vnet subnet show \
  --name "$AZURE_PE_SUBNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET_NAME" \
  --query "networkSecurityGroup.id" --output tsv

# ── 5. Stream Function App logs ───────────────────────────────────────────────
echo "── 5. Streaming Function App logs (Ctrl+C to stop)"
az webapp log tail \
  --name "$AZURE_FUNCTION_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP"
