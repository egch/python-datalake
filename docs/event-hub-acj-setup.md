# Azure Event Hub + Container Apps Job Setup

## Overview

This documents the end-to-end configuration for triggering an Azure Container Apps Job (ACJ) from events on an Azure Event Hub. The API exposes `POST /jobs/trigger-aeh` which publishes an event; KEDA detects unprocessed events and scales the job.

## 1. Azure Event Hub

### Create the Namespace and Event Hub

1. In the Azure portal, create an **Event Hubs namespace** (e.g. `egch-poc`)
2. Inside the namespace, create an **Event Hub** named `file-process-hub`
3. Create a **Consumer Group** (or use `$Default`)

### Get the Connection String

1. Go to the namespace → **Shared access policies** → `RootManageSharedAccessKey`
2. Copy the **Primary Connection String** — format: `Endpoint=sb://<namespace>.servicebus.windows.net/;SharedAccessKeyName=...;SharedAccessKey=...`

## 2. Azure Storage — Checkpoint Container

KEDA and the consumer need a blob container to store event offsets (checkpoints).

1. In the Azure portal, open your Storage Account (e.g. `egchdatalake`)
2. Create a **Blob container** named `eventhub-checkpoints`
3. Copy the **Connection String** from the storage account → **Access keys**

## 3. Build and Push Docker Image

The job container is built from `job_aeh/Dockerfile`.

```bash
cd aeh
docker build -t <dockerhub-username>/process-file-job-eh:latest .
docker push <dockerhub-username>/process-file-job-eh:latest
```

## 4. Azure Container Apps Job

### Create the Job

1. In the Azure portal, create a new **Container Apps Job**
2. Set the trigger type to **Event-driven**
3. Set the image to `<dockerhub-username>/process-file-job-eh:latest`

### Environment Variables

| Name | Value |
|------|-------|
| `EVENT_HUB_CONNECTION_STRING` | `Endpoint=sb://<namespace>.servicebus.windows.net/;...` |
| `EVENT_HUB_NAME` | `file-process-hub` |
| `EVENT_HUB_CONSUMER_GROUP` | `$Default` |
| `CHECKPOINT_STORAGE_CONNECTION_STRING` | `DefaultEndpointsProtocol=https;AccountName=...` |
| `CHECKPOINT_CONTAINER` | `eventhub-checkpoints` |

### Secrets

Add secrets for the KEDA scaler (it cannot read env vars directly):

| Name | Value |
|------|-------|
| `event-hub-connection-string` | `Endpoint=sb://<namespace>.servicebus.windows.net/;...` |
| `storage-connection-string` | `DefaultEndpointsProtocol=https;AccountName=...` |

## 5. Event-Driven Scale Rule

Under the job's **Event-driven scaling**, add a new scale rule:

| Field | Value |
|-------|-------|
| Rule name | `event-hub-rule` |
| Custom rule type | `azure-eventhub` |

### Scale Parameters

| Name | Value |
|------|-------|
| `consumerGroup` | `$Default` |
| `unprocessedEventThreshold` | `1` |
| `blobContainer` | `eventhub-checkpoints` |

### Authentication

| Secret reference | Trigger parameter |
|-----------------|-------------------|
| `event-hub-connection-string` | `connection` |
| `storage-connection-string` | `storageConnection` |

> Both `connection` and `storageConnection` are required. KEDA uses the storage connection to read checkpoints and determine how many events are unprocessed.

## 6. Message Format

Events published to the hub must be JSON with the following structure:

```json
{
  "job_id": "780ccd08-7ec7-455e-854c-8c31c5c66c55",
  "blob_path": "/path/to/blob.csv"
}
```

## 7. How It Works

1. A request hits `POST /jobs/trigger-aeh`
2. The API publishes an `EventData` batch to the Event Hub
3. KEDA reads the checkpoint store to calculate unprocessed events and triggers a new job execution
4. The job container runs `job_aeh/main.py`, which:
   - Connects to Event Hub using `EVENT_HUB_CONNECTION_STRING`
   - Reads one event from the hub
   - Calls `process_message()` with the event body
   - Updates the checkpoint (so KEDA knows the event is processed)
   - Closes the client and exits
5. One job execution is created per unprocessed event (`unprocessedEventThreshold: 1`)

## 8. Key Difference vs Service Bus

| | Service Bus | Event Hub |
|--|-------------|-----------|
| Consumption model | Competing consumers, message deleted after ack | Each consumer group tracks its own offset |
| Checkpoint | Built into the queue (message lock / complete) | External blob storage |
| KEDA scaler | `azure-servicebus` | `azure-eventhub` |
| KEDA auth params | `connection` | `connection` + `storageConnection` |
| Replay | No | Yes (within retention period) |

## 9. Viewing Logs

```kusto
ContainerAppConsoleLogs_CL
| order by TimeGenerated desc
| project TimeGenerated, Log_s
```

```bash
az containerapp job execution logs show \
  --name <job-name> \
  --resource-group <resource-group> \
  --execution-name <execution-name> \
  --follow
```
