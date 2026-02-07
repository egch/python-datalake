from azure.storage.filedatalake import DataLakeServiceClient
from core.config import ADLS_ACCOUNT

def get_datalake_service_client(adls_key: str) -> DataLakeServiceClient:
    return DataLakeServiceClient(
        account_url=f"https://{ADLS_ACCOUNT}.dfs.core.windows.net",
        credential=adls_key,
    )
