# app/eventgrid_webhook.py
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

router = APIRouter()

@router.post("/eventgrid")
async def eventgrid_webhook(request: Request):
    events = await request.json()

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
