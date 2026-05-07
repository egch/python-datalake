#!/bin/bash
# Remove the system-assigned managed identity (SAMI) from the Function App
# and delete its Event Hub role assignment.
# Run this after 07_configure_managed_identity.sh if you migrated from SAMI to UAMI.
set -euo pipefail
source "$(dirname "$0")/.env"

EVENTHUB_NAMESPACE_RESOURCE_ID=$(az eventhubs namespace show \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

SAMI_PRINCIPAL_ID=$(az functionapp identity show \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query principalId --output tsv)

if [ -z "$SAMI_PRINCIPAL_ID" ] || [ "$SAMI_PRINCIPAL_ID" = "null" ]; then
  echo "No system-assigned managed identity found on $AZURE_FUNC_APP_NAME — nothing to do."
  exit 0
fi

echo "SAMI principal ID: $SAMI_PRINCIPAL_ID"

echo "Removing Azure Event Hubs Data Receiver role from SAMI"
az role assignment delete \
  --assignee "$SAMI_PRINCIPAL_ID" \
  --role "Azure Event Hubs Data Receiver" \
  --scope "$EVENTHUB_NAMESPACE_RESOURCE_ID"

echo "Disabling system-assigned managed identity on $AZURE_FUNC_APP_NAME"
az functionapp identity remove \
  --name "$AZURE_FUNC_APP_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --identities [system]

echo "Done."
