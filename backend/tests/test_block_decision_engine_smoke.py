"""Smoke tests for BlockDecisionEngine.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_block_decision_engine_smoke.py
"""
from datetime import date
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.application.block_decision_engine import BlockDecisionEngine
from app.domain.services.rule_engine import RuleEvaluationResult
from app.domain.state_machine.block_state_machine import BlockStateMachine


class FakeBlockRepository:
    def get_active_block(self, account_id):
        return None

    def save(self, block):
        block.id = 1
        return block


def build_engine() -> BlockDecisionEngine:
    engine = BlockDecisionEngine.__new__(BlockDecisionEngine)
    engine._repo = FakeBlockRepository()
    engine._state_machine = BlockStateMachine()
    return engine


def test_warning_severity_blockable_rule_creates_full_day_block() -> None:
    engine = build_engine()
    result = RuleEvaluationResult(
        account_id=1,
        target_date=date(2026, 7, 7),
        checks=[
            {
                "rule_code": "too_many_trades_today",
                "triggered": True,
                "severity": "warning",
                "message": "Max trades reached",
                "payload": {"trade_count": 5, "max_trades_per_day": 5},
            }
        ],
        triggered_count=1,
        critical_count=0,
        warning_count=1,
    )

    decision = engine.decide(result, trade_blocking_enabled=True)

    assert decision.trade_blocked is True
    assert decision.state.value == "FULL_DAY_BLOCK"
    assert decision.reasons[0]["rule_code"] == "too_many_trades_today"


def test_disabled_trade_blocking_allows_trading() -> None:
    engine = build_engine()
    result = RuleEvaluationResult(
        account_id=1,
        target_date=date(2026, 7, 7),
        checks=[
            {
                "rule_code": "too_many_trades_today",
                "triggered": True,
                "severity": "warning",
                "message": "Max trades reached",
                "payload": {},
            }
        ],
        triggered_count=1,
        critical_count=0,
        warning_count=1,
    )

    decision = engine.decide(result, trade_blocking_enabled=False)

    assert decision.trade_blocked is False
    assert decision.block_state is None


if __name__ == "__main__":
    test_warning_severity_blockable_rule_creates_full_day_block()
    test_disabled_trade_blocking_allows_trading()
    print("test_block_decision_engine_smoke: PASS")
