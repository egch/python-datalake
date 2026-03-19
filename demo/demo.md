# 📦 POC: Event-Driven File Processing with Azure Container Jobs

This document describes the end-to-end flow:

➡️ FastAPI → Service Bus → Queue → Azure Container Job → Processing → Logs (Log Analytics)

---

## 🧭 High-Level Flow

1. A request is sent to **FastAPI**
2. FastAPI pushes a message to **Azure Service Bus Queue**
3. The queue triggers an **Azure Container Job**
4. The job processes the file (from Blob Storage)
5. Logs are collected in **Log Analytics Workspace**

---

### 🚀 1. FastAPI – Trigger Job

FastAPI exposes an endpoint to trigger the process.

- Endpoint: `POST /jobs/trigger`
- Input: blob path

Example request:

{
  "blob_path": "file-a.csv"
}

![FastAPI Endpoint](images/fast-api-endpoint.png)

---

### 📬 2. Service Bus Queue

FastAPI sends a message to the **Service Bus Queue**.

The message contains:
- job_id
- blob_path

![Service Bus Queue](images/service-bus-queue-peek.png)

---

### ⚙️ 3. Event-Driven Azure Container Job

The Container Job is configured with **event-driven scaling** using Service Bus.

- Trigger type: azure-servicebus
- Queue: file-process-queue
- Activation rule: messageCount >= 5

![Event Driven Scaling](images/event-driven-scaling.png)

![Scale Rule](images/scale-rule.png)

---

### 🐳 4. Container Job Configuration

The job runs a Docker image pulled from Docker Hub:

docker.io/egch/python-datalake-job:latest

![Container Config](images/acj-image-configuration.png)

---

### ▶️ 5. Job Execution

Each message triggers a job execution.

- Parallelism: 1
- Completion count: 1
- Execution duration: ~15–45 seconds

![Job History](images/job-history.png)

---

### 🧠 6. Processing Logic

Inside the container:

- Reads blob_path from message
- Downloads file from Azure Blob Storage
- Processes data (POC logic)
- Outputs logs

Example log:

blob_path: file-a.csv

---

### The code 
[job code](../job/main.py)

## 📊 7. Log Analytics Workspace

All logs are collected in **Log Analytics Workspace**.

You can query:

- container logs
- execution metadata
- errors

![Log Analytics](images/log-analytics-ws.png)

---

## 🏁 8. Azure Container Job Overview

Main configuration:

- Trigger Type: Event
- Workload: Consumption
- Retry: 0
- Timeout: 1800s

![Job Overview](images/process-file-job.png)

---

## ✅ Summary

This POC demonstrates:

- Decoupled architecture (API ≠ processing)
- Event-driven execution
- Scalable background processing
- Fully managed Azure components
- Centralized logging

---

## 💡 Next Improvements

- Use Azure Container Registry (ACR) instead of Docker Hub
- Add retry / dead-letter handling
- Add monitoring alerts
- Improve parallelism & batching
- Add idempotency for job execution

---

## 🧱 Architecture Benefits

- No long-running threads in FastAPI
- Fully async processing
- Scales automatically with queue load
- Clear separation of concerns