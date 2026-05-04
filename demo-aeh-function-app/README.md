# Azure Event Hub Demo — Function App with VNet Integration

## Overview

This demo extends the [AEH Function App scenario](../demo-aeh/demo.md) by deploying the Azure Function inside a **Virtual Network**, integrated with a dedicated subnet. This matches a corporate network topology (e.g. UBS) where resources must not be exposed to the public internet.

## Architecture

```
FastAPI /upload/function
        ↓
Azure Storage (saehfa)
container: container-eh-fa
        ↓ BlobCreated / BlobUpdated
Event Grid System Topic (evgt-storage-eh-fa)
managed identity ──→ Azure Event Hubs Data Sender role
        ↓ [trusted service bypass when public network disabled]
Azure Event Hub
namespace : evhns-eh-fa  ← public network disabled (script 06)
hub       : evh-eh-fa
partitions: 2
        ↓ [private endpoint: pe-evhns-eh-fa (script 06)]
Azure Function App (func-eh-fa)
function  : process_blob_event
trigger   : Event Hub
runtime   : Python 3.11 — Docker image (egch/func-consumer:latest)
plan      : Elastic Premium EP1
        ↑
subnet    : snet-eh-fa (10.0.1.0/24)   — Function App (delegated)
subnet    : snet-eh-fa-pe (10.0.2.0/24) — Private Endpoint NIC
vnet      : vnet-eh-fa (10.0.0.0/16)
region    : Switzerland North
```

## Azure Resources

| Resource | Name | Type |
|---|---|---|
| Resource Group | `rg-eh-fa` | Switzerland North |
| Network Resource Group | `rg-eh-fa-network` | Switzerland North |
| Virtual Network | `vnet-eh-fa` | 10.0.0.0/16 — in `rg-eh-fa-network` |
| Subnet | `snet-eh-fa` | 10.0.1.0/24 — delegated to `Microsoft.Web/serverFarms` |
| PE Subnet | `snet-eh-fa-pe` | 10.0.2.0/24 — for private endpoint NIC |
| Storage Account | `saehfa` | Standard LRS StorageV2 |
| Storage Container | `container-eh-fa` | Blob container |
| Event Hub Namespace | `evhns-eh-fa` | Standard SKU |
| Event Hub | `evh-eh-fa` | 2 partitions |
| Event Grid System Topic | `evgt-storage-eh-fa` | system-assigned managed identity |
| Event Grid Subscription | `sub-container-eh-fa` | managed identity delivery to Event Hub |
| App Service Plan | `asp-eh-fa` | Elastic Premium EP1 (Linux) |
| Function App | `func-eh-fa` | VNet-integrated |
| Private Endpoint | `pe-evhns-eh-fa` | Event Hub namespace — created by script 06 |
| Private DNS Zone | `privatelink.servicebus.windows.net` | created by script 06 |

## Key Differences from the Container Apps Version

| | Container Apps (acf) | Function App + Subnet (this) |
|---|---|---|
| Hosting | Container Apps Environment | Elastic Premium App Service Plan |
| Networking | Public | VNet-integrated via subnet |
| Subnet delegation | Not required | `Microsoft.Web/serverFarms` |
| VNet routing | N/A | `WEBSITE_VNET_ROUTE_ALL=1` |
| Region | Configurable | Switzerland North |
| Plan SKU | Consumption | EP1 (required for VNet trigger support) |

> **Why is VNet integration on the outbound side?**
> Event Hub does **not** push events to the Function App. The Function App's host opens a
> persistent outbound AMQP connection to Event Hub and continuously polls for new messages:
> ```
> Function App ──(outbound AMQP)──→ Event Hub
>                  "any new messages?"
>                  ← "yes, here are 3" → function invoked
>                  "any new messages?"
>                  ← "no" ...
> ```
> Event Hub never initiates a connection to the Function App. The Function App always
> initiates to Event Hub — so the VNet integration sits on the **outbound** side.

> **Why Elastic Premium and not Consumption?**
> The Function App must keep that persistent outbound AMQP connection alive 24/7.
> Consumption plan cannot maintain a persistent outbound VNet connection — it requires
> at minimum an **Elastic Premium** plan.

## Function Code

Located in [`func_consumer/`](func_consumer/function_app.py). The function has an Event Hub trigger and logs the blob subject, event type, and blob URL for every event received.

```python
@app.event_hub_message_trigger(
    arg_name="event",
    event_hub_name="%EVENT_HUB_NAME%",
    connection="EVENT_HUB_CONNECTION_STRING",
    consumer_group="%EVENT_HUB_CONSUMER_GROUP%",
    cardinality="one",
)
def process_blob_event(event: func.EventHubEvent):
    ...
```

## Docker Image

```
docker.io/egch/func-consumer-ehfa:latest
```

Built from `func_consumer/Dockerfile` using the official Azure Functions Python base image:
```
mcr.microsoft.com/azure-functions/python:4-python3.11
```

## Configuration

### .env

Copy `az-cli/.env.example` to `az-cli/.env` and fill in:

| Variable | Description |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID |
| `AZURE_STORAGE_ACCOUNT_CONNECTION_STRING` | Retrieved after running script 02 |
| `EVENT_HUB_CONNECTION_STRING` | Retrieved after running script 03 |

All other variables have defaults defined in `.env.example`.

### Function App Settings

| Setting | Value |
|---|---|
| `AzureWebJobsStorage` | Storage account connection string |
| `EVENT_HUB_CONNECTION_STRING` | Event Hub namespace connection string |
| `EVENT_HUB_NAME` | `evh-eh-fa` |
| `EVENT_HUB_CONSUMER_GROUP` | `$Default` |
| `WEBSITE_VNET_ROUTE_ALL` | `1` — route all outbound traffic through VNet |

### Event Grid Subscription Filters

- **Event types:** `Microsoft.Storage.BlobCreated`, `Microsoft.Storage.BlobUpdated`, `Microsoft.Storage.BlobDeleted`, `Microsoft.Storage.BlobTierChanged`
- **Subject begins with:** `/blobServices/default/containers/uploads`

## Deployment Scripts

Located in `az-cli/`, run in order:

```shell
cd demo-aeh-function-app
cp az-cli/.env.example az-cli/.env   # fill in your values

./az-cli/00_login.sh                  # authenticate to Azure
./az-cli/01_create_rg_vnet_subnet.sh  # RG + VNet + Subnets (func + PE)
./az-cli/02_create_storage.sh         # storage account + container
./az-cli/03_create_eventhub.sh        # Event Hub namespace + hub
./az-cli/04_create_eventgrid.sh       # wire Event Grid → Event Hub
./az-cli/05_deploy_function.sh        # build image, deploy Function App, VNet integration

# Optional — reproduces the UBS scenario (Event Hub with public access disabled):
./az-cli/06_create_private_endpoint.sh  # private endpoint + DNS zone + disable public access
```

After script 02, retrieve the storage connection string:
```shell
az storage account show-connection-string \
  --name saehfa \
  --resource-group rg-eh-fa \
  --query connectionString --output tsv
```

After script 03, retrieve the Event Hub connection string:
```shell
az eventhubs namespace authorization-rule keys list \
  --resource-group rg-eh-fa \
  --namespace-name evhns-eh-fa \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString --output tsv
```

> **Important:** fill `EVENT_HUB_CONNECTION_STRING` in `.env` before running script 05. Script 05 reads it from `.env` to configure the Function App settings. If it is empty when script 05 runs, the Function App will start but the trigger will fail — and you will have to set all the keys manually in the portal.

## Local Development

`local.settings.json` is committed with empty values as a template. Before running the function locally, populate it from `az-cli/.env`:

```shell
cd demo-aeh-function-app
./func_consumer/load_settings.sh
```

Then start the function locally:

```shell
cd func_consumer
func start
```

> **Note:** `load_settings.sh` overwrites `local.settings.json` with real connection strings — do not commit it afterwards.

## How to Trigger

### Via FastAPI

Upload a file via the FastAPI Swagger UI at http://127.0.0.1:8000/docs — use `POST /upload/function`.

### Via Azure CLI

Open two terminals side by side.

**Terminal 1 — watch live logs:**
```shell
az webapp log tail --name func-eh-fa --resource-group rg-eh-fa
```

**Terminal 2 — upload a blob:**
```shell
echo "hello private event hub" > /tmp/test.txt && \
az storage blob upload \
  --account-name saehfa \
  --account-key $(az storage account keys list --account-name saehfa --resource-group rg-eh-fa --query "[0].value" --output tsv) \
  --container-name container-eh-fa \
  --file /tmp/test.txt \
  --name test.txt
```

> **Note:** `--data` and `--auth-mode login` are not available in CLI ≤ 2.85.0. Use `--file` with `--account-key` instead.

**Expected output in Terminal 1:**
```
Event received: {"subject": "/blobServices/default/containers/container-eh-fa/blobs/test.txt", ...}
Event type : Microsoft.Storage.BlobCreated
Subject    : /blobServices/default/containers/container-eh-fa/blobs/test.txt
Blob URL   : https://saehfa.blob.core.windows.net/container-eh-fa/test.txt
```

This proves the full private chain: Storage → Event Grid (managed identity, trusted bypass) → Event Hub (private endpoint) → Function App (VNet).

## Fixing App Settings from the Portal

If the Function App is running but functions fail to load, the most likely cause is a missing or incorrect app setting. Fix them without redeploying:

**Portal → `func-eh-fa` → Settings → Environment variables → + Add (or click the setting name to edit)**

| Setting | How to get the value |
|---|---|
| `FUNCTIONS_WORKER_RUNTIME` | `python` (literal value) |
| `AzureWebJobsStorage` | `az storage account show-connection-string --name saehfa --resource-group rg-eh-fa --query connectionString --output tsv` |
| `EVENT_HUB_CONNECTION_STRING` | `az eventhubs namespace authorization-rule keys list --resource-group rg-eh-fa --namespace-name evhns-eh-fa --name RootManageSharedAccessKey --query primaryConnectionString --output tsv` |
| `EVENT_HUB_NAME` | `evh-eh-fa` (literal value) |
| `EVENT_HUB_CONSUMER_GROUP` | `$Default` (literal value) |

After editing, click **Apply** → **Confirm**. The Function App restarts automatically.

To verify what is currently set:
```shell
az functionapp config appsettings list --name func-eh-fa --resource-group rg-eh-fa --query "[].{name:name, value:value}" --output table
```

## How to Monitor

### Function invocations

**Portal → `func-eh-fa` → Functions → `process_blob_event` → Invocations**

### Logs via Azure CLI

```shell
az webapp log tail --name func-eh-fa --resource-group rg-eh-fa
```

### Event Hub metrics

**Portal → `evhns-eh-fa` → `evh-eh-fa` → Metrics → Incoming Messages**

### VNet integration status

```shell
az functionapp vnet-integration list \
  --name func-eh-fa \
  --resource-group rg-eh-fa \
  --output table
```

## Private Event Hub — Reproducing the "No Public Access" Scenario

### The problem

In corporate environments (e.g. UBS), the Event Hub namespace is created with public network access disabled. Two separate paths need to work:

| Path | Challenge |
|---|---|
| Event Grid → Event Hub | Event Grid runs in Microsoft's backbone, **not** in our VNet — it cannot use a private endpoint |
| Function App → Event Hub | Function App is VNet-integrated, but the connection string still resolves to the public hostname |

### Path 1 — Event Grid → Event Hub (trusted service + managed identity)

Event Grid cannot use your private endpoint. The only mechanism that allows it to reach a private Event Hub is the **trusted Microsoft services bypass** on the Event Hub network rules. But the bypass only works when Event Grid authenticates with a **managed identity** + proper RBAC — a SAS key won't do.

This is why script 04 now uses a **system topic with system-assigned managed identity** instead of a direct SAS-based subscription:

```
Storage account (BlobCreated/Updated)
  → Event Grid system topic  [system-assigned identity]
      ↓  identity holds "Azure Event Hubs Data Sender" role on the namespace
      ↓  Event Hub network rule: trusted-service-access-enabled = true
  → Event Hub namespace  [public network: Disabled]
```

Script 04 sets this up before public network is ever disabled. Script 06 enables the trusted services bypass when it disables public access — so the Event Grid path keeps working.

### Path 2 — Function App → Event Hub (private endpoint + DNS)

**The Function App is not aware of the private endpoint.** It uses the same connection string as always — `evhns-eh-fa.servicebus.windows.net`. The private endpoint is completely transparent to the application. Here is what happens step by step:

```
Function App connects to evhns-eh-fa.servicebus.windows.net
        ↓
DNS lookup — "what IP is evhns-eh-fa.servicebus.windows.net?"
        ↓
Private DNS zone (linked to the VNet) intercepts the query
        ↓
Returns 10.0.2.4  ← the private endpoint NIC inside the VNet
        ↓
Function App connects to 10.0.2.4 — traffic stays inside the VNet
        ↓
Event Hub accepts the connection (came via private endpoint, not public network)
```

Without the private endpoint, the same DNS lookup returns the public IP — and with `PublicNetworkAccess: Disabled` that connection is rejected.

Each component has exactly one job:

| Component | Job |
|---|---|
| Private endpoint | Creates a NIC with a private IP (e.g. 10.0.2.4) inside the VNet, wired to the Event Hub namespace |
| Private DNS zone | Makes `evhns-eh-fa.servicebus.windows.net` resolve to 10.0.2.4 instead of the public IP — but only from within the VNet |
| VNet integration + `WEBSITE_VNET_ROUTE_ALL=1` | Ensures the Function App's traffic (including DNS queries) goes through the VNet |

```
VNet: vnet-eh-fa (10.0.0.0/16)
  ├── snet-eh-fa      (10.0.1.0/24)  ← Function App
  └── snet-eh-fa-pe   (10.0.2.0/24)  ← Private Endpoint NIC (10.0.2.4)
                              ↑
          Private DNS Zone: privatelink.servicebus.windows.net
            A record: evhns-eh-fa → 10.0.2.4 (auto-registered by zone group)
                              ↑
          DNS zone linked to vnet-eh-fa
```

### Running script 06

Scripts 01–05 must already be deployed. Then:

```shell
./az-cli/06_create_private_endpoint.sh
```

Steps in order:
1. Creates private endpoint `pe-evhns-eh-fa` in `snet-eh-fa-pe`
2. Creates private DNS zone `privatelink.servicebus.windows.net` and links it to the VNet
3. Registers the PE NIC IP in the DNS zone via a zone group (automatic A record)

> Public network access and trusted service access are already configured in script 03 at namespace creation time.

### Verifying the setup

**Confirm public access is disabled and trusted services are enabled:**
```shell
az eventhubs namespace show \
  --name evhns-eh-fa --resource-group rg-eh-fa \
  --query "{publicNetwork:publicNetworkAccess}" --output json

az eventhubs namespace network-rule show \
  --name evhns-eh-fa --resource-group rg-eh-fa \
  --query trustedServiceAccessEnabled --output tsv
```

**Check the private endpoint and its private IP:**
```shell
az network private-endpoint show \
  --name pe-evhns-eh-fa --resource-group rg-eh-fa \
  --query "{state:provisioningState, ip:customDnsConfigs[0].ipAddresses}" \
  --output json
```

**Check the A record was registered in the DNS zone:**
```shell
az network private-dns record-set a list \
  --resource-group rg-eh-fa \
  --zone-name privatelink.servicebus.windows.net \
  --output table
```

**Check Event Grid is delivering (system topic subscription health):**
```shell
az eventgrid system-topic event-subscription show \
  --name sub-container-eh-fa \
  --system-topic-name evgt-storage-eh-fa \
  --resource-group rg-eh-fa \
  --query "{state:provisioningState, lastDelivery:deliveryWithResourceIdentity}" \
  --output json
```

**End-to-end: upload a file and watch Function App logs:**
```shell
az webapp log tail --name func-eh-fa --resource-group rg-eh-fa
```

### Re-enabling public access (rollback)

```shell
az eventhubs namespace update \
  --name evhns-eh-fa --resource-group rg-eh-fa \
  --public-network-access Enabled
```

## Troubleshooting

### Function not triggering — diagnostic chain

**1. Check that `EVENT_HUB_CONNECTION_STRING` is set:**
```shell
az functionapp config appsettings list --name func-eh-fa --resource-group rg-eh-fa --query "[?name=='EVENT_HUB_CONNECTION_STRING'].value" --output tsv
```

**2. Check the Event Grid subscription is healthy:**
```shell
az eventgrid event-subscription show --name "sub-container-eh-fa" \
  --source-resource-id $(az storage account show --name saehfa --resource-group rg-eh-fa --query id --output tsv) \
  --query "{state:provisioningState, endpoint:destination}" --output json
```

**3. Check the Event Hub is reachable:**
```shell
az eventhubs eventhub show --name evh-eh-fa --namespace-name evhns-eh-fa --resource-group rg-eh-fa \
  --query "{partitions:partitionCount, retention:messageRetentionInDays}" --output json
```

**4. Stream live logs while uploading a file:**
```shell
az webapp log tail --name func-eh-fa --resource-group rg-eh-fa
```

### Event Grid system topic managed identity not available immediately

After creating the system topic with `--mi-system-assigned`, the `principalId` is sometimes empty when queried immediately:

```
usage error: --assignee can't be an empty string.
```

The identity may not be registered on creation in CLI ≤ 2.85.0. Script 04 handles this by detecting an empty `principalId` and running a separate `az eventgrid system-topic update --identity SystemAssigned`, then waiting 20 seconds for propagation before retrying.

### Event Grid subscription — `--delivery-identity` not available in CLI ≤ 2.85.0

```
unrecognized arguments: --delivery-identity SystemAssigned --delivery-identity-endpoint ...
```

The managed identity delivery parameters for `az eventgrid system-topic event-subscription create` are not available in this CLI version. Script 04 uses `az rest` with the ARM API instead:

```shell
az rest \
  --method PUT \
  --url "${SYSTEM_TOPIC_RESOURCE_ID}/eventSubscriptions/${SUBSCRIPTION_NAME}?api-version=2022-06-15" \
  --body '{
    "properties": {
      "deliveryWithResourceIdentity": {
        "identity": {"type": "SystemAssigned"},
        "destination": {
          "endpointType": "EventHub",
          "properties": {"resourceId": "<eventhub-resource-id>"}
        }
      },
      "filter": {
        "subjectBeginsWith": "/blobServices/default/containers/<container>",
        "includedEventTypes": ["Microsoft.Storage.BlobCreated", "Microsoft.Storage.BlobUpdated", "Microsoft.Storage.BlobDeleted", "Microsoft.Storage.BlobTierChanged"]
      }
    }
  }'
```

### Portal cannot view Event Hub data when public network is disabled

The portal data explorer connects to the Event Hub data plane over the public endpoint. When `PublicNetworkAccess: Disabled`, you will see:

> "This namespace has public network access disabled, data operations such as Send and View will not work."

Use `az webapp log tail` to observe events as the Function App processes them, or check **Metrics → Incoming Messages** in the portal (management plane, still accessible).

### Azure CLI gotchas for trusted service access

Three issues encountered when enabling trusted service access on a private Event Hub namespace:

**1. Wrong subcommand — `network-rule` does not exist**

```
'network-rule' is misspelled or not recognized by the system.
Did you mean 'network-rule-set'?
```

Use `az eventhubs namespace network-rule-set update`, not `network-rule update`.

**2. `--trusted-service-access-enabled` not available in CLI ≤ 2.85.0**

```
unrecognized arguments: --trusted-service-access-enabled true
```

Use `az rest` to call the ARM API directly:

```shell
NAMESPACE_ID=$(az eventhubs namespace show \
  --name evhns-eh-fa --resource-group rg-eh-fa \
  --query id --output tsv)

az rest \
  --method PUT \
  --url "${NAMESPACE_ID}/networkRuleSets/default?api-version=2024-01-01" \
  --body '{"properties": {"trustedServiceAccessEnabled": true, "defaultAction": "Allow"}}'
```

**3. `defaultAction: Deny` is rejected when `PublicNetworkAccess` is already `Disabled`**

```
InvalidNetworkRuleSetUpdate: This update sets zero IPRule and VirtualNetworkRules
and DefaultAction is Deny. This would render the namespace inaccessible.
If the intention was to restrict to private links only, set PublicNetworkAccess to Disabled.
```

Use `"defaultAction": "Allow"`. The two settings operate at different layers:
- `PublicNetworkAccess: Disabled` — namespace-level, blocks all public traffic
- `trustedServiceAccessEnabled: true` — opens a hole for trusted Microsoft services (Event Grid)
- `defaultAction: Allow` — fine because the namespace-level block already takes precedence

### AuthenticationFailed on `azure-webjobs-eventhub` container

The Event Hub trigger stores checkpoints in blob storage. If `AzureWebJobsStorage` is stale or wrong, the listener fails to start with `AuthenticationFailed`. Fix it in one command:

```shell
az functionapp config appsettings set --name func-eh-fa --resource-group rg-eh-fa \
  --settings "AzureWebJobsStorage=$(az storage account show-connection-string --name saehfa --resource-group rg-eh-fa --query connectionString --output tsv)"
```

The Function App restarts automatically and the trigger will start listening.

## Scaling

- **Min replicas:** 0 — scales to zero when idle
- **Max replicas:** 2 — bounded by partition count (2 partitions = max 2 useful instances)
- Scaling is automatic based on unprocessed messages in the Event Hub
