from __future__ import annotations

import asyncio
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode


ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / ".tmp" / f"license_backend_start_gate_{os.getpid()}.db"
os.environ["DATABASE_URL"] = f"sqlite:///{DB_PATH.as_posix()}"
os.environ["LICENSE_MODE"] = "offline"
sys.path.insert(0, str(ROOT / "backend"))
sys.path.insert(0, str(ROOT / "backend" / ".deps"))

from app.main import create_app  # noqa: E402


async def asgi_request(app, method: str, path: str, json_body=None, query=None):
    body = b""
    headers = []
    if json_body is not None:
        body = json.dumps(json_body).encode()
        headers.append((b"content-type", b"application/json"))
    if query:
        path = f"{path}?{urlencode(query)}"

    messages = []

    async def receive():
        return {"type": "http.request", "body": body, "more_body": False}

    async def send(message):
        messages.append(message)

    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": method,
        "path": path.split("?", 1)[0],
        "query_string": path.split("?", 1)[1].encode() if "?" in path else b"",
        "headers": headers,
        "client": ("127.0.0.1", 50000),
        "server": ("127.0.0.1", 8000),
        "scheme": "http",
    }
    await app(scope, receive, send)
    status = next(item["status"] for item in messages if item["type"] == "http.response.start")
    response_body = b"".join(
        item.get("body", b"") for item in messages if item["type"] == "http.response.body"
    )
    payload = json.loads(response_body.decode() or "{}")
    return status, payload


async def main():
    app = create_app()
    async with app.router.lifespan_context(app):
        assert getattr(app.state, "mt5_trade_blocker", None) is None
        assert getattr(app.state, "mt5_trade_blocker_task", None) is None

        blocked_status, blocked_payload = await asgi_request(
            app,
            "GET",
            "/api/dashboard/overview",
            query={"account_id": "1"},
        )
        assert blocked_status == 403, blocked_payload
        assert getattr(app.state, "mt5_trade_blocker", None) is None

        license_status, license_payload = await asgi_request(
            app,
            "POST",
            "/api/license",
            json_body={"license_key": "OFFLINE-123456789012"},
        )
        assert license_status == 201, license_payload
        assert license_payload["is_active"] is True, license_payload

        task = getattr(app.state, "mt5_trade_blocker_task", None)
        assert getattr(app.state, "mt5_trade_blocker", None) is not None
        assert task is not None and not task.done()

        clear_status, clear_payload = await asgi_request(
            app,
            "DELETE",
            "/api/license/session",
        )
        assert clear_status == 200, clear_payload
        assert clear_payload["is_active"] is False, clear_payload
        assert getattr(app.state, "mt5_trade_blocker", None) is None
        task_after_clear = getattr(app.state, "mt5_trade_blocker_task", None)
        assert task_after_clear is None

    print("license backend start gate smoke: blocker stays off until license active")


if __name__ == "__main__":
    asyncio.run(main())
