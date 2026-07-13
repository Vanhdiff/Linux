"""Smoke tests for MT5 EA setup/repair manager.

Run directly:
    installer\python-runtime\python.exe backend\tests\test_mt5_setup_manager_smoke.py
"""
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.application.mt5_protection import EACommunicationLayer
from app.application.mt5_setup_manager import Mt5EASetupRepairService


class FakeInstaller:
    def install(self, *, terminal_id=None, compile_after_install=True):
        return {
            "installed": True,
            "compiled": compile_after_install,
            "verified": compile_after_install,
            "terminal_id": terminal_id,
            "compile_after_install": compile_after_install,
        }

    def status(self):
        return {
            "terminal_count": 1,
            "installed_count": 1,
            "compiled_count": 1,
            "source_exists": True,
            "metaeditor_exists": True,
            "targets": [],
        }


class FailingInstaller:
    def install(self, *, terminal_id=None, compile_after_install=True):
        return {
            "installed": False,
            "compiled": False,
            "verified": False,
            "error": "No MT5 terminal target found.",
        }

    def status(self):
        return {
            "terminal_count": 1,
            "installed_count": 0,
            "compiled_count": 0,
            "source_exists": True,
            "metaeditor_exists": True,
            "targets": [],
        }


def test_repair_writes_config_and_queues_reload_command() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        layer = EACommunicationLayer(data_dir=Path(tmp))
        service = Mt5EASetupRepairService(
            ea_layer=layer,
            installer=FakeInstaller(),
        )

        result = service.repair(
            account_id=7,
            terminal_id="TERM1",
            backend_base_url="http://127.0.0.1:8765",
        )

        assert result["repaired"] is True
        assert result["config"]["account_id"] == 7
        assert result["config"]["backend_base_url"] == "http://127.0.0.1:8765"
        assert result["install"]["terminal_id"] == "TERM1"
        assert result["command"]["command_type"] == "reload_config"
        assert result["command"]["account_id"] == 7
        assert result["setup_state"]["code"] == "attach_ea"
        assert result["setup_state"]["can_run_one_click"] is False
        assert result["diagnostics"]["config_file_exists"] is True
        assert result["diagnostics"]["command_file_exists"] is True
        assert "Attach TradingDeskGuardEA" in result["next_actions"][0]


def test_repair_reports_install_failure_without_hiding_next_action() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        layer = EACommunicationLayer(data_dir=Path(tmp))
        service = Mt5EASetupRepairService(
            ea_layer=layer,
            installer=FailingInstaller(),
        )

        result = service.repair(account_id=7)

        assert result["repaired"] is False
        assert result["install"]["installed"] is False
        assert result["command"]["command_type"] == "reload_config"
        assert result["setup_state"]["code"] == "install_required"
        assert any("copy the EA" in action for action in result["next_actions"])


if __name__ == "__main__":
    test_repair_writes_config_and_queues_reload_command()
    test_repair_reports_install_failure_without_hiding_next_action()
    print("test_mt5_setup_manager_smoke: PASS")
