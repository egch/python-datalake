#!/bin/bash
# Create the private endpoint so the Function App can reach the Event Hub
# through the VNet. The namespace was already created with public network
# disabled and trusted service access enabled in script 03.
#
# What this does:
#   1. Creates a private endpoint for the namespace in the PE subnet
#   2. Creates a private DNS zone (privatelink.servicebus.windows.net)
#   3. Links the DNS zone to the VNet
#   4. Registers the PE NIC IP in the DNS zone via a zone group
#
# After this runs the Function App resolves evhns-eh-fa.servicebus.windows.net
# to the private IP — no code or connection-string changes required.
set -euo pipefail
source "$(dirname "$0")/.env"

DNS_ZONE="privatelink.servicebus.windows.net"

# ── 1. Resolve resource IDs ───────────────────────────────────────────────────
EVENTHUB_RESOURCE_ID=$(az eventhubs namespace show \
  --name "$AZURE_EVENTHUB_NAMESPACE" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query id --output tsv)

PE_SUBNET_RESOURCE_ID=$(az network vnet subnet show \
  --name "$AZURE_PE_SUBNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --vnet-name "$AZURE_VNET_NAME" \
  --query id --output tsv)

VNET_RESOURCE_ID=$(az network vnet show \
  --name "$AZURE_VNET_NAME" \
  --resource-group "$AZURE_NETWORK_RESOURCE_GROUP" \
  --query id --output tsv)

# ── 2. Create private endpoint ────────────────────────────────────────────────
echo "Creating private endpoint: $AZURE_PRIVATE_ENDPOINT_NAME"
az network private-endpoint create \
  --name "$AZURE_PRIVATE_ENDPOINT_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --subnet "$PE_SUBNET_RESOURCE_ID" \
  --private-connection-resource-id "$EVENTHUB_RESOURCE_ID" \
  --group-id namespace \
  --connection-name "pec-${AZURE_EVENTHUB_NAMESPACE}" \
  --output table

# ── 3. Create private DNS zone ────────────────────────────────────────────────
DNS_ZONE_EXISTS=$(az network private-dns zone show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$DNS_ZONE" \
  --query name --output tsv 2>/dev/null || true)

if [ -z "$DNS_ZONE_EXISTS" ]; then
  echo "Creating private DNS zone: $DNS_ZONE"
  az network private-dns zone create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$DNS_ZONE" \
    --output table
else
  echo "Private DNS zone $DNS_ZONE already exists, skipping."
fi

# ── 4. Link DNS zone to VNet ──────────────────────────────────────────────────
DNS_LINK_NAME="pdnslink-${AZURE_VNET_NAME}"
DNS_LINK_EXISTS=$(az network private-dns link vnet show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --zone-name "$DNS_ZONE" \
  --name "$DNS_LINK_NAME" \
  --query name --output tsv 2>/dev/null || true)

if [ -z "$DNS_LINK_EXISTS" ]; then
  echo "Linking DNS zone to VNet: $AZURE_VNET_NAME"
  az network private-dns link vnet create \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE" \
    --name "$DNS_LINK_NAME" \
    --virtual-network "$VNET_RESOURCE_ID" \
    --registration-enabled false \
    --output table
else
  echo "DNS zone link $DNS_LINK_NAME already exists, skipping."
fi

# ── 5. Register PE NIC via DNS zone group (auto-creates the A record) ─────────
echo "Registering private endpoint DNS record"
DNS_ZONE_ID=$(az network private-dns zone show \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --name "$DNS_ZONE" \
  --query id --output tsv)

az network private-endpoint dns-zone-group create \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --endpoint-name "$AZURE_PRIVATE_ENDPOINT_NAME" \
  --name "default" \
  --private-dns-zone "$DNS_ZONE_ID" \
  --zone-name "servicebus" \
  --output table

echo ""
echo "Done. Verify with:"
echo "  az network private-endpoint show --name $AZURE_PRIVATE_ENDPOINT_NAME --resource-group $AZURE_RESOURCE_GROUP --query 'customDnsConfigs' --output table"
echo "  az network private-dns record-set a list --resource-group $AZURE_RESOURCE_GROUP --zone-name $DNS_ZONE --output table"
