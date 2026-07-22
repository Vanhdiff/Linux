"""Smoke tests for MT5 real demo harness reporting.

Run directly:
    installer\python-runtime\python.exe backend\tests\test_mt5_demo_harness_smoke.py
"""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.application.mt5_demo_harness import Mt5DemoHarnessService
from app.application.mt5_protection import EACommunicationLayer


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row) + "\n")


def test_demo_harness_report_contains_required_checklist_and_timing_fields() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        now = datetime.now(timezone.utc)
        layer.clear_block_state(7)
        (data_dir / "ea_status.json").write_text(
            json.dumps(
                {
                    "connected": True,
                    "last_heartbeat": now.isoformat(),
                    "version": "1.0.0",
                    "account_id": 7,
                    "error": "",
                }
            ),
            encoding="utf-8",
        )
        _write_jsonl(
            data_dir / "backend_mt5_demo_audit.jsonl",
            [
                {
                    "source": "backend",
                    "event_type": "rule_detected",
                    "account_id": 7,
                    "occurred_at": now.isoformat(),
                    "metadata": {"block_key": "b1"},
                },
                {
                    "source": "backend",
                    "event_type": "block_persisted",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(milliseconds=50)).isoformat(),
                    "metadata": {"block_key": "b1"},
                },
                {
                    "source": "backend",
                    "event_type": "block_file_written",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(milliseconds=120)).isoformat(),
                    "metadata": {"block_key": "b1"},
                },
            ],
        )
        _write_jsonl(
            data_dir / "ea_mt5_demo_audit.jsonl",
            [
                {
                    "source": "ea",
                    "event_type": "ea_transaction_received",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(milliseconds=150)).isoformat(),
                },
                {
                    "source": "ea",
                    "event_type": "close_request_sent",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(milliseconds=180)).isoformat(),
                },
                {
                    "source": "ea",
                    "event_type": "close_confirmed",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(milliseconds=420)).isoformat(),
                },
            ],
        )
        blocker = SimpleNamespace(
            last_result={"running": True},
            get_ea_status=lambda: SimpleNamespace(
                connected=True,
                stale=False,
                last_heartbeat=now,
                error="",
            ),
        )

        report = Mt5DemoHarnessService(layer).report(account_id=7, blocker=blocker)

        assert report["completion"]["validation_checklist_created"] is True
        assert report["completion"]["structured_timing_audit_created"] is True
        timestamps = report["timing_audit"]["timestamps"]
        assert timestamps["rule_detected_at"] is not None
        assert timestamps["block_persisted_at"] is not None
        assert timestamps["block_file_written_at"] is not None
        assert timestamps["ea_transaction_received_at"] is not None
        assert timestamps["close_request_sent_at"] is not None
        assert timestamps["close_confirmed_at"] is not None
        assert (
            report["timing_audit"]["durations_ms"]["backend_reaction_ms"] == 120
        )
        assert report["timing_audit"]["targets"]["backend_reaction_target_ms"] == 500


def test_demo_harness_does_not_claim_broker_speed_without_measured_close_confirmation() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        now = datetime.now(timezone.utc)
        _write_jsonl(
            data_dir / "backend_mt5_demo_audit.jsonl",
            [
                {
                    "source": "backend",
                    "event_type": "block_file_written",
                    "account_id": 7,
                    "occurred_at": now.isoformat(),
                    "metadata": {"block_key": "b1"},
                }
            ],
        )
        _write_jsonl(
            data_dir / "ea_mt5_demo_audit.jsonl",
            [
                {
                    "source": "ea",
                    "event_type": "close_request_sent",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(milliseconds=40)).isoformat(),
                }
            ],
        )

        report = Mt5DemoHarnessService(layer).report(account_id=7)

        assert report["timing_audit"]["durations_ms"]["broker_execution_ms"] is None
        assert any(
            "Broker execution under 500ms is not claimed" in note
            for note in report["timing_audit"]["notes"]
        )


def test_demo_harness_uses_first_block_file_write_for_same_block_key() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        now = datetime.now(timezone.utc)
        _write_jsonl(
            data_dir / "backend_mt5_demo_audit.jsonl",
            [
                {
                    "source": "backend",
                    "event_type": "rule_detected",
                    "account_id": 7,
                    "occurred_at": now.isoformat(),
                    "metadata": {"block_key": "b1"},
                },
                {
                    "source": "backend",
                    "event_type": "block_persisted",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(milliseconds=40)).isoformat(),
                    "metadata": {"block_key": "b1"},
                },
                {
                    "source": "backend",
                    "event_type": "block_file_written",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(milliseconds=120)).isoformat(),
                    "metadata": {"block_key": "b1"},
                },
                {
                    "source": "backend",
                    "event_type": "block_file_written",
                    "account_id": 7,
                    "occurred_at": (now + timedelta(seconds=150)).isoformat(),
                    "metadata": {"block_key": "b1"},
                },
            ],
        )

        report = Mt5DemoHarnessService(layer).report(account_id=7)

        assert report["timing_audit"]["durations_ms"]["backend_reaction_ms"] == 120


if __name__ == "__main__":
    test_demo_harness_report_contains_required_checklist_and_timing_fields()
    test_demo_harness_does_not_claim_broker_speed_without_measured_close_confirmation()
    test_demo_harness_uses_first_block_file_write_for_same_block_key()
    print("test_mt5_demo_harness_smoke: PASS")
