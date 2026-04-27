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
Event Grid Subscription (sub-container-eh-fa)
        ↓
Azure Event Hub
namespace : evhns-eh-fa
hub       : evh-eh-fa
partitions: 2
        ↓
Azure Function App (func-eh-fa)
function  : process_blob_event
trigger   : Event Hub
runtime   : Python 3.11 — Docker image (egch/func-consumer:latest)
plan      : Elastic Premium EP1
        ↑
subnet    : snet-eh-fa (10.0.1.0/24)
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
| Storage Account | `saehfa` | Standard LRS StorageV2 |
| Storage Container | `container-eh-fa` | Blob container |
| Event Hub Namespace | `evhns-eh-fa` | Standard SKU |
| Event Hub | `evh-eh-fa` | 2 partitions |
| Event Grid Subscription | `sub-container-eh-fa` | BlobCreated + BlobUpdated |
| App Service Plan | `asp-eh-fa` | Elastic Premium EP1 (Linux) |
| Function App | `func-eh-fa` | VNet-integrated |

## Key Differences from the Container Apps Version

| | Container Apps (acf) | Function App + Subnet (this) |
|---|---|---|
| Hosting | Container Apps Environment | Elastic Premium App Service Plan |
| Networking | Public | VNet-integrated via subnet |
| Subnet delegation | Not required | `Microsoft.Web/serverFarms` |
| VNet routing | N/A | `WEBSITE_VNET_ROUTE_ALL=1` |
| Region | Configurable | Switzerland North |
| Plan SKU | Consumption | EP1 (required for VNet trigger support) |

> **Why Elastic Premium and not Consumption?**
> Consumption plan supports VNet integration for outbound traffic only.
> Triggering from a private Event Hub endpoint requires at minimum an **Elastic Premium** plan.

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

## CI/CD

A GitLab CI pipeline is provided in [`.gitlab-ci.yml`](.gitlab-ci.yml). It triggers automatically when `func_consumer/` changes and rebuilds and pushes the Docker image. Two CI/CD variables are required: `DOCKER_HUB_USER` and `DOCKER_HUB_TOKEN` (set under **Settings → CI/CD → Variables** in GitLab).

> This file is GitLab-specific and is not compatible with GitHub Actions.

## Deployment Scripts

Located in `az-cli/`, run in order:

```shell
cd demo-aeh-function-app
cp az-cli/.env.example az-cli/.env   # fill in your values

./az-cli/00_login.sh                  # authenticate to Azure
./az-cli/01_create_rg_vnet_subnet.sh  # RG + VNet + Subnet
./az-cli/02_create_storage.sh         # storage account + container
./az-cli/03_create_eventhub.sh        # Event Hub namespace + hub
./az-cli/04_create_eventgrid.sh       # wire Event Grid → Event Hub
./az-cli/05_deploy_function.sh        # build image, deploy Function App, VNet integration
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

Upload a file via the FastAPI Swagger UI at http://127.0.0.1:8000/docs — use `POST /upload/function`.

This lands the blob in the `container-eh-fa` container → Event Grid fires `BlobCreated` → Event Hub receives the message → Azure Function triggers and logs the event.

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
