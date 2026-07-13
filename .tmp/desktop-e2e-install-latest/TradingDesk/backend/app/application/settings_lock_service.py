"""
Settings Lock Service.

Owns guardrail settings locking and pending-update rollover behavior.
Does not evaluate trading rules or build full guardrail status responses.
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Any, Callable


class SettingsLockService:
    """Coordinates same-day settings lock and next-day pending updates."""

    def __init__(self, db_session: Any, today_fn: Callable[[], date]) -> None:
        self._db = db_session
        self._today_fn = today_fn

    def guardrail_lock_payload(
        self,
        trade_blocked: bool,
        trade_count: int,
        settings: Any | None = None,
        target_date: date | None = None,
    ) -> dict:
        effective_today_locked = trade_count > 0 or trade_blocked
        if trade_blocked:
            reason = "blocked_until_next_trading_day"
            message = (
                "Today's rules are locked because a blocking rule was hit. "
                "Any saved changes apply on the next trading day."
            )
        elif trade_count > 0:
            reason = "next_day_pending_only"
            message = (
                "Trades already exist today. Rule edits are saved for the next "
                "trading day."
            )
        else:
            reason = "editable"
            message = "Guardrails are editable for today."
        return {
            "hard_locked": False,
            "tighten_only": effective_today_locked,
            "effective_today_locked": effective_today_locked,
            "trade_count": trade_count,
            "timezone": "Local",
            "reason": reason,
            "message": message,
            "pending_update": self.pending_update_payload(settings, target_date),
        }

    def apply_settings_changes(self, settings: Any, changes: dict) -> None:
        nested_changes = dict(changes.get("settings") or {})
        for key, value in changes.items():
            if key == "settings":
                continue
            setattr(settings, key, value)

        nested = dict(settings.settings or {})
        nested.pop("pending_update", None)
        nested.update(nested_changes)
        settings.settings = nested

    def schedule_settings_for_next_day(
        self,
        settings: Any,
        changes: dict,
        effective_date: date,
    ) -> None:
        nested = dict(settings.settings or {})
        nested["pending_update"] = {
            "effective_date": effective_date.isoformat(),
            "saved_at": datetime.utcnow().isoformat(),
            "changes": changes,
        }
        settings.settings = nested

    def rollover_pending_settings_if_due(self, settings: Any) -> None:
        pending = self.pending_update(settings)
        if pending is None:
            return
        effective_date = self.parse_iso_date(pending.get("effective_date"))
        if effective_date is None or effective_date > self._today_fn():
            return
        changes = pending.get("changes")
        if isinstance(changes, dict):
            self.apply_settings_changes(settings, changes)
        nested = dict(settings.settings or {})
        nested.pop("pending_update", None)
        settings.settings = nested
        self._db.commit()
        self._db.refresh(settings)

    def pending_update(self, settings: Any | None) -> dict | None:
        if settings is None:
            return None
        pending = (settings.settings or {}).get("pending_update")
        return pending if isinstance(pending, dict) else None

    def pending_update_payload(
        self,
        settings: Any | None,
        target_date: date | None = None,
    ) -> dict | None:
        pending = self.pending_update(settings)
        if pending is None:
            return None
        effective_date = self.parse_iso_date(pending.get("effective_date"))
        changes = pending.get("changes")
        return {
            "effective_date": effective_date.isoformat() if effective_date else None,
            "saved_at": pending.get("saved_at"),
            "changes": changes if isinstance(changes, dict) else {},
            "active_for_date": bool(
                effective_date is not None
                and target_date is not None
                and effective_date <= target_date
            ),
        }

    def parse_iso_date(self, value: object) -> date | None:
        if not value:
            return None
        try:
            return date.fromisoformat(str(value))
        except ValueError:
            return None
