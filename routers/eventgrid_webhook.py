# app/eventgrid_webhook.py
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse


from typing import List, Optional
from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()

@router.post("/eventgrid")
async def eventgrid_webhook(request: Request):

    print("---- RAW EVENTGRID PAYLOAD ----")
    events = await request.json()
    print(events)
    print("--------------------------------")

    # Event Grid always sends a list of events
    if not isinstance(events, list) or not events:
        return JSONResponse({"ok": True})

    first_event = events[0]
    event_type = first_event.get("eventType")

    # 1️⃣ Subscription validation (MANDATORY)
    if event_type == "Microsoft.EventGrid.SubscriptionValidationEvent":
        validation_code = first_event["data"]["validationCode"]
        return JSONResponse({"validationResponse": validation_code})

    # 2️⃣ Real events (e.g. BlobCreated)
    for event in events:
        if event.get("eventType") == "Microsoft.Storage.BlobCreated":
            subject = event.get("subject")
            data = event.get("data", {})
            blob_url = data.get("url")

            # 🔥 DO NOT do heavy work here
            print("[eventgrid] blob created:", subject, blob_url)

            # Best practice:
            # - push blob_url to internal queue
            # - or store minimal metadata in DB
            # - or trigger async background task

    # Always ACK fast
    return JSONResponse({"ok": True})





class EventGridData(BaseModel):
    url: Optional[str] = None
    validationCode: Optional[str] = None


class EventGridEvent(BaseModel):
    id: str
    eventType: str
    subject: Optional[str] = None
    data: EventGridData


@router.post("/eventgrid-param")
async def eventgrid_webhook_param(events: List[EventGridEvent]):
    first_event = events[0]
    event_type = first_event.eventType

    if event_type == "Microsoft.EventGrid.SubscriptionValidationEvent":
        return {"validationResponse": first_event.data.validationCode}

    for event in events:
        if event.eventType == "Microsoft.Storage.BlobCreated":
            print("[eventgrid] blob created:", event.subject, event.data.url)

    return {"ok": True}
