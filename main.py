from dotenv import load_dotenv
load_dotenv()  # reads .env from current working directo

import os
from fastapi import FastAPI, HTTPException, Query
from services.store_parquet import convert_csv_to_parquet
from services.query_products_parquet import get_products_by_category_from_parquet

app = FastAPI()

ADLS_ACCOUNT = "egchdatalake"
SRC_CONTAINER = "product"
DST_CONTAINER = "product-curated"



PARQUET_CONTAINER = "product-curated"
PARQUET_PATH = "products/products.parquet"


@app.post("/convert/products")
def convert_products_csv_to_parquet():
    try:
        adls_key = os.environ["ADLS_ACCOUNT_KEY"]  # set in your env

        parquet_url = convert_csv_to_parquet(
            adls_account=ADLS_ACCOUNT,
            adls_key=adls_key,
            src_container=SRC_CONTAINER,
            src_csv_path="products.csv",
            dst_container=DST_CONTAINER,
            dst_parquet_path="products/products.parquet",
        )

        return {"status": "ok", "parquet_url": parquet_url}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))



from azure.storage.filedatalake import DataLakeServiceClient

@app.get("/check/products-parquet")
def check_parquet():
    key = os.environ["ADLS_ACCOUNT_KEY"]
    service = DataLakeServiceClient(
        account_url=f"https://{ADLS_ACCOUNT}.dfs.core.windows.net",
        credential=key,
    )
    fs = service.get_file_system_client(DST_CONTAINER)

    paths = [p.name for p in fs.get_paths(path="products", recursive=True)]
    return {"paths": paths[:50], "count": len(paths)}



@app.get("/products/by-category")
def products_by_category(
    category: str = Query(..., description="Product category, e.g. 'Mountain Bikes'")
):
    key = os.environ.get("ADLS_ACCOUNT_KEY")
    if not key:
        raise HTTPException(status_code=500, detail="ADLS_ACCOUNT_KEY not set")

    return get_products_by_category_from_parquet(
        adls_account=ADLS_ACCOUNT,
        adls_key=key,
        container=PARQUET_CONTAINER,
        parquet_path=PARQUET_PATH,
        category=category,
    )