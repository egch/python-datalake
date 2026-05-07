#!/bin/bash
# Configure user-assigned managed identity (UAMI) for the Function App to connect to Event Hub.
# Required when local authentication (SAS keys) is disabled on the namespace.
#
# What this does:
#   1. Creates the UAMI (if it doesn't exist)
#   2. Assigns Azure Event Hubs Data Receiver role to that identity
#   3. Attaches the UAMI to the Function App
#   4. Replaces EVENT_HUB_CONNECTION_STRING with the managed identity equivalent
set -euo pipefail
source "$(dirname "$0")/.env"

EVENTHUB_NAMESPACE_RESOURCE_ID=$(az eventhubs namespace show \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

# ── 1. Create UAMI if it doesn't exist ───────────────────────────────────────
echo "Ensuring user-assigned managed identity exists: $AZURE_UAMI_NAME"
az identity create \
  --name "$AZURE_UAMI_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --output table

UAMI_RESOURCE_ID=$(az identity show \
  --name "$AZURE_UAMI_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

UAMI_PRINCIPAL_ID=$(az identity show \
  --name "$AZURE_UAMI_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query principalId --output tsv)

UAMI_CLIENT_ID=$(az identity show \
  --name "$AZURE_UAMI_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query clientId --output tsv)

echo "UAMI principal ID : $UAMI_PRINCIPAL_ID"
echo "UAMI client ID    : $UAMI_CLIENT_ID"

# ── 2. Assign Azure Event Hubs Data Receiver role ─────────────────────────────
echo "Assigning Azure Event Hubs Data Receiver role"
az role assignment create \
  --assignee "$UAMI_PRINCIPAL_ID" \
  --role "Azure Event Hubs Data Receiver" \
  --scope "$EVENTHUB_NAMESPACE_RESOURCE_ID" \
  --output table

# ── 3. Attach UAMI to the Function App ───────────────────────────────────────
echo "Attaching UAMI to Function App: $AZURE_FUNC_APP_NAME"
az functionapp identity assign \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --identities "$UAMI_RESOURCE_ID" \
  --output table

# ── 4. Update app settings for managed identity ───────────────────────────────
echo "Updating app settings for managed identity"
az functionapp config appsettings set \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --settings \
    "EVENT_HUB_CONNECTION_STRING__fullyQualifiedNamespace=${AZURE_EVENTHUB_NAMESPACE}.servicebus.windows.net" \
    "EVENT_HUB_CONNECTION_STRING__clientId=${UAMI_CLIENT_ID}" \
  --output table

az functionapp config appsettings delete \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --setting-names "EVENT_HUB_CONNECTION_STRING"

echo "Done."
