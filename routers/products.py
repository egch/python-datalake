from fastapi import APIRouter, HTTPException, Query

from core.config import (
    ADLS_ACCOUNT,
    SRC_CONTAINER,
    DST_CONTAINER,
    PARQUET_CONTAINER,
    PARQUET_PATH,
    require_adls_key,
)
from core.adls import get_datalake_service_client
from services.store_parquet import convert_csv_to_parquet
from services.query_products_parquet import get_products_by_category_from_parquet

router = APIRouter(tags=["products"])


@router.post("/convert/products")
def convert_products_csv_to_parquet():
    try:
        adls_key = require_adls_key()

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


@router.get("/check/products-parquet")
def check_parquet():
    try:
        adls_key = require_adls_key()
        service = get_datalake_service_client(adls_key)
        fs = service.get_file_system_client(DST_CONTAINER)

        paths = [p.name for p in fs.get_paths(path="products", recursive=True)]
        return {"paths": paths[:50], "count": len(paths)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/products/by-category")
def products_by_category(
    category: str = Query(..., description="Product category, e.g. 'Mountain Bikes'")
):
    try:
        adls_key = require_adls_key()
        return get_products_by_category_from_parquet(
            adls_account=ADLS_ACCOUNT,
            adls_key=adls_key,
            container=PARQUET_CONTAINER,
            parquet_path=PARQUET_PATH,
            category=category,
        )
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
