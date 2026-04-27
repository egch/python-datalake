import json
import logging

import azure.functions as func

app = func.FunctionApp()


@app.event_hub_message_trigger(
    arg_name="event",
    event_hub_name="%EVENT_HUB_NAME%",
    connection="EVENT_HUB_CONNECTION_STRING",
    consumer_group="%EVENT_HUB_CONSUMER_GROUP%",
    cardinality="one",
)
def process_blob_event(event: func.EventHubEvent):
    message_body = event.get_body().decode("utf-8")
    logging.info("Event received: %s", message_body)

    payload = json.loads(message_body)

    # Event Grid sends events as a list
    events = payload if isinstance(payload, list) else [payload]

    for event_data in events:
        subject = event_data.get("subject", "")
        event_type = event_data.get("eventType", "")
        blob_url = event_data.get("data", {}).get("url", "")

        logging.info("Event type : %s", event_type)
        logging.info("Subject    : %s", subject)
        logging.info("Blob URL   : %s", blob_url)

    # TODO: add your processing logic here
