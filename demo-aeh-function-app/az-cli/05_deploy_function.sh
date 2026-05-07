#!/bin/bash
# Build, push and deploy the Azure Function App with VNet integration on the subnet.
# The Function App uses a user-assigned managed identity (UAMI) to authenticate to Event Hub
# (SAS keys are disabled on the namespace).
set -euo pipefail
source "$(dirname "$0")/.env"

SCRIPT_DIR="$(dirname "$0")"

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
  echo "App Service Plan $AZURE_APP_SERVICE_PLAN already exists, skipping."
fi

# ── 4. Create UAMI if it doesn't exist ───────────────────────────────────────
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

# ── 5. Assign Azure Event Hubs Data Receiver role to UAMI ────────────────────
EVENTHUB_NAMESPACE_RESOURCE_ID=$(az eventhubs namespace show \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

echo "Assigning Azure Event Hubs Data Receiver role to UAMI"
az role assignment create \
  --assignee "$UAMI_PRINCIPAL_ID" \
  --role "Azure Event Hubs Data Receiver" \
  --scope "$EVENTHUB_NAMESPACE_RESOURCE_ID" \
  --output table

# ── 6. Create Function App ────────────────────────────────────────────────────
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
    --image "docker.io/egch/func-consumer-ehfa:latest" \
    --functions-version 4 \
    --output table
else
  echo "Function App $AZURE_FUNC_APP_NAME already exists, skipping."
fi

# ── 7. Attach UAMI to the Function App ───────────────────────────────────────
echo "Attaching UAMI to Function App: $AZURE_FUNC_APP_NAME"
az functionapp identity assign \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --identities "$UAMI_RESOURCE_ID" \
  --output table

# ── 8. Integrate Function App with subnet ─────────────────────────────────────
echo "Adding VNet integration: $AZURE_VNET_NAME/$AZURE_SUBNET_NAME"

SUBNET_RESOURCE_ID=$(az network vnet subnet show \
  --name "$AZURE_SUBNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET_NAME" \
  --query id --output tsv)

az functionapp vnet-integration add \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --vnet "$AZURE_VNET_NAME" \
  --subnet "$SUBNET_RESOURCE_ID" \
  --output table

# ── 9. Configure app settings ─────────────────────────────────────────────────
echo "Configuring app settings"

SETTINGS_FILE=$(mktemp /tmp/func_settings_XXXXXX.json)
cat > "$SETTINGS_FILE" <<EOF
[
  {"name": "FUNCTIONS_WORKER_RUNTIME",                      "value": "python"},
  {"name": "EVENT_HUB_CONNECTION__fullyQualifiedNamespace", "value": "${AZURE_EVENTHUB_NAMESPACE}.servicebus.windows.net"},
  {"name": "EVENT_HUB_CONNECTION__clientId",                "value": "${UAMI_CLIENT_ID}"},
  {"name": "EVENT_HUB_NAME",                                "value": "${AZURE_EVENTHUB_NAME}"},
  {"name": "EVENT_HUB_CONSUMER_GROUP",                      "value": "\$Default"},
  {"name": "WEBSITE_VNET_ROUTE_ALL",                        "value": "1"}
]
EOF

az functionapp config appsettings set \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --settings @"$SETTINGS_FILE" \
  --output table

rm -f "$SETTINGS_FILE"

# ── 10. Configure CORS ────────────────────────────────────────────────────────
echo "Configuring CORS"
az functionapp cors add \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --allowed-origins "$AZURE_CORS_ORIGIN" \
  --output table

# ── 11. Refresh AzureWebJobsStorage from Azure ───────────────────────────────
echo "Refreshing AzureWebJobsStorage connection string"
az functionapp config appsettings set \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --settings "AzureWebJobsStorage=$(az storage account show-connection-string \
    --name "$AZURE_STORAGE_ACCOUNT" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query connectionString --output tsv)" \
  --output table

echo "Done."
