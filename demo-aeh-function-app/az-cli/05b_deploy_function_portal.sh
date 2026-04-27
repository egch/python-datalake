#!/bin/bash
# Deploy an Azure Function App using the built-in Python runtime (portal-editable).
# Uses the existing App Service Plan — no Docker image required.
set -euo pipefail
source "$(dirname "$0")/.env"

if [ -z "${AZURE_STORAGE_ACCOUNT_CONNECTION_STRING:-}" ]; then
  echo "ERROR: AZURE_STORAGE_ACCOUNT_CONNECTION_STRING is not set in .env" >&2
  exit 1
fi
if [ -z "${EVENT_HUB_CONNECTION_STRING:-}" ]; then
  echo "ERROR: EVENT_HUB_CONNECTION_STRING is not set in .env" >&2
  exit 1
fi

PORTAL_FUNC_APP_NAME="${AZURE_FUNC_APP_NAME}-portal"

# ── 1. Create Function App (built-in runtime, portal-editable) ────────────────
FUNC_EXISTS=$(az functionapp show \
  --name "$PORTAL_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query name --output tsv 2>/dev/null || true)

if [ -z "$FUNC_EXISTS" ]; then
  echo "Creating Function App: $PORTAL_FUNC_APP_NAME"
  az functionapp create \
    --name "$PORTAL_FUNC_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --storage-account "$AZURE_STORAGE_ACCOUNT" \
    --plan "$AZURE_APP_SERVICE_PLAN" \
    --runtime python \
    --runtime-version 3.11 \
    --functions-version 4 \
    --output table
else
  echo "Function App $PORTAL_FUNC_APP_NAME already exists, skipping creation."
fi

# ── 2. Configure app settings ─────────────────────────────────────────────────
echo "Configuring app settings"
az functionapp config appsettings set \
  --name "$PORTAL_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --settings \
    "EVENT_HUB_CONNECTION_STRING=${EVENT_HUB_CONNECTION_STRING}" \
    "EVENT_HUB_NAME=${AZURE_EVENTHUB_NAME}" \
    "EVENT_HUB_CONSUMER_GROUP=\$Default" \
    "AzureWebJobsStorage=${AZURE_STORAGE_ACCOUNT_CONNECTION_STRING}" \
  --output table

echo "Done. Edit your function code at:"
echo "  Portal → $PORTAL_FUNC_APP_NAME → Functions → + Create"
