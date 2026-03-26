import json
import os

from azure.eventhub import EventHubConsumerClient
from azure.eventhub.extensions.checkpointstoreblob import BlobCheckpointStore
from azure.identity import DefaultAzureCredential

EVENT_HUB_CONNECTION_STRING = os.getenv("EVENT_HUB_CONNECTION_STRING")
EVENT_HUB_NAMESPACE = os.getenv("EVENT_HUB_NAMESPACE", "egch-poc.servicebus.windows.net")
EVENT_HUB_NAME = os.getenv("EVENT_HUB_NAME", "file-process-hub")
EVENT_HUB_CONSUMER_GROUP = os.getenv("EVENT_HUB_CONSUMER_GROUP", "$Default")
CHECKPOINT_STORAGE_CONNECTION_STRING = os.getenv("CHECKPOINT_STORAGE_CONNECTION_STRING")
CHECKPOINT_CONTAINER = os.getenv("CHECKPOINT_CONTAINER", "eventhub-checkpoints")


def process_message(message_body: str):
    payload = json.loads(message_body)
    job_id = payload.get("job_id")
    blob_path = payload.get("blob_path")
    print(f"job_id: {job_id}")
    print(f"blob_path: {blob_path}")


def main():
    checkpoint_store = BlobCheckpointStore.from_connection_string(
        CHECKPOINT_STORAGE_CONNECTION_STRING, CHECKPOINT_CONTAINER
    )

    if EVENT_HUB_CONNECTION_STRING:
        client = EventHubConsumerClient.from_connection_string(
            EVENT_HUB_CONNECTION_STRING,
            consumer_group=EVENT_HUB_CONSUMER_GROUP,
            eventhub_name=EVENT_HUB_NAME,
            checkpoint_store=checkpoint_store,
        )
    else:
        client = EventHubConsumerClient(
            fully_qualified_namespace=EVENT_HUB_NAMESPACE,
            eventhub_name=EVENT_HUB_NAME,
            consumer_group=EVENT_HUB_CONSUMER_GROUP,
            credential=DefaultAzureCredential(),
            checkpoint_store=checkpoint_store,
        )

    def on_event(partition_context, event):
        if event is None:
            return
        process_message(event.body_as_str())
        partition_context.update_checkpoint(event)
        client.close()  # Container Apps Job: process one event per run

    with client:
        client.receive(on_event=on_event, max_wait_time=30)


if __name__ == "__main__":
    main()
