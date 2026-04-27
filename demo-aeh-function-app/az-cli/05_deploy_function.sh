#!/bin/bash
# Build, push and deploy the Azure Function App with VNet integration on the subnet
set -euo pipefail
source "$(dirname "$0")/.env"

SCRIPT_DIR="$(dirname "$0")"

# ── 0. Pre-flight checks ──────────────────────────────────────────────────────
if [ -z "${AZURE_STORAGE_ACCOUNT_CONNECTION_STRING:-}" ]; then
  echo "ERROR: AZURE_STORAGE_ACCOUNT_CONNECTION_STRING is not set in .env" >&2
  exit 1
fi
if [ -z "${EVENT_HUB_CONNECTION_STRING:-}" ]; then
  echo "ERROR: EVENT_HUB_CONNECTION_STRING is not set in .env" >&2
  exit 1
fi

# ── 1. Build & push image ────────────────────────────────────────────────────
echo "Building Docker image: egch/func-consumer-ehfa:latest"
docker build -t egch/func-consumer-ehfa:latest "$SCRIPT_DIR/../func_consumer"

echo "Pushing to Docker Hub"
docker push egch/func-consumer-ehfa:latest

# ── 2. Delegate subnet to Microsoft.Web/serverFarms ──────────────────────────
echo "Delegating subnet $AZURE_SUBNET_NAME to Microsoft.Web/serverFarms"
az network vnet subnet update \
  --name "$AZURE_SUBNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET_NAME" \
  --delegations Microsoft.Web/serverFarms \
  --output table

# ── 3. Create App Service Plan (Elastic Premium for VNet support) ─────────────
PLAN_EXISTS=$(az functionapp plan show \
  --name "$AZURE_APP_SERVICE_PLAN" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query name --output tsv 2>/dev/null || true)

if [ -z "$PLAN_EXISTS" ]; then
  echo "Creating App Service Plan: $AZURE_APP_SERVICE_PLAN"
  az functionapp plan create \
    --name "$AZURE_APP_SERVICE_PLAN" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --location "$AZURE_REGION" \
    --sku EP1 \
    --is-linux \
    --output table
else
  echo "App Service Plan $AZURE_APP_SERVICE_PLAN already exists, skipping creation."
fi

# ── 4. Create Function App ────────────────────────────────────────────────────
FUNC_EXISTS=$(az functionapp show \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query name --output tsv 2>/dev/null || true)

if [ -z "$FUNC_EXISTS" ]; then
  echo "Creating Function App: $AZURE_FUNC_APP_NAME"
  az functionapp create \
    --name "$AZURE_FUNC_APP_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --storage-account "$AZURE_STORAGE_ACCOUNT" \
    --plan "$AZURE_APP_SERVICE_PLAN" \
    --deployment-container-image-name "docker.io/egch/func-consumer-ehfa:latest" \
    --functions-version 4 \
    --output table
else
  echo "Function App $AZURE_FUNC_APP_NAME already exists, skipping creation."
fi

# ── 5. Integrate Function App with subnet ────────────────────────────────────
echo "Adding VNet integration: $AZURE_VNET_NAME/$AZURE_SUBNET_NAME"

# VNet lives in a different resource group — must use resource IDs, not names
VNET_RESOURCE_ID=$(az network vnet show \
  --name "$AZURE_VNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --query id --output tsv)

SUBNET_RESOURCE_ID=$(az network vnet subnet show \
  --name "$AZURE_SUBNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET_NAME" \
  --query id --output tsv)

az functionapp vnet-integration add \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --vnet "$VNET_RESOURCE_ID" \
  --subnet "$SUBNET_RESOURCE_ID" \
  --output table

# ── 6. Configure app settings ─────────────────────────────────────────────────
echo "Configuring app settings"

SETTINGS_FILE=$(mktemp /tmp/func_settings_XXXXXX.json)
cat > "$SETTINGS_FILE" <<EOF
[
  {"name": "FUNCTIONS_WORKER_RUNTIME",      "value": "python"},
  {"name": "AzureWebJobsStorage",         "value": "${AZURE_STORAGE_ACCOUNT_CONNECTION_STRING}"},
  {"name": "EVENT_HUB_CONNECTION_STRING", "value": "${EVENT_HUB_CONNECTION_STRING}"},
  {"name": "EVENT_HUB_NAME",              "value": "${AZURE_EVENTHUB_NAME}"},
  {"name": "EVENT_HUB_CONSUMER_GROUP",    "value": "\$Default"},
  {"name": "WEBSITE_VNET_ROUTE_ALL",      "value": "1"}
]
EOF

az functionapp config appsettings set \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --settings @"$SETTINGS_FILE" \
  --output table

rm -f "$SETTINGS_FILE"

echo "Done."
