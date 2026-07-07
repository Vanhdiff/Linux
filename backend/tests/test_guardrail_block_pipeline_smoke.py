"""Smoke tests for GuardrailBlockPipeline.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_guardrail_block_pipeline_smoke.py
"""
from pathlib import Path
from types import SimpleNamespace
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.application.guardrail_block_pipeline import GuardrailBlockPipeline


class FakeRuleResult:
    def __init__(self, checks):
        self.checks = checks


class FakeRuleEngine:
    def __init__(self, checks):
        self._checks = checks

    def evaluate(self, input_data):
        return FakeRuleResult(self._checks)


def build_pipeline_with_fake_rule_engine(checks) -> GuardrailBlockPipeline:
    pipeline = GuardrailBlockPipeline.__new__(GuardrailBlockPipeline)
    pipeline._rule_engine = FakeRuleEngine(checks)
    return pipeline


def test_settings_for_rule_engine_preserves_flat_and_nested_settings() -> None:
    pipeline = GuardrailBlockPipeline.__new__(GuardrailBlockPipeline)
    settings = SimpleNamespace(
        settings={
            "trade_blocking_enabled": True,
            "fixed_risk_percent": 0.5,
        },
        max_daily_loss=100.0,
        max_trades_per_day=3,
        max_risk_per_trade=20.0,
        block_high_impact_news=True,
        enabled=True,
    )

    payload = pipeline.settings_for_rule_engine(settings)

    assert payload["trade_blocking_enabled"] is True
    assert payload["fixed_risk_percent"] == 0.5
    assert payload["settings"]["trade_blocking_enabled"] is True
    assert payload["max_daily_loss"] == 100.0
    assert payload["max_trades_per_day"] == 3
    assert payload["max_risk_per_trade"] == 20.0
    assert payload["block_high_impact_news"] is True
    assert payload["enabled"] is True


def test_evaluate_rules_overlays_compatibility_checks_by_rule_code() -> None:
    engine_check = {
        "rule_code": "too_many_trades_today",
        "triggered": False,
        "severity": "info",
        "message": "engine value",
        "payload": {"source": "engine"},
    }
    compatibility_check = {
        "rule_code": "too_many_trades_today",
        "triggered": True,
        "severity": "warning",
        "message": "compatibility value",
        "payload": {"source": "compatibility"},
    }
    pipeline = build_pipeline_with_fake_rule_engine([engine_check])

    checks = pipeline.evaluate_rules(
        input_data=SimpleNamespace(account_id=1),
        compatibility_checks=[compatibility_check],
    )

    assert len(checks) == 1
    assert checks[0]["rule_code"] == "too_many_trades_today"
    assert checks[0]["triggered"] is True
    assert checks[0]["message"] == "compatibility value"
    assert checks[0]["payload"] == {"source": "compatibility"}


def test_evaluate_rules_keeps_engine_only_checks() -> None:
    engine_check = {
        "rule_code": "risk_too_high",
        "triggered": True,
        "severity": "critical",
        "message": "risk exceeded",
        "payload": {},
    }
    pipeline = build_pipeline_with_fake_rule_engine([engine_check])

    checks = pipeline.evaluate_rules(
        input_data=SimpleNamespace(account_id=1),
        compatibility_checks=[],
    )

    assert checks == [engine_check]


if __name__ == "__main__":
    test_settings_for_rule_engine_preserves_flat_and_nested_settings()
    test_evaluate_rules_overlays_compatibility_checks_by_rule_code()
    test_evaluate_rules_keeps_engine_only_checks()
    print("test_guardrail_block_pipeline_smoke: PASS")
