from fastapi import FastAPI

app = FastAPI(title="Azure Connector API")

@app.get("/health")
def health():
    return {"status": "ok"}
