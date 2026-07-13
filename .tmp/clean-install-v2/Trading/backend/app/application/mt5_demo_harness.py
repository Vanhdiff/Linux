from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.application.mt5_protection import EACommunicationLayer


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _ms_between(start: datetime | None, end: datetime | None) -> int | None:
    if start is None or end is None:
        return None
    return int((end - start).total_seconds() * 1000)


@dataclass(frozen=True)
class DemoTimingAudit:
    rule_detected_at: datetime | None = None
    block_persisted_at: datetime | None = None
    block_file_written_at: datetime | None = None
    ea_transaction_received_at: datetime | None = None
    close_request_sent_at: datetime | None = None
    close_confirmed_at: datetime | None = None

    def as_dict(self) -> dict[str, Any]:
        backend_reaction_ms = _ms_between(
            self.rule_detected_at,
            self.block_file_written_at,
        )
        block_persistence_ms = _ms_between(
            self.rule_detected_at,
            self.block_persisted_at,
        )
        ea_close_reaction_ms = _ms_between(
            self.block_file_written_at,
            self.close_request_sent_at,
        )
        broker_execution_ms = _ms_between(
            self.close_request_sent_at,
            self.close_confirmed_at,
        )
        return {
            "timestamps": {
                "rule_detected_at": _iso(self.rule_detected_at),
                "block_persisted_at": _iso(self.block_persisted_at),
                "block_file_written_at": _iso(self.block_file_written_at),
                "ea_transaction_received_at": _iso(self.ea_transaction_received_at),
                "close_request_sent_at": _iso(self.close_request_sent_at),
                "close_confirmed_at": _iso(self.close_confirmed_at),
            },
            "durations_ms": {
                "backend_reaction_ms": backend_reaction_ms,
                "block_persistence_ms": block_persistence_ms,
                "ea_close_reaction_ms": ea_close_reaction_ms,
                "broker_execution_ms": broker_execution_ms,
            },
            "targets": {
                "backend_reaction_target_ms": 500,
                "backend_reaction_within_target": (
                    backend_reaction_ms is not None and backend_reaction_ms <= 500
                ),
            },
            "notes": [
                "Backend reaction target is under 500ms from rule detection to block file write."
            ]
            + (
                []
                if broker_execution_ms is not None
                else [
                    "Broker execution under 500ms is not claimed unless close_request_sent_at and close_confirmed_at are both measured."
                ]
            ),
        }


class Mt5DemoHarnessService:
    def __init__(self, ea_layer: EACommunicationLayer | None = None) -> None:
        self._ea_layer = ea_layer or EACommunicationLayer()

    def report(self, account_id: int, blocker: Any | None = None) -> dict[str, Any]:
        diagnostics = self._ea_layer.diagnostics(account_id=account_id)
        timing = self._timing_audit(account_id)
        return {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "account_id": account_id,
            "checklist": self._checklist(
                account_id=account_id,
                diagnostics=diagnostics,
                timing=timing,
                blocker=blocker,
            ),
            "timing_audit": timing.as_dict(),
            "evidence": {
                "backend_data_directory": diagnostics["backend_data_directory"],
                "expected_ea_data_directory": diagnostics["expected_ea_data_directory"],
                "status_file_path": diagnostics["status_file_path"],
                "block_file_path": diagnostics["block_file_path"],
                "backend_audit_file_path": diagnostics["backend_audit_file_path"],
                "ea_audit_file_path": diagnostics["ea_audit_file_path"],
            },
            "completion": {
                "validation_checklist_created": True,
                "structured_timing_audit_created": True,
                "all_required_timestamp_fields_present": all(
                    value is not None
                    for value in timing.as_dict()["timestamps"].values()
                ),
            },
        }

    def _checklist(
        self,
        *,
        account_id: int,
        diagnostics: dict[str, Any],
        timing: DemoTimingAudit,
        blocker: Any | None,
    ) -> list[dict[str, Any]]:
        blocker_running = bool(getattr(blocker, "last_result", {}).get("running")) if blocker else False
        backend_dir = diagnostics["backend_data_directory"]
        expected_dir = diagnostics["expected_ea_data_directory"]
        ea_status = blocker.get_ea_status() if blocker and hasattr(blocker, "get_ea_status") else self._ea_layer.read_ea_status()
        return [
            {
                "id": "shared_filesystem_aligned",
                "title": "Backend and EA use the same shared filesystem directory",
                "completed": backend_dir == expected_dir,
                "details": {
                    "backend_data_directory": backend_dir,
                    "expected_ea_data_directory": expected_dir,
                },
            },
            {
                "id": "backend_blocker_running",
                "title": "MT5 backend enforcement loop is running",
                "completed": blocker_running,
                "details": {"running": blocker_running},
            },
            {
                "id": "ea_heartbeat_fresh",
                "title": "EA heartbeat is present and fresh",
                "completed": bool(ea_status.connected) and not bool(ea_status.stale),
                "details": {
                    "connected": ea_status.connected,
                    "stale": ea_status.stale,
                    "last_heartbeat": _iso(ea_status.last_heartbeat),
                    "error": ea_status.error,
                },
            },
            {
                "id": "block_file_accessible",
                "title": "Shared block file exists for the account",
                "completed": bool(diagnostics["block_file_exists"]),
                "details": {
                    "account_id": account_id,
                    "block_file_path": diagnostics["block_file_path"],
                    "block_file_exists": diagnostics["block_file_exists"],
                },
            },
            {
                "id": "backend_timing_audit_active",
                "title": "Backend timing audit events are being written",
                "completed": bool(diagnostics["backend_audit_file_exists"]),
                "details": {
                    "backend_audit_file_path": diagnostics["backend_audit_file_path"],
                    "backend_audit_file_exists": diagnostics["backend_audit_file_exists"],
                },
            },
            {
                "id": "ea_timing_audit_active",
                "title": "EA timing audit events are being written",
                "completed": bool(diagnostics["ea_audit_file_exists"]),
                "details": {
                    "ea_audit_file_path": diagnostics["ea_audit_file_path"],
                    "ea_audit_file_exists": diagnostics["ea_audit_file_exists"],
                },
            },
            {
                "id": "required_timestamps_measured",
                "title": "Required demo timestamps have been captured",
                "completed": all(
                    value is not None for value in timing.as_dict()["timestamps"].values()
                ),
                "details": timing.as_dict()["timestamps"],
            },
        ]

    def _timing_audit(self, account_id: int) -> DemoTimingAudit:
        events = self._ea_layer.read_timing_events(account_id=account_id)
        backend_events = sorted(
            events["backend"],
            key=lambda item: item.get("occurred_at") or "",
        )
        ea_events = sorted(
            events["ea"],
            key=lambda item: item.get("occurred_at") or "",
        )

        latest_block_write = self._latest_event(backend_events, "block_file_written")
        block_key = (
            ((latest_block_write or {}).get("metadata") or {}).get("block_key")
            if latest_block_write
            else None
        )
        rule_detected = self._latest_event(
            backend_events,
            "rule_detected",
            block_key=block_key,
        )
        block_persisted = self._latest_event(
            backend_events,
            "block_persisted",
            block_key=block_key,
        )

        block_file_written_at = _parse_dt(
            latest_block_write.get("occurred_at") if latest_block_write else None
        )
        if block_file_written_at is None:
            block_path_value = self._ea_layer.diagnostics(account_id=account_id)["block_file_path"]
            if block_path_value:
                block_path = Path(block_path_value)
                if block_path.exists():
                    block_file_written_at = datetime.fromtimestamp(
                        block_path.stat().st_mtime,
                        tz=timezone.utc,
                    )

        return DemoTimingAudit(
            rule_detected_at=_parse_dt(
                rule_detected.get("occurred_at") if rule_detected else None
            ),
            block_persisted_at=_parse_dt(
                block_persisted.get("occurred_at") if block_persisted else None
            ),
            block_file_written_at=block_file_written_at,
            ea_transaction_received_at=_parse_dt(
                self._first_event_after(
                    ea_events,
                    "ea_transaction_received",
                    block_file_written_at,
                )
            ),
            close_request_sent_at=_parse_dt(
                self._first_event_after(
                    ea_events,
                    "close_request_sent",
                    block_file_written_at,
                )
            ),
            close_confirmed_at=_parse_dt(
                self._first_event_after(
                    ea_events,
                    "close_confirmed",
                    block_file_written_at,
                )
            ),
        )

    def _latest_event(
        self,
        events: list[dict[str, Any]],
        event_type: str,
        *,
        block_key: str | None = None,
    ) -> dict[str, Any] | None:
        filtered = [
            item
            for item in events
            if item.get("event_type") == event_type
            and (
                block_key is None
                or ((item.get("metadata") or {}).get("block_key") == block_key)
            )
        ]
        return filtered[-1] if filtered else None

    def _first_event_after(
        self,
        events: list[dict[str, Any]],
        event_type: str,
        start_at: datetime | None,
    ) -> str | None:
        for item in events:
            if item.get("event_type") != event_type:
                continue
            occurred_at = _parse_dt(item.get("occurred_at"))
            if start_at is None or (occurred_at is not None and occurred_at >= start_at):
                return item.get("occurred_at")
        return None
