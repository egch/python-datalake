# Azure Event Hub Demo — Azure Function Consumer

## Overview

This demo shows an event-driven architecture where uploading a blob to Azure Storage
automatically triggers an Azure Function via Event Grid and Event Hub.

## Flow

```
FastAPI /upload/function
        ↓
Azure Storage (egchsaaeh)
container: blobs-processed-by-function
        ↓ BlobCreated / BlobUpdated
Event Grid Subscription (sub-blobs-processed-by-function)
        ↓
Azure Event Hub
namespace : egch-poc-aeh
hub       : blobs-processed-by-function-hub
partitions: 2
        ↓
Azure Function (egch-func-consumer)
function  : process_blob_event
trigger   : Event Hub
runtime   : Python 3.11 on Container Apps (Consumption plan)
```

## Azure Resources

| Resource | Name | Type |
|---|---|---|
| Storage account | `egchsaaeh` | Standard StorageV2 |
| Storage container | `blobs-processed-by-function` | Blob container |
| Event Grid subscription | `sub-blobs-processed-by-function` | EventGrid |
| Event Hub namespace | `egch-poc-aeh` | Standard |
| Event Hub | `blobs-processed-by-function-hub` | 2 partitions |
| Container Apps Environment | `egch-container-env` | Consumption |
| Log Analytics Workspace | `egch-logs` | LAWS |
| Function App | `egch-func-consumer` | Container Apps hosted |

## Configuration

### Event Grid Subscription Filters
- **Event types:** `Microsoft.Storage.BlobCreated`, `Microsoft.Storage.BlobUpdated`
- **Subject begins with:** `/blobServices/default/containers/blobs-processed-by-function`

### Azure Function App Settings
| Setting | Value |
|---|---|
| `EVENT_HUB_CONNECTION_STRING` | Full connection string for `egch-poc-aeh` |
| `EVENT_HUB_NAME` | `blobs-processed-by-function-hub` |
| `EVENT_HUB_CONSUMER_GROUP` | `$Default` |
| `AzureWebJobsStorage` | Full connection string for `egchsaaeh` |

### Scaling
- **Min replicas:** 0 (scales to zero when idle)
- **Max replicas:** 10 (bounded by partition count — 2 partitions = max 2 useful instances)
- Scaling is automatic based on number of unprocessed messages in the Event Hub

## Docker Image

The Azure Function is packaged as a Docker image and published to Docker Hub:

```
docker.io/egch/func-consumer:latest
```

Built from `func_consumer/Dockerfile` using the official Azure Functions Python base image:
```
mcr.microsoft.com/azure-functions/python:4-python3.11
```

## Deployment Scripts

Located in `azure-cli/`, run in order:

```shell
source .env
./azure-cli/00_login.sh                # authenticate to Azure
./azure-cli/01_create_storage.sh       # create storage account + container
./azure-cli/02_create_eventhub.sh      # create Event Hub namespace + hub
./azure-cli/03_create_eventgrid.sh     # wire Event Grid → Event Hub
./azure-cli/04_deploy_function.sh      # build image, deploy Function App, set env vars
```

## How to Trigger

Upload a file via the FastAPI endpoint:

```
POST http://127.0.0.1:8000/upload/function
Body: multipart/form-data — file
```

Or via Swagger UI: http://127.0.0.1:8000/docs

## How to Monitor

### Function invocations
**Portal → `egch-func-consumer` → Functions → `process_blob_event` → Invocations**

### Logs in Log Analytics Workspace
```kql
ContainerAppConsoleLogs
| where ContainerName contains "egch-func-consumer"
| order by TimeGenerated desc
| project TimeGenerated, Log
```

### Event Hub metrics
**Portal → Event Hub namespace → `blobs-processed-by-function-hub` → Metrics → Incoming Messages**
