#!/usr/bin/env bash
# Provisions Azure resources for the large-file upload POC.
# Run from anywhere — .env is always written to poc-large-upload/ (script's parent).
set -euo pipefail

# Always write .env next to main.py, regardless of where this script is called from
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-poc-large-upload}"
LOCATION="${LOCATION:-westeurope}"
CONTAINER="${CONTAINER:-large-uploads}"

# Storage account names must be globally unique, 3-24 chars, lowercase+digits only
SUFFIX=$(date +%s | tail -c 6)
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stpocupload${SUFFIX}}"

echo "==> Creating resource group: $RESOURCE_GROUP"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "==> Creating storage account: $STORAGE_ACCOUNT"
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --output none

echo "==> Retrieving connection string"
CONN_STR=$(az storage account show-connection-string \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --query connectionString -o tsv)

echo "==> Creating blob container: $CONTAINER"
az storage container create \
  --name "$CONTAINER" \
  --connection-string "$CONN_STR" \
  --output none

echo "==> Configuring CORS (required for direct browser uploads)"
# MSYS_NO_PATHCONV prevents Git Bash from mangling the wildcard origin
MSYS_NO_PATHCONV=1 az storage cors add \
  --services b \
  --methods DELETE GET HEAD MERGE OPTIONS PATCH POST PUT \
  --origins '*' \
  --allowed-headers '*' \
  --exposed-headers '*' \
  --max-age 3600 \
  --connection-string "$CONN_STR" \
  --output none

echo "==> Writing .env"
cat > "$ENV_FILE" <<EOF
AZURE_STORAGE_ACCOUNT_CONNECTION_STRING=${CONN_STR}
CONTAINER_LARGE_UPLOAD=${CONTAINER}
SAS_EXPIRY_HOURS=1
EOF

echo ""
echo "Done."
echo "  Resource group : $RESOURCE_GROUP"
echo "  Storage account: $STORAGE_ACCOUNT"
echo "  Container      : $CONTAINER"
echo "  .env written   : $ENV_FILE"
echo ""
echo "Start the API with:  uvicorn main:app --reload"
