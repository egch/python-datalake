import os
from dotenv import load_dotenv

load_dotenv()

AZURE_STORAGE_ACCOUNT_CONNECTION_STRING = os.getenv("AZURE_STORAGE_ACCOUNT_CONNECTION_STRING")
CONTAINER_LARGE_UPLOAD = os.getenv("CONTAINER_LARGE_UPLOAD", "large-uploads")
SAS_EXPIRY_HOURS = int(os.getenv("SAS_EXPIRY_HOURS", "1"))
