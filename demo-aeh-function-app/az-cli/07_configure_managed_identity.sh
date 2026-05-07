#!/bin/bash
# Configure user-assigned managed identity (UAMI) for the Function App to connect to Event Hub.
# Required when local authentication (SAS keys) is disabled on the namespace.
# Safe to rerun — idempotent.
#
# What this does:
#   1. Creates the UAMI (if it doesn't exist)
#   2. Assigns Azure Event Hubs Data Receiver role to that identity
#   3. Attaches the UAMI to the Function App
#   4. Sets the correct app settings (EVENT_HUB_CONNECTION__ prefix)
#   5. Removes any stale/wrong settings
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

# Wait for the service principal to propagate in Entra ID before assigning roles
echo "Waiting 30s for Entra ID propagation..."
sleep 30

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

# ── 4. Set correct app settings ───────────────────────────────────────────────
# The connection name must match the 'connection' parameter in function_app.py: "EVENT_HUB_CONNECTION"
echo "Setting app settings"
az functionapp config appsettings set \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --settings \
    "EVENT_HUB_CONNECTION__fullyQualifiedNamespace=${AZURE_EVENTHUB_NAMESPACE}.servicebus.windows.net" \
    "EVENT_HUB_CONNECTION__clientId=${UAMI_CLIENT_ID}" \
  --output table

# ── 5. Remove stale/wrong settings ────────────────────────────────────────────
echo "Removing stale settings (if any)"
STALE_KEYS=(
  "EVENT_HUB_CONNECTION_STRING"
  "EVENT_HUB_CONNECTION_STRING__fullyQualifiedNamespace"
  "EVENT_HUB_CONNECTION_STRING__clientId"
)
az functionapp config appsettings delete \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --setting-names "${STALE_KEYS[@]}" 2>/dev/null || true

echo "Done."
