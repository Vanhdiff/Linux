"""Smoke tests for MT5 file-based protection sync.

Run directly without extra dependencies:
    installer\python-runtime\python.exe backend\tests\test_mt5_protection_smoke.py
"""
import os
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.application.mt5_protection import (
    EACommunicationLayer,
    BlockStateSync,
    default_mt5_common_files_dir,
)
from app.domain.entities.block_state import BlockState, BlockType


class FakeRepo:
    def __init__(self, block=None, active_blocks=None):
        self.block = block
        self.active_blocks = active_blocks or ([] if block is None else [block])

    def get_active_block(self, account_id):
        return self.block if self.block and self.block.account_id == account_id else None

    def get_active_blocks(self):
        return self.active_blocks


def make_block(account_id: int = 7) -> BlockState:
    now = datetime.now(timezone.utc)
    return BlockState(
        id=99,
        account_id=account_id,
        block_type=BlockType.FULL_DAY,
        triggered_by=["too_many_trades_today"],
        blocked_at=now,
        expires_at=now + timedelta(hours=1),
        payload={
            "reasons": [
                {
                    "rule_code": "too_many_trades_today",
                    "message": "Max trades reached",
                }
            ]
        },
    )


def read_block_file(data_dir: Path, account_id: int) -> dict:
    path = data_dir / f"block_{account_id}.json"
    assert path.exists()
    return json.loads(path.read_text(encoding="utf-8"))


def test_ea_layer_writes_block_file_payload() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        now = datetime.now(timezone.utc)

        ok = layer.write_block_state(
            account_id=7,
            blocked=True,
            block_type="full_day",
            blocked_at=now,
            expires_at=now + timedelta(minutes=10),
            triggered_by=["too_many_trades_today"],
            reasons=[{"rule_code": "too_many_trades_today"}],
        )
        payload = read_block_file(data_dir, 7)

        assert ok is True
        assert payload["account_id"] == 7
        assert payload["blocked"] is True
        assert payload["block_type"] == "full_day"
        assert payload["remaining_seconds"] > 0
        assert payload["triggered_by"] == ["too_many_trades_today"]
        assert payload["reasons"] == [{"rule_code": "too_many_trades_today"}]
        assert payload["updated_at"]


def test_ea_layer_clear_block_state_writes_unblocked_payload() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)

        ok = layer.clear_block_state(7)
        payload = read_block_file(data_dir, 7)

        assert ok is True
        assert payload["account_id"] == 7
        assert payload["blocked"] is False
        assert payload["block_type"] is None
        assert payload["remaining_seconds"] == 0
        assert payload["triggered_by"] == []
        assert payload["reasons"] == []


def test_default_mt5_common_files_dir_matches_ea_common_files_contract() -> None:
    original_appdata = os.environ.get("APPDATA")
    try:
        os.environ["APPDATA"] = r"C:\Users\Trader\AppData\Roaming"
        expected = Path(r"C:\Users\Trader\AppData\Roaming\MetaQuotes\Terminal\Common\Files")
        assert default_mt5_common_files_dir() == expected
    finally:
        if original_appdata is None:
            os.environ.pop("APPDATA", None)
        else:
            os.environ["APPDATA"] = original_appdata


def test_ea_status_missing_file_is_disconnected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        layer = EACommunicationLayer(data_dir=Path(tmp))

        status = layer.read_ea_status()

        assert status.connected is False
        assert status.stale is False
        assert status.error == "Status file not found"


def test_ea_status_valid_heartbeat_is_connected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        (data_dir / "ea_status.json").write_text(
            json.dumps(
                {
                    "connected": True,
                    "last_heartbeat": datetime.now(timezone.utc).isoformat(),
                    "version": "1.0.0",
                    "account_id": 7,
                }
            ),
            encoding="utf-8",
        )

        status = layer.read_ea_status()

        assert status.connected is True
        assert status.stale is False
        assert status.version == "1.0.0"
        assert status.account_id == 7
        assert status.error == ""


def test_ea_status_stale_heartbeat_is_disconnected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        (data_dir / "ea_status.json").write_text(
            json.dumps(
                {
                    "connected": True,
                    "last_heartbeat": (datetime.now(timezone.utc) - timedelta(minutes=5)).isoformat(),
                    "version": "1.0.0",
                    "account_id": 7,
                }
            ),
            encoding="utf-8",
        )

        status = layer.read_ea_status()

        assert status.connected is False
        assert status.stale is True
        assert status.error == "EA heartbeat is stale"


def test_ea_status_invalid_json_is_disconnected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        (data_dir / "ea_status.json").write_text("{invalid", encoding="utf-8")

        status = layer.read_ea_status()

        assert status.connected is False
        assert status.error


def test_block_state_sync_writes_active_block_to_ea_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        block = make_block(account_id=7)
        sync = BlockStateSync.__new__(BlockStateSync)
        sync._repo = FakeRepo(block=block)
        sync._ea_layer = layer

        result = sync.sync_account(7)
        payload = read_block_file(data_dir, 7)

        assert result["synced"] is True
        assert result["blocked"] is True
        assert result["block_type"] == "full_day"
        assert payload["blocked"] is True
        assert payload["triggered_by"] == ["too_many_trades_today"]
        assert payload["reasons"][0]["rule_code"] == "too_many_trades_today"


def test_ea_status_missing_file_returns_disconnected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        layer = EACommunicationLayer(data_dir=Path(tmp))

        status = layer.read_ea_status()

        assert status.connected is False
        assert status.last_heartbeat is None
        assert status.error == "Status file not found"


def test_ea_status_reads_valid_heartbeat_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        heartbeat = datetime.now(timezone.utc)
        (data_dir / "ea_status.json").write_text(
            json.dumps(
                {
                    "connected": True,
                    "last_heartbeat": heartbeat.isoformat(),
                    "version": "1.0.0",
                    "account_id": 7,
                    "error": "",
                }
            ),
            encoding="utf-8",
        )
        layer = EACommunicationLayer(data_dir=data_dir)

        status = layer.read_ea_status()

        assert status.connected is True
        assert status.last_heartbeat == heartbeat
        assert status.version == "1.0.0"
        assert status.account_id == 7
        assert status.error == ""


def test_ea_diagnostics_report_status_and_block_file_details() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        heartbeat = datetime.now(timezone.utc)
        (data_dir / "ea_status.json").write_text(
            json.dumps(
                {
                    "connected": True,
                    "last_heartbeat": heartbeat.isoformat(),
                    "version": "1.0.0",
                    "account_id": 7,
                    "error": "",
                }
            ),
            encoding="utf-8",
        )
        layer = EACommunicationLayer(data_dir=data_dir)
        layer.clear_block_state(7)

        diagnostics = layer.diagnostics(account_id=7)

        assert diagnostics["backend_data_directory"] == str(data_dir)
        assert diagnostics["expected_ea_data_directory"]
        assert diagnostics["status_file_path"] == str(data_dir / "ea_status.json")
        assert diagnostics["status_file_exists"] is True
        assert diagnostics["status_file_last_modified"]
        assert diagnostics["heartbeat_age_seconds"] is not None
        assert diagnostics["block_file_path"] == str(data_dir / "block_7.json")
        assert diagnostics["block_file_exists"] is True
        assert diagnostics["config_file_path"] == str(data_dir / "ea_config.json")
        assert diagnostics["command_file_path"] == str(data_dir / "ea_command.json")


def test_ea_layer_writes_config_contract_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)

        config = layer.write_ea_config(
            account_id=7,
            backend_base_url="http://127.0.0.1:8765",
            updates={
                "close_positions_when_blocked": False,
                "enforcement_timer_ms": 50,
            },
        )
        saved = json.loads((data_dir / "ea_config.json").read_text(encoding="utf-8"))
        diagnostics = layer.diagnostics(account_id=7)

        assert config["contract_version"] == "td_ea_config.v1"
        assert saved["account_id"] == 7
        assert saved["backend_base_url"] == "http://127.0.0.1:8765"
        assert saved["close_positions_when_blocked"] is False
        assert saved["delete_pending_orders_when_blocked"] is True
        assert saved["enforcement_timer_ms"] == 50
        assert saved["audit_file_name"] == "ea_mt5_demo_audit.jsonl"
        assert diagnostics["config_file_exists"] is True
        assert diagnostics["config_contract_version"] == "td_ea_config.v1"
        assert diagnostics["config_account_id"] == 7


def test_ea_layer_queues_and_clears_command_contract_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)

        command = layer.queue_ea_command(
            command_id="cmd-1",
            command_type="reload_config",
            account_id=7,
            payload={"reason": "test"},
        )
        saved = json.loads((data_dir / "ea_command.json").read_text(encoding="utf-8"))
        diagnostics = layer.diagnostics(account_id=7)

        assert command["command_id"] == "cmd-1"
        assert saved["command_type"] == "reload_config"
        assert saved["account_id"] == 7
        assert saved["payload"] == {"reason": "test"}
        assert saved["status"] == "pending"
        assert diagnostics["command_file_exists"] is True
        assert diagnostics["command_id"] == "cmd-1"
        assert diagnostics["command_type"] == "reload_config"
        assert layer.clear_ea_command() is True
        assert layer.read_ea_command() is None


def test_ea_status_invalid_heartbeat_does_not_crash() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        (data_dir / "ea_status.json").write_text(
            json.dumps(
                {
                    "connected": True,
                    "last_heartbeat": "not-a-date",
                    "version": "1.0.0",
                    "account_id": 7,
                    "error": "",
                }
            ),
            encoding="utf-8",
        )
        layer = EACommunicationLayer(data_dir=data_dir)

        status = layer.read_ea_status()

        assert status.connected is False
        assert status.stale is True
        assert status.last_heartbeat is None
        assert status.version == "1.0.0"
        assert status.account_id == 7
        assert status.error == "EA heartbeat is stale"


def test_block_state_sync_clears_when_no_active_block() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        data_dir = Path(tmp)
        layer = EACommunicationLayer(data_dir=data_dir)
        sync = BlockStateSync.__new__(BlockStateSync)
        sync._repo = FakeRepo(block=None)
        sync._ea_layer = layer

        result = sync.sync_account(7)
        payload = read_block_file(data_dir, 7)

        assert result == {
            "account_id": 7,
            "synced": True,
            "blocked": False,
            "block_type": None,
        }
        assert payload["blocked"] is False


if __name__ == "__main__":
    test_ea_layer_writes_block_file_payload()
    test_ea_layer_clear_block_state_writes_unblocked_payload()
    test_default_mt5_common_files_dir_matches_ea_common_files_contract()
    test_ea_status_missing_file_is_disconnected()
    test_ea_status_valid_heartbeat_is_connected()
    test_ea_status_stale_heartbeat_is_disconnected()
    test_ea_status_invalid_json_is_disconnected()
    test_block_state_sync_writes_active_block_to_ea_file()
    test_ea_status_missing_file_returns_disconnected()
    test_ea_status_reads_valid_heartbeat_file()
    test_ea_diagnostics_report_status_and_block_file_details()
    test_ea_layer_writes_config_contract_file()
    test_ea_layer_queues_and_clears_command_contract_file()
    test_ea_status_invalid_heartbeat_does_not_crash()
    test_block_state_sync_clears_when_no_active_block()
    print("test_mt5_protection_smoke: PASS")
