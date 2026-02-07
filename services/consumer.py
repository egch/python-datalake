# app/queue_listener.py
"""
Azure Storage Queue listener using:
  - ACCOUNT_NAME from .env -> ADLS_ACCOUNT
  - ACCESS KEY from .env  -> ADLS_ACCOUNT_KEY

.env example:
  ADLS_ACCOUNT=myaccount
  ADLS_ACCOUNT_KEY=xxxxxxxxxxxxxxxx
  AZURE_QUEUE_NAME=my-queue
"""

from __future__ import annotations

import os
import asyncio
import contextlib
from typing import Optional

from azure.storage.queue import QueueClient


# ==========================
# CONFIGURATION (FROM .env)
# ==========================

ACCOUNT_NAME = os.getenv("ADLS_ACCOUNT")
if not ACCOUNT_NAME:
    raise RuntimeError("Missing env var: ADLS_ACCOUNT")

ACCESS_KEY = os.getenv("ADLS_ACCOUNT_KEY")
if not ACCESS_KEY:
    raise RuntimeError("Missing env var: ADLS_ACCOUNT_KEY")

QUEUE_NAME = os.getenv("AZURE_QUEUE_NAME", "datalake-queue")

VISIBILITY_TIMEOUT = int(os.getenv("QUEUE_VISIBILITY_TIMEOUT", "60"))
MAX_MESSAGES = int(os.getenv("QUEUE_MAX_MESSAGES", "8"))
WAIT_TIME = int(os.getenv("QUEUE_WAIT_TIME", "15"))
POISON_THRESHOLD = int(os.getenv("QUEUE_POISON_THRESHOLD", "5"))
IDLE_SLEEP = float(os.getenv("QUEUE_IDLE_SLEEP", "1.0"))


# ==========================
# BUSINESS LOGIC
# ==========================

async def handle_message(payload: str) -> None:
    """
    Your queue message handler.
    Raise an exception to retry the message.
    """
    print("Processing message:", payload)
    # TODO: your real logic here


# ==========================
# QUEUE LISTENER
# ==========================

class AzureQueueListener:
    def __init__(self):
        self.queue = QueueClient(
            account_url=f"https://{ACCOUNT_NAME}.queue.core.windows.net",
            queue_name=QUEUE_NAME,
            credential=ACCESS_KEY,
        )
        self._stop_event = asyncio.Event()
        self._task: Optional[asyncio.Task] = None

    async def start(self):
        if self._task:
            return
        self._task = asyncio.create_task(self._run(), name="azure-queue-listener")

    async def stop(self):
        self._stop_event.set()
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task

    async def _run(self):
        backoff = 1.0
        while not self._stop_event.is_set():
            try:
                got_any = await self._poll()
                backoff = 1.0
                if not got_any:
                    await asyncio.sleep(IDLE_SLEEP)
            except Exception as e:
                print("[queue] listener error:", e)
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 30.0)

    async def _poll(self) -> bool:
        print(f"[queue] polling {ACCOUNT_NAME}/{QUEUE_NAME} ...")
        messages = await asyncio.to_thread(
            self.queue.receive_messages,
            messages_per_page=MAX_MESSAGES,
            visibility_timeout=VISIBILITY_TIMEOUT,
            timeout=WAIT_TIME,
        )

        received_any = False

        for page in messages.by_page():
            batch = await asyncio.to_thread(list, page)
            if not batch:
                continue

            received_any = True
            for msg in batch:
                try:
                    if msg.dequeue_count >= POISON_THRESHOLD:
                        print("[queue] poison message:", msg.content)
                        await asyncio.to_thread(self.queue.delete_message, msg)
                        continue

                    await handle_message(msg.content)
                    await asyncio.to_thread(self.queue.delete_message, msg)

                except Exception as e:
                    print("[queue] processing failed:", e)
                    # message will reappear after visibility timeout

        return received_any


# ==========================
# FASTAPI INTEGRATION
# ==========================
#
# from contextlib import asynccontextmanager
# from fastapi import FastAPI
# from app.queue_listener import AzureQueueListener
#
# @asynccontextmanager
# async def lifespan(app: FastAPI):
#     listener = AzureQueueListener()
#     await listener.start()
#     try:
#         yield
#     finally:
#         await listener.stop()
#
# app = FastAPI(lifespan=lifespan)
#
# IMPORTANT:
#   Run uvicorn with ONE worker:
#     uvicorn app.main:app --workers 1
#
