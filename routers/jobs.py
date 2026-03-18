import json
import uuid

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from core.config import SERVICE_BUS_CONNECTION_STRING, SERVICE_BUS_NAMESPACE, SERVICE_BUS_QUEUE

router = APIRouter(tags=["jobs"])


class JobRequest(BaseModel):
    blob_path: str


@router.post("/jobs/trigger")
def trigger_job(request: JobRequest):
    job_id = str(uuid.uuid4())
    payload = json.dumps({"job_id": job_id, "blob_path": request.blob_path})

    try:
        if SERVICE_BUS_CONNECTION_STRING:
            client = ServiceBusClient.from_connection_string(SERVICE_BUS_CONNECTION_STRING)
        else:
            client = ServiceBusClient(SERVICE_BUS_NAMESPACE, DefaultAzureCredential())

        with client:
            with client.get_queue_sender(SERVICE_BUS_QUEUE) as sender:
                sender.send_messages(ServiceBusMessage(payload))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {"job_id": job_id, "status": "queued"}
