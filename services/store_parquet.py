import io
import pyarrow.csv as pcsv
import pyarrow.parquet as pq
from azure.storage.filedatalake import DataLakeServiceClient
from azure.core.exceptions import ResourceExistsError


def convert_csv_to_parquet(
    adls_account: str,
    adls_key: str,
    src_container: str,
    src_csv_path: str,
    dst_container: str,
    dst_parquet_path: str,
) -> str:
    service = DataLakeServiceClient(
        account_url=f"https://{adls_account}.dfs.core.windows.net",
        credential=adls_key,
    )
    print("1) Connecting to ADLS...")

    # Download CSV
    src_fs = service.get_file_system_client(src_container)
    print("2) Downloading CSV...")
    csv_bytes = src_fs.get_file_client(src_csv_path).download_file().readall()

    # CSV -> Arrow Table
    print("3) Parsing CSV -> Arrow...")
    table = pcsv.read_csv(io.BytesIO(csv_bytes))

    # Arrow Table -> Parquet bytes
    out = io.BytesIO()
    print("4) Writing Parquet to memory...")
    pq.write_table(table, out, compression="snappy")
    out.seek(0)

    # Ensure destination container exists (create if missing)
    dst_fs = service.get_file_system_client(dst_container)
    try:
        dst_fs.create_file_system()
    except ResourceExistsError:
        pass

    # Upload Parquet
    dst_file = dst_fs.get_file_client(dst_parquet_path)
    print("5) Uploading Parquet...")
    dst_file.upload_data(out.read(), overwrite=True)

    return f"https://{adls_account}.dfs.core.windows.net/{dst_container}/{dst_parquet_path}"
