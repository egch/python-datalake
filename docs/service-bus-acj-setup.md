# Azure Service Bus + Container Apps Job Setup

## Overview

This documents the end-to-end configuration for triggering an Azure Container Apps Job (ACJ) from messages on an Azure Service Bus queue.

## 1. Azure Service Bus

### Create the Namespace and Queue

1. In the Azure portal, create a **Service Bus namespace** (e.g. `egch-poc`)
2. Inside the namespace, create a **Queue** named `file-process-queue`

### Get the Connection String

1. Go to the namespace → **Shared access policies** → `RootManageSharedAccessKey`
2. Copy the **Primary Connection String** — format: `Endpoint=sb://<namespace>.servicebus.windows.net/;SharedAccessKeyName=...;SharedAccessKey=...`

## 2. Build and Push Docker Image to Docker Hub

The job container is built from `job/Dockerfile`.

### Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- A Docker Hub account

### Login

```bash
docker login
```

### Build the Image

```bash
cd job
docker build -t <dockerhub-username>/process-file-job:latest .
```

### Push to Docker Hub

```bash
docker push <dockerhub-username>/process-file-job:latest
```

### Tagging a Specific Version (recommended)

```bash
docker build -t <dockerhub-username>/process-file-job:1.0.0 .
docker push <dockerhub-username>/process-file-job:1.0.0
```

> When updating the job, rebuild, push, and then update the image reference in the Container Apps Job configuration.

## 3. Azure Container Apps Job

### Create the Job

1. In the Azure portal, create a new **Container Apps Job**
2. Set the trigger type to **Event-driven**
3. Set the image to `<dockerhub-username>/process-file-job:latest`

### Environment Variables

Under the job's **Environment variables**, add:

| Name | Value |
|------|-------|
| `SERVICE_BUS_CONNECTION_STRING` | `Endpoint=sb://<namespace>.servicebus.windows.net/;...` |
| `SERVICE_BUS_QUEUE` | `file-process-queue` |

> Note: this env var is used by the Python code at runtime. It is **not** used by the KEDA scaler.

### Secrets

Under the job's **Secrets**, add a secret for the scaler:

| Name | Value |
|------|-------|
| `service-bus-connection-string` | `Endpoint=sb://<namespace>.servicebus.windows.net/;...` |

> The scaler cannot read env vars directly — it requires a secret reference.

## 4. Event-Driven Scale Rule

Under the job's **Event-driven scaling**, add a new scale rule:

| Field | Value |
|-------|-------|
| Rule name | `service-bus-rule` |
| Custom rule type | `azure-servicebus` |

### Scale Parameters

| Name | Value |
|------|-------|
| `queueName` | `file-process-queue` |
| `messageCount` | `1` |

### Authentication

| Secret reference | Trigger parameter |
|-----------------|-------------------|
| `service-bus-connection-string` | `connection` |

> The `connection` trigger parameter is what KEDA uses to authenticate with Service Bus. Without this, the scaler logs: `error parsing azure service bus metadata: no connection setting given`.

## 5. Message Format

Messages published to the queue must be JSON with the following structure:

```json
{
  "job_id": "780ccd08-7ec7-455e-854c-8c31c5c66c55",
  "blob_path": "/path/to/blob.csv"
}
```

## 6. How It Works

1. A message is published to the `file-process-queue` Service Bus queue
2. KEDA detects the message via the scale rule and triggers a new job execution
3. The job container runs `job/main.py`, which:
   - Connects to Service Bus using `SERVICE_BUS_CONNECTION_STRING`
   - Reads one message from the queue
   - Calls `process_message()` with the message body
   - Completes (deletes) the message and exits
4. One job execution is created per message (`messageCount: 1`)

## 7. Viewing Logs

### Log Analytics

Query the console logs in Log Analytics:

```kusto
ContainerAppConsoleLogs_CL
| order by TimeGenerated desc
| project TimeGenerated, Log_s
```

### CLI (stream during execution)

```bash
az containerapp job execution logs show \
  --name <job-name> \
  --resource-group <resource-group> \
  --execution-name <execution-name> \
  --follow
```
