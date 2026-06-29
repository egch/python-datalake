from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from routers import upload

app = FastAPI(
    title="Large File Upload POC",
    description="Demonstrates direct-to-Azure-Blob large file uploads via SAS presigned URLs.",
    version="0.1.0",
)

app.mount("/static", StaticFiles(directory="static"), name="static")
app.include_router(upload.router)


@app.get("/", include_in_schema=False)
def index():
    return FileResponse("static/index.html")
