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
        task = getattr(app.state, "mt5_trade_blocker_task", None)
        if task is not None:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task


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
