from azure.storage.blob import BlobServiceClient
from fastapi import APIRouter, HTTPException, UploadFile

from core.config import (
    AZURE_STORAGE_ACCOUNT_CONNECTION_STRING,
    CONTAINER_FUNCTION,
    CONTAINER_JOB,
)

router = APIRouter(prefix="/upload", tags=["upload"])


def _upload_to_container(container: str, file: UploadFile) -> dict:
    try:
        client = BlobServiceClient.from_connection_string(AZURE_STORAGE_ACCOUNT_CONNECTION_STRING)
        blob_client = client.get_blob_client(container=container, blob=file.filename)
        blob_client.upload_blob(file.file, overwrite=True)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {"container": container, "blob": file.filename, "status": "uploaded"}


@router.post("/function")
def upload_for_function(file: UploadFile):
    """Upload a file to the container processed by the Azure Function."""
    return _upload_to_container(CONTAINER_FUNCTION, file)


@router.post("/job")
def upload_for_job(file: UploadFile):
    """Upload a file to the container processed by the Azure Container Job."""
    return _upload_to_container(CONTAINER_JOB, file)
