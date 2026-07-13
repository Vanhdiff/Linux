"""Smoke tests for MT5 protection status levels.

Run directly:
    installer\python-runtime\python.exe backend\tests\test_protection_status_smoke.py
"""
from datetime import datetime, timezone
from pathlib import Path
import sys
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.services.mt5_trade_blocker import Mt5TradeBlocker


class FakeMt5Service:
    def positions(self):
        return []


def fake_ea(**kwargs):
    return SimpleNamespace(
        connected=kwargs.get("connected", False),
        stale=kwargs.get("stale", False),
        last_heartbeat=kwargs.get("last_heartbeat"),
        version=kwargs.get("version", "0.12"),
        account_id=kwargs.get("account_id", 7),
        error=kwargs.get("error", ""),
    )


def test_status_is_off_when_backend_blocker_is_not_running() -> None:
    blocker = Mt5TradeBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
    blocker.last_result = {"running": False, "accounts": {}}
    blocker._ea_layer = SimpleNamespace(read_ea_status=lambda: fake_ea(connected=True))

    status = blocker.protection_status()

    assert status["level"] == "OFF"
    assert status["reason"] == "backend_blocker_not_running"
    assert "diagnostics" in status
    assert "backend_data_directory" in status["diagnostics"]


def test_status_is_degraded_when_ea_is_stale() -> None:
    blocker = Mt5TradeBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
    blocker.last_result = {"running": True, "accounts": {}}
    blocker._ea_layer = SimpleNamespace(
        read_ea_status=lambda: fake_ea(
            connected=False,
            stale=True,
            error="EA heartbeat is stale",
        )
    )

    status = blocker.protection_status()

    assert status["level"] == "DEGRADED"
    assert status["reason"] == "ea_offline_or_stale"
    assert status["ea"]["stale"] is True


def test_status_is_degraded_when_backend_latency_over_target() -> None:
    heartbeat = datetime.now(timezone.utc)
    blocker = Mt5TradeBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
    blocker.last_result = {
        "running": True,
        "checked_at": heartbeat.isoformat(),
        "accounts": {
            "7": {
                "blocked": True,
                "block_file_sync": {"synced": True},
                "latency": {"total_ms": 650, "target_ms": 500, "within_target": False},
            }
        },
    }
    blocker._ea_layer = SimpleNamespace(
        read_ea_status=lambda: fake_ea(
            connected=True,
            stale=False,
            last_heartbeat=heartbeat,
        )
    )

    status = blocker.protection_status()

    assert status["level"] == "DEGRADED"
    assert status["reason"] == "backend_latency_over_500ms"


def test_status_is_full_when_ea_connected_and_block_file_synced() -> None:
    heartbeat = datetime.now(timezone.utc)
    blocker = Mt5TradeBlocker(mt5_service=FakeMt5Service(), poll_seconds=0.05)
    blocker.last_result = {
        "running": True,
        "checked_at": heartbeat.isoformat(),
        "accounts": {
            "7": {
                "blocked": True,
                "block_file_sync": {"synced": True},
            }
        },
    }
    blocker._ea_layer = SimpleNamespace(
        read_ea_status=lambda: fake_ea(
            connected=True,
            stale=False,
            last_heartbeat=heartbeat,
        )
    )

    status = blocker.protection_status()

    assert status["level"] == "FULL"
    assert status["reason"] == "blocked_and_enforced"
    assert status["ea"]["connected"] is True
    assert status["accounts"]["7"]["blocked"] is True
    assert status["diagnostics"]["block_file_path"]


if __name__ == "__main__":
    test_status_is_off_when_backend_blocker_is_not_running()
    test_status_is_degraded_when_ea_is_stale()
    test_status_is_degraded_when_backend_latency_over_target()
    test_status_is_full_when_ea_connected_and_block_file_synced()
    print("test_protection_status_smoke: PASS")
