import os
from dotenv import load_dotenv

# carica .env una sola volta all'avvio
load_dotenv()

ADLS_ACCOUNT = os.getenv("ADLS_ACCOUNT")
SRC_CONTAINER = os.getenv("SRC_CONTAINER", "product")
DST_CONTAINER = os.getenv("DST_CONTAINER", "product-curated")

PARQUET_CONTAINER = os.getenv("PARQUET_CONTAINER", "product-curated")
PARQUET_PATH = os.getenv("PARQUET_PATH", "products/products.parquet")

SERVICE_BUS_CONNECTION_STRING = os.getenv("SERVICE_BUS_CONNECTION_STRING")
SERVICE_BUS_NAMESPACE = os.getenv("SERVICE_BUS_NAMESPACE", "egch-poc.servicebus.windows.net")
SERVICE_BUS_QUEUE = os.getenv("SERVICE_BUS_QUEUE", "file-process-queue")

def require_adls_key() -> str:
    key = os.environ.get("ADLS_ACCOUNT_KEY")
    if not key:
        raise RuntimeError("ADLS_ACCOUNT_KEY not set")
    return key
