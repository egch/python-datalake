import io
from typing import List, Dict

import pyarrow.compute as pc
import pyarrow.parquet as pq
from azure.storage.filedatalake import DataLakeServiceClient


def get_products_by_category_from_parquet(
    *,
    adls_account: str,
    adls_key: str,
    container: str,
    parquet_path: str,
    category: str,
) -> List[Dict]:
    service = DataLakeServiceClient(
        account_url=f"https://{adls_account}.dfs.core.windows.net",
        credential=adls_key,
    )

    fs = service.get_file_system_client(container)
    parquet_bytes = fs.get_file_client(parquet_path).download_file().readall()

    table = pq.read_table(io.BytesIO(parquet_bytes))

    # Filter Category == "Mountain Bikes"
    filtered = table.filter(pc.field("Category") == category)

    # Convert to list[dict] for JSON response
    return filtered.to_pylist()
