from datetime import datetime, timedelta, timezone

from azure.storage.blob import BlobServiceClient, BlobSasPermissions, generate_blob_sas
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from core.config import (
    AZURE_STORAGE_ACCOUNT_CONNECTION_STRING,
    CONTAINER_LARGE_UPLOAD,
    SAS_EXPIRY_HOURS,
)

router = APIRouter(prefix="/upload", tags=["upload"])


class PresignedUrlRequest(BaseModel):
    filename: str
    container: str = CONTAINER_LARGE_UPLOAD


class PresignedUrlResponse(BaseModel):
    sas_url: str
    blob_name: str
    container: str
    expires_at: str


@router.post("/presigned-url", response_model=PresignedUrlResponse)
def get_presigned_url(req: PresignedUrlRequest):
    """
    Returns a time-limited, write-only SAS URL for a specific blob.
    The client uploads directly to Azure — the file never passes through this server.
    Supports files of any size (Azure block blob handles chunking up to 5 TB).
    """
    try:
        client = BlobServiceClient.from_connection_string(AZURE_STORAGE_ACCOUNT_CONNECTION_STRING)
        account_name = client.credential.account_name
        account_key = client.credential.account_key

        expiry = datetime.now(timezone.utc) + timedelta(hours=SAS_EXPIRY_HOURS)

        sas_token = generate_blob_sas(
            account_name=account_name,
            container_name=req.container,
            blob_name=req.filename,
            account_key=account_key,
            permission=BlobSasPermissions(write=True, create=True),
            expiry=expiry,
        )

        sas_url = (
            f"https://{account_name}.blob.core.windows.net"
            f"/{req.container}/{req.filename}?{sas_token}"
        )

        return PresignedUrlResponse(
            sas_url=sas_url,
            blob_name=req.filename,
            container=req.container,
            expires_at=expiry.isoformat(),
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/complete")
def upload_complete(blob_name: str, container: str = CONTAINER_LARGE_UPLOAD):
    """
    Called by the client after a direct upload finishes.
    Hook this up to trigger downstream processing (queue message, Event Grid, etc.).
    """
    # TODO: send message to Service Bus / Event Hub to kick off processing
    return {"status": "received", "blob": blob_name, "container": container}
