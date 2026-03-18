import json
import os

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient

SERVICE_BUS_CONNECTION_STRING = os.getenv("SERVICE_BUS_CONNECTION_STRING")
SERVICE_BUS_NAMESPACE = os.getenv("SERVICE_BUS_NAMESPACE", "egch-poc.servicebus.windows.net")
SERVICE_BUS_QUEUE = os.getenv("SERVICE_BUS_QUEUE", "file-process-queue")


def process_message(message_body: str):
    payload = json.loads(message_body)
    job_id = payload.get("job_id")
    blob_path = payload.get("blob_path")
    print(f"job_id: {job_id}")
    print(f"blob_path: {blob_path}")


def main():
    if SERVICE_BUS_CONNECTION_STRING:
        client = ServiceBusClient.from_connection_string(SERVICE_BUS_CONNECTION_STRING)
    else:
        client = ServiceBusClient(SERVICE_BUS_NAMESPACE, DefaultAzureCredential())

    with client:
        with client.get_queue_receiver(SERVICE_BUS_QUEUE, max_wait_time=30) as receiver:
            for message in receiver:
                process_message(str(message))
                receiver.complete_message(message)
                break  # Container Apps Job: process one message per run


if __name__ == "__main__":
    main()
