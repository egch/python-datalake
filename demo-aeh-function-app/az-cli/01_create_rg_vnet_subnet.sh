#!/bin/bash
# Create resource groups, virtual network and subnet
set -euo pipefail
source "$(dirname "$0")/.env"

echo "Creating resource group: $AZURE_RESOURCE_GROUP"
az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --output table

echo "Creating network resource group: $AZURE_NETWORK_RESOURCE_GROUP"
az group create \
  --name "$AZURE_NETWORK_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --output table

echo "Creating virtual network: $AZURE_VNET_NAME"
az network vnet create \
  --name "$AZURE_VNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --address-prefix "$AZURE_VNET_ADDRESS_PREFIX" \
  --output table

echo "Creating subnet: $AZURE_SUBNET_NAME"
az network vnet subnet create \
  --name "$AZURE_SUBNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET_NAME" \
  --address-prefix "$AZURE_SUBNET_ADDRESS_PREFIX" \
  --output table

echo "Done."
