"""Smoke tests for pre-trade validation service flow.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_pre_trade_validation_smoke.py
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [
    str(ROOT / "backend" / ".deps"),
    str(ROOT / "backend"),
    str(ROOT / "backend" / "tests"),
]

from app.schemas.guardrail import PreTradeValidationRequest
from app.schemas.guardrail import PreTradeValidationResponse
from test_guardrail_service_regression_smoke import (
    GuardrailService,
    GuardrailSettingsPatch,
    add_closed_trade,
    build_session,
)


def test_pre_trade_validation_allows_when_clear() -> None:
    session, account_id = build_session("pretrade-clear")
    try:
        service = GuardrailService(session)
        response = service.pre_trade_validate(
            PreTradeValidationRequest(
                account_id=account_id,
                symbol="EURUSD",
                direction="buy",
                volume=0.1,
            )
        )
        parsed = PreTradeValidationResponse(**response)

        assert parsed.allowed is True
        assert parsed.blocked is False
        assert parsed.decision == "ALLOW"
        assert parsed.reason is None
        assert parsed.request["symbol"] == "EURUSD"
    finally:
        session.close()


def test_pre_trade_validation_denies_when_blocked() -> None:
    session, account_id = build_session("pretrade-blocked")
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

        response = service.pre_trade_validate(
            PreTradeValidationRequest(
                account_id=account_id,
                symbol="EURUSD",
                direction="buy",
                volume=0.1,
            )
        )
        parsed = PreTradeValidationResponse(**response)

        assert parsed.allowed is False
        assert parsed.blocked is True
        assert parsed.decision == "DENY"
        assert parsed.reason
        assert parsed.trade_blocking_enabled is True
        assert parsed.block_state["active"] is True
        assert any(reason["rule_code"] == "too_many_trades_today" for reason in parsed.reasons)
    finally:
        session.close()


if __name__ == "__main__":
    test_pre_trade_validation_allows_when_clear()
    test_pre_trade_validation_denies_when_blocked()
    print("test_pre_trade_validation_smoke: PASS")
