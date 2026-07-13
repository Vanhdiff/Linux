"""Regression smoke tests for max trades full-day block behavior.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_max_trades_block_regression_smoke.py
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [
    str(ROOT / "backend" / ".deps"),
    str(ROOT / "backend"),
    str(ROOT / "backend" / "tests"),
]

from app.schemas.guardrail import GuardrailSettingsPatch
from app.services.guardrail_service import GuardrailService
from test_guardrail_service_regression_smoke import add_closed_trade, build_session


def check_by_code(status: dict, rule_code: str) -> dict:
    for check in status["checks"]:
        if check["rule_code"] == rule_code:
            return check
    raise AssertionError(f"Missing check: {rule_code}")


def test_closed_normalized_trade_counts_toward_max_trades_block() -> None:
    session, account_id = build_session("max-trades-normalized-only")
    try:
        service = GuardrailService(session)
        service.patch_settings(
            account_id,
            GuardrailSettingsPatch(
                max_trades_per_day=1,
                settings={"trade_blocking_enabled": True},
            ),
        )
        add_closed_trade(session, account_id)

        status = service.status(account_id)
        check = check_by_code(status, "too_many_trades_today")

        assert check["triggered"] is True
        assert check["payload"]["trade_count"] == 1
        assert status["trade_blocking_enabled"] is True
        assert status["trade_blocked"] is True
        assert status["trade_block"]["blocked"] is True
        assert status["block_state"]["active"] is True
        assert status["block_state"]["block_type"] == "full_day"
    finally:
        session.close()


def test_trade_blocking_disabled_reports_violation_but_does_not_block() -> None:
    session, account_id = build_session("max-trades-disabled")
    try:
        service = GuardrailService(session)
        service.patch_settings(
            account_id,
            GuardrailSettingsPatch(
                max_trades_per_day=1,
                settings={"trade_blocking_enabled": False},
            ),
        )
        add_closed_trade(session, account_id)

        status = service.status(account_id)
        check = check_by_code(status, "too_many_trades_today")

        assert check["triggered"] is True
        assert status["trade_blocking_enabled"] is False
        assert status["trade_blocked"] is False
        assert status["trade_block"]["blocked"] is False
        assert status["trade_block"]["blockable_reason_count"] >= 1
        assert status["trade_block"]["disabled_reason"] == "trade_blocking_disabled"
        assert status["block_state"]["active"] is False
    finally:
        session.close()


if __name__ == "__main__":
    test_closed_normalized_trade_counts_toward_max_trades_block()
    test_trade_blocking_disabled_reports_violation_but_does_not_block()
    print("test_max_trades_block_regression_smoke: PASS")
