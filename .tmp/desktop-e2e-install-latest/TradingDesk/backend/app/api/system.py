from __future__ import annotations

import asyncio
import os
import threading
from contextlib import suppress

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request
from sqlalchemy.orm import Session

from app.database import get_db
from app.services.developer_reset_service import DeveloperResetService
from app.services.mt5_trade_blocker import Mt5TradeBlocker


router = APIRouter(prefix="/system", tags=["system"])


def _shutdown_process() -> None:
    threading.Timer(0.25, lambda: os._exit(0)).start()


@router.post("/shutdown")
def shutdown(background_tasks: BackgroundTasks):
    background_tasks.add_task(_shutdown_process)
    return {"status": "shutting_down"}


@router.post("/developer/reset-environment")
async def developer_reset_environment(
    request: Request,
    db: Session = Depends(get_db),
    history_days: int = Query(default=90, ge=1, le=3650),
):
    blocker = getattr(request.app.state, "mt5_trade_blocker", None)
    task = getattr(request.app.state, "mt5_trade_blocker_task", None)
    should_restart = task is not None and not task.done()
    poll_seconds = getattr(blocker, "_poll_seconds", 0.10) if blocker is not None else 0.10

    if should_restart:
        task.cancel()
        with suppress(asyncio.CancelledError):
            await task
        request.app.state.mt5_trade_blocker = None
        request.app.state.mt5_trade_blocker_task = None
    elif blocker is not None:
        blocker.reset_runtime()

    result = DeveloperResetService(db).reset_environment(history_days=history_days)

    restarted = False
    if should_restart:
        next_blocker = Mt5TradeBlocker(poll_seconds=poll_seconds)
        request.app.state.mt5_trade_blocker = next_blocker
        request.app.state.mt5_trade_blocker_task = asyncio.create_task(
            next_blocker.run_forever()
        )
        restarted = True

    return {
        **result,
        "runtime": {
            "blocker_restarted": restarted,
            "history_days": history_days,
        },
    }
