#!/bin/bash
# Build, push and deploy the Azure Function to Container Apps
set -euo pipefail
source "$(dirname "$0")/../.env"

SCRIPT_DIR="$(dirname "$0")"

# ── 1. Build & push image ────────────────────────────────────────────────────
echo "Building Docker image: egch/func-consumer:latest"
docker build -t egch/func-consumer:latest "$SCRIPT_DIR/../func_consumer"

echo "Pushing to Docker Hub"
docker push egch/func-consumer:latest

# ── 2. Create Log Analytics Workspace ────────────────────────────────────────
echo "Creating Log Analytics workspace: $AZURE_LOG_ANALYTICS_WORKSPACE"
az monitor log-analytics workspace create \
  --name "$AZURE_LOG_ANALYTICS_WORKSPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --output table

LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
  --name "$AZURE_LOG_ANALYTICS_WORKSPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query customerId --output tsv)

LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --name "$AZURE_LOG_ANALYTICS_WORKSPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query primarySharedKey --output tsv)

# ── 3. Create Container Apps Environment ─────────────────────────────────────
echo "Creating Container Apps Environment: $AZURE_CONTAINER_APP_ENV"
az containerapp env create \
  --name "$AZURE_CONTAINER_APP_ENV" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --logs-workspace-id "$LOG_ANALYTICS_ID" \
  --logs-workspace-key "$LOG_ANALYTICS_KEY" \
  --output table

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
    --environment "$AZURE_CONTAINER_APP_ENV" \
    --image "docker.io/egch/func-consumer:latest" \
    --functions-version 4 \
    --workload-profile-name Consumption \
    --output table
else
  echo "Function App $AZURE_FUNC_APP_NAME already exists, skipping creation."
fi

# ── 5. Configure environment variables ───────────────────────────────────────
echo "Configuring environment variables"

SETTINGS_FILE=$(mktemp /tmp/func_settings_XXXXXX.json)
cat > "$SETTINGS_FILE" <<EOF
[
  {"name": "AzureWebJobsStorage",        "value": "${AZURE_STORAGE_ACCOUNT_CONNECTION_STRING}"},
  {"name": "EVENT_HUB_CONNECTION_STRING","value": "${EVENT_HUB_CONNECTION_STRING}"},
  {"name": "EVENT_HUB_NAME",             "value": "${AZURE_EVENTHUB_NAME}"},
  {"name": "EVENT_HUB_CONSUMER_GROUP",   "value": "\$Default"}
]
EOF

az functionapp config appsettings set \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --settings @"$SETTINGS_FILE" \
  --output table

rm -f "$SETTINGS_FILE"

echo "Done."
