"""
Guardrail Block Pipeline.

Application-layer bridge for the live GuardrailService flow:
RuleEngine -> BlockDecisionEngine -> BlockExecutor.

This keeps GuardrailService focused on collecting database data and shaping API
responses while the application layer coordinates block decisions and execution.
"""
from __future__ import annotations

from datetime import date
from typing import Any

from fastapi import HTTPException

from app.application.block_decision_engine import BlockDecisionEngine
from app.application.block_executor import BlockExecutor
from app.domain.services.rule_engine import (
    RuleEngine,
    RuleEvaluationInput,
    RuleEvaluationResult,
)


class GuardrailBlockPipeline:
    """Coordinates guardrail rule evaluation and block execution."""

    def __init__(self, db_session: Any) -> None:
        self._rule_engine = RuleEngine()
        self._decision_engine = BlockDecisionEngine(db_session)
        self._block_executor = BlockExecutor(db_session)

    def settings_for_rule_engine(self, settings: Any) -> dict:
        nested = dict(settings.settings or {})
        return {
            **nested,
            "settings": nested,
            "max_daily_loss": settings.max_daily_loss,
            "max_trades_per_day": settings.max_trades_per_day,
            "max_risk_per_trade": settings.max_risk_per_trade,
            "block_high_impact_news": settings.block_high_impact_news,
            "enabled": settings.enabled,
        }

    def evaluate_rules(
        self,
        *,
        input_data: RuleEvaluationInput,
        compatibility_checks: list[dict],
    ) -> list[dict]:
        """Evaluate rules through RuleEngine and overlay mature DB-backed checks.

        The overlay keeps the current API behavior stable while DB-dependent
        checks are gradually moved into pure domain inputs.
        """
        engine_result = self._rule_engine.evaluate(input_data)
        by_code = {check["rule_code"]: check for check in engine_result.checks}
        for check in compatibility_checks:
            by_code[check["rule_code"]] = check
        return list(by_code.values())

    def apply_block_decision(
        self,
        *,
        account_id: int,
        target_date: date,
        trade_block_reasons: list[dict],
        trade_blocking_enabled: bool,
    ) -> dict[str, Any]:
        """Run decision and executor, then return current block state."""
        if not trade_blocking_enabled:
            return {
                "active": False,
                "block_type": None,
                "remaining_seconds": 0,
            }

        result = RuleEvaluationResult(
            account_id=account_id,
            target_date=target_date,
            checks=trade_block_reasons,
            triggered_count=len(trade_block_reasons),
            critical_count=len(
                [item for item in trade_block_reasons if item.get("severity") == "critical"]
            ),
            warning_count=len(
                [item for item in trade_block_reasons if item.get("severity") == "warning"]
            ),
        )
        decision = self._decision_engine.decide(
            result,
            trade_blocking_enabled=trade_blocking_enabled,
        )
        execution = self._block_executor.execute(decision)
        if not execution.success:
            raise HTTPException(
                status_code=500,
                detail=f"Block execution failed: {execution.error}",
            )
        return self._decision_engine.get_block_state(account_id)
