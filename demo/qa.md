# Q&A — POC Demo Preparation

Anticipated questions and answers for the event-driven file processing POC demo.

---

## Architecture & Flow

**Q: When I hit the API, what happens before the job runs?**

The caller sends a `POST /jobs/trigger` with a `blob_path`. FastAPI generates a `job_id` (UUID internally — not provided by the caller), builds a JSON payload, and sends it as a message to the Azure Service Bus queue. KEDA detects the message within 2 seconds and starts a new Container Job execution. The container reads the message, processes it, completes (deletes) the message, and exits.

---

**Q: Is the Container Job listening to the queue?**

No. There is no container sitting idle waiting for messages. KEDA polls the queue every 2 seconds. When it detects messages it calculates how many executions to spawn and starts fresh containers. The containers only exist for the duration of one message, then shut down. This means zero compute cost when the queue is empty.

---

**Q: Can I keep at least one container always running?**

Yes — set Min executions to 1 or more. That container stays alive even when the queue is empty, eliminating cold start latency. The trade-off is you pay for it continuously.

---

**Q: What if 50 messages arrive at the same time?**

KEDA calculates: `ceil(50 / messageCount)`. With `messageCount = 5`, that's 10 executions. Each processes 1 message and exits. The remaining 40 messages are picked up in subsequent polling cycles (every 2 seconds).

---

**Q: What if the job crashes mid-processing? Does the message get lost?**

No. The message is only deleted from the queue when `receiver.complete_message()` is called. If the job crashes before that line, Service Bus keeps the message and makes it available for retry. After the max delivery count is exceeded, it moves to the dead-letter queue for manual inspection. Note: in this POC, Container Job retry is set to 0 — retries are handled at the Service Bus level.

---

## Technology Choices

**Q: Why not Kafka?**

Kafka is built for high-throughput, ordered, replayable event streams — millions of events per second, multiple consumers, replay history. Here we need simple async job triggering. Service Bus is lighter, fully managed, cheaper, and already in the Azure ecosystem. Short version: *Kafka is a firehose, Service Bus is a queue. We need a queue.*

---

**Q: Why not Prefect (or another orchestrator)?**

Prefect is a workflow orchestrator — great for complex pipelines with dependencies, retries, scheduling, and branching logic. Here the job is a single step: receive message → process file → done. No DAG, no dependencies. Adding Prefect would be an orchestration layer for something that doesn't need orchestration. If the processing logic grows into a multi-step pipeline, Prefect would become relevant.

---

**Q: Why Docker Hub instead of ACR?**

Docker Hub was convenient for the POC. In a real org, Azure Container Registry (ACR) makes more sense: images stay private, it's closer to the Azure infrastructure (faster pulls, no external dependency), and it integrates natively with managed identity — no credentials needed to pull the image.

---

## Extensibility

**Q: What if I need to process different file types with different code?**

Three options, in order of complexity:

1. **Multiple queues + multiple jobs** — one queue and one Container Job per file type. Clean separation, operationally heavy.

2. **Single queue, routing inside the job** — include file type in the message payload; the job dispatches to the right function internally. Simple to operate but the image grows over time.

3. **Service Bus Topics + Subscriptions** *(recommended)* — use a Topic instead of a queue. Each file type gets a Subscription with a filter rule, feeding its own Container Job. Azure does the routing, no code changes needed.

```
FastAPI → Topic
              ├── csv-subscription      → ACJ (csv job)
              ├── parquet-subscription  → ACJ (parquet job)
              └── json-subscription     → ACJ (json job)
```

If processing per file type becomes multi-step, that's when Prefect becomes the right tool.

---

## Logging & Observability

**Q: Can I log to a filesystem instead of Log Analytics Workspace?**

Container Jobs have no persistent local filesystem — everything is lost when the container exits. Options:

- **Azure Blob Storage** — write a log file per execution to a blob container. Simple and cheap, but not queryable.
- **Azure Files (SMB mount)** — mount a file share as a volume; the job writes logs like a normal file. Works, but adds coupling.

In practice, containerized workloads treat logs as streams, not files (12-factor principle), so filesystem logging is uncommon.

---

**Q: Can I send logs to Splunk?**

Yes. Two approaches:

**Option 1 — Direct via Splunk HEC (recommended for existing Splunk orgs)**

Use the Splunk HTTP Event Collector. The job sends log events via HTTP directly to Splunk. Just add a logging handler — no infrastructure change needed. Inject `SPLUNK_HEC_TOKEN` and `SPLUNK_HOST` as environment variables in the Container Job, same pattern as `SERVICE_BUS_CONNECTION_STRING`.

**Option 2 — Via Event Hub (enterprise pipeline)**

```
Container Job stdout → LAWS → Export → Azure Event Hub → Splunk Connect → Splunk
```

More moving parts but keeps the job code clean.
