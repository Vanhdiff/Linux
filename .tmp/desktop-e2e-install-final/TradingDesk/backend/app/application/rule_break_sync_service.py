"""
Rule Break Sync Service.

Persists and resolves RuleBreak rows from guardrail check payloads.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Callable

from app.models import RuleBreak


class RuleBreakSyncService:
    """Synchronizes open rule break records with current rule checks."""

    def __init__(
        self,
        db_session: Any,
        *,
        open_rule_breaks: Callable[[int], list[RuleBreak]],
    ) -> None:
        self._db = db_session
        self._open_rule_breaks = open_rule_breaks

    def sync_rule_breaks(self, account_id: int, checks: list[dict]) -> None:
        existing = {
            rule_break.rule_code: rule_break
            for rule_break in self._open_rule_breaks(account_id)
        }
        now = datetime.utcnow()

        for check in checks:
            current = existing.get(check["rule_code"])
            if check["triggered"]:
                if current is None:
                    self._db.add(
                        RuleBreak(
                            account_id=account_id,
                            trade_id=None,
                            rule_code=check["rule_code"],
                            severity=check["severity"],
                            message=check["message"],
                            detected_at=now,
                            payload=check["payload"],
                        )
                    )
                else:
                    current.severity = check["severity"]
                    current.message = check["message"]
                    current.payload = check["payload"]
            elif current is not None:
                current.resolved_at = now

        self._db.commit()
