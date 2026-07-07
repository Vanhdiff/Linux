import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api import (
    accounts,
    ai,
    analytics,
    dashboard,
    guardrails,
    health,
    ingestion,
    journal,
    journals,
    license as license_api,
    mt5,
    news,
    notebook,
    system,
    trades,
)
from app.config import settings
from app.database import SessionLocal, init_db
from app.services.mt5_trade_blocker import Mt5TradeBlocker

LICENSE_EXEMPT_PATHS = {
    "/health",
    "/docs",
    "/openapi.json",
    "/redoc",
    f"{settings.api_prefix}/license",
    f"{settings.api_prefix}/license/session",
    f"{settings.api_prefix}/system/shutdown",
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()

    # Phase 1A: Recover block state from database on startup
    _restore_block_state()

    # Phase 1A: Start scheduler for expired block cleanup
    scheduler_task = asyncio.create_task(_run_block_scheduler())

    app.state.mt5_trade_blocker = None
    app.state.mt5_trade_blocker_task = None
    with SessionLocal() as db:
        if license_api.is_license_active(db):
            blocker = Mt5TradeBlocker(poll_seconds=0.10)
            app.state.mt5_trade_blocker = blocker
            app.state.mt5_trade_blocker_task = asyncio.create_task(
                blocker.run_forever()
            )
    try:
        yield
    finally:
        scheduler_task.cancel()
        with suppress(asyncio.CancelledError):
            await scheduler_task
        task = getattr(app.state, "mt5_trade_blocker_task", None)
        if task is not None:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task


def _restore_block_state():
    """
    Restore block state from database on startup.

    This ensures that any blocks that were active before restart
    are properly restored and enforced.
    """
    import logging
    from app.infrastructure.persistence.block_repository import BlockRepository

    logger = logging.getLogger(__name__)

    with SessionLocal() as db:
        repo = BlockRepository(db)
        cleaned_blocks = repo.cleanup_expired_blocks()
        active_blocks = repo.restore_active_blocks()

        if cleaned_blocks:
            logger.info(
                f"Block state recovery: {len(cleaned_blocks)} expired blocks cleaned up"
            )

        if active_blocks:
            logger.info(
                f"Block state recovery: {len(active_blocks)} active blocks restored"
            )
            for block in active_blocks:
                logger.info(
                    f"  - Account {block.account_id}: "
                    f"{block.block_type.value} block "
                    f"(expires: {block.expires_at})"
                )
        else:
            logger.info("Block state recovery: No active blocks to restore")


async def _run_block_scheduler():
    """
    Background scheduler for block-related periodic tasks.

    Runs every 60 seconds to:
    - Check and resolve expired blocks
    - Prepare for next trading day
    """
    import logging
    import asyncio
    from app.infrastructure.persistence.block_repository import BlockRepository

    logger = logging.getLogger(__name__)
    check_interval = 60  # Check every 60 seconds

    logger.info("Block scheduler started")

    while True:
        try:
            with SessionLocal() as db:
                repo = BlockRepository(db)

                # Check for expired blocks
                expired_blocks = repo.cleanup_expired_blocks()
                if expired_blocks:
                    logger.info(f"Found {len(expired_blocks)} expired blocks to resolve")

                # Log current active block count
                active_count = repo.count_active_blocks()
                if active_count > 0:
                    logger.debug(f"Active blocks: {active_count}")

        except Exception as e:
            logger.error(f"Block scheduler error: {e}")

        await asyncio.sleep(check_interval)


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def enforce_license(request: Request, call_next):
        path = request.url.path.rstrip("/") or "/"
        if request.method == "OPTIONS" or path in LICENSE_EXEMPT_PATHS:
            return await call_next(request)

        db = SessionLocal()
        try:
            if not license_api.is_license_active(db):
                return JSONResponse(
                    status_code=status.HTTP_403_FORBIDDEN,
                    content={"detail": "License activation required"},
                )
        finally:
            db.close()

        return await call_next(request)

    app.include_router(health.router)
    app.include_router(ai.router)
    app.include_router(ingestion.router)
    app.include_router(news.ingest_router)
    app.include_router(analytics.router)
    app.include_router(dashboard.router)
    app.include_router(guardrails.router)
    app.include_router(journal.router)
    app.include_router(news.router)
    app.include_router(notebook.router)
    app.include_router(trades.router)
    app.include_router(accounts.router, prefix=settings.api_prefix)
    from app.api import license as license_api

    app.include_router(license_api.router, prefix=settings.api_prefix)
    app.include_router(system.router, prefix=settings.api_prefix)
    app.include_router(mt5.router, prefix=settings.api_prefix)
    app.include_router(ai.router, prefix=settings.api_prefix)
    app.include_router(trades.router, prefix=settings.api_prefix)
    app.include_router(journals.router, prefix=settings.api_prefix)
    app.include_router(analytics.router, prefix=settings.api_prefix)
    app.include_router(dashboard.router, prefix=settings.api_prefix)
    app.include_router(guardrails.router, prefix=settings.api_prefix)
    app.include_router(journal.router, prefix=settings.api_prefix)
    app.include_router(news.router, prefix=settings.api_prefix)
    app.include_router(notebook.router, prefix=settings.api_prefix)

    return app


app = create_app()
