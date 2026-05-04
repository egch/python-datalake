#!/bin/bash
# Configure managed identity for the Function App to connect to Event Hub.
# Required when local authentication (SAS keys) is disabled on the namespace.
#
# What this does:
#   1. Enables system-assigned managed identity on the Function App
#   2. Assigns Azure Event Hubs Data Receiver role to that identity
#   3. Replaces EVENT_HUB_CONNECTION_STRING with the managed identity equivalent
set -euo pipefail
source "$(dirname "$0")/.env"

EVENTHUB_NAMESPACE_RESOURCE_ID=$(az eventhubs namespace show \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

# ── 1. Enable system-assigned managed identity ────────────────────────────────
echo "Enabling system-assigned managed identity on: $AZURE_FUNC_APP_NAME"
az functionapp identity assign \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --output table

FUNC_PRINCIPAL_ID=$(az functionapp identity show \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query principalId --output tsv)

echo "Function App principal ID: $FUNC_PRINCIPAL_ID"

# ── 2. Assign Azure Event Hubs Data Receiver role ─────────────────────────────
echo "Assigning Azure Event Hubs Data Receiver role"
az role assignment create \
  --assignee "$FUNC_PRINCIPAL_ID" \
  --role "Azure Event Hubs Data Receiver" \
  --scope "$EVENTHUB_NAMESPACE_RESOURCE_ID" \
  --output table

# ── 3. Replace connection string with managed identity setting ────────────────
echo "Updating app settings for managed identity"
az functionapp config appsettings set \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --settings "EVENT_HUB_CONNECTION_STRING__fullyQualifiedNamespace=${AZURE_EVENTHUB_NAMESPACE}.servicebus.windows.net" \
  --output table

az functionapp config appsettings delete \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --setting-names "EVENT_HUB_CONNECTION_STRING"

echo "Done."
