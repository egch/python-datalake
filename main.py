# app/main.py
from dotenv import load_dotenv
load_dotenv()  # IMPORTANT if you use .env

from fastapi import FastAPI
from routers.products import router as products_router
from routers.eventgrid_webhook import router as eventgrid_router

from services.consumer import AzureQueueListener  # <-- your consumer.py

listener = AzureQueueListener()

app = FastAPI()
app.include_router(products_router)
app.include_router(eventgrid_router)

#@app.on_event("startup")
async def startup_event():
    print("### startup: starting queue listener ###", flush=True)
    await listener.start()

#@app.on_event("shutdown")
async def shutdown_event():
    print("### shutdown: stopping queue listener ###", flush=True)
    await listener.stop()
