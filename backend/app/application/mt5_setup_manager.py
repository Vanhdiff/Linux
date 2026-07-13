from __future__ import annotations

from typing import Any

from app.application.mt5_ea_installer import Mt5EAInstallerService
from app.application.mt5_protection import (
    DEFAULT_MT5_BACKEND_BASE_URL,
    EAStatus,
    EACommunicationLayer,
)


class Mt5EASetupRepairService:
    """Coordinates the backend side of EA setup and repair."""

    def __init__(
        self,
        *,
        ea_layer: EACommunicationLayer | None = None,
        installer: Mt5EAInstallerService | None = None,
    ) -> None:
        self._ea_layer = ea_layer or EACommunicationLayer()
        self._installer = installer or Mt5EAInstallerService()

    def repair(
        self,
        *,
        account_id: int | None = None,
        terminal_id: str | None = None,
        backend_base_url: str | None = None,
        compile_after_install: bool = True,
    ) -> dict[str, Any]:
        config = self._ea_layer.write_ea_config(
            account_id=account_id,
            backend_base_url=backend_base_url or DEFAULT_MT5_BACKEND_BASE_URL,
        )
        install_result = self._installer.install(
            terminal_id=terminal_id,
            compile_after_install=compile_after_install,
        )
        command = self._ea_layer.queue_ea_command(
            command_type="reload_config",
            account_id=account_id,
            payload={"source": "mt5_setup_repair"},
        )
        installer_status = self._installer_status_snapshot(install_result)
        ea_status = self._ea_layer.read_ea_status()
        diagnostics = self._ea_layer.diagnostics(account_id=account_id)
        installed = bool(install_result.get("installed"))
        compiled = bool(install_result.get("compiled")) if compile_after_install else True
        setup_state = self.build_setup_state(
            installer_status=installer_status,
            ea_status=ea_status,
            diagnostics=diagnostics,
        )

        return {
            "repaired": installed and compiled,
            "account_id": account_id,
            "config": config,
            "install": install_result,
            "installer": installer_status,
            "command": command,
            "ea": {
                "connected": ea_status.connected,
                "stale": ea_status.stale,
                "last_heartbeat": ea_status.last_heartbeat.isoformat()
                if ea_status.last_heartbeat
                else None,
                "version": ea_status.version,
                "account_id": ea_status.account_id,
                "error": ea_status.error,
            },
            "diagnostics": diagnostics,
            "setup_state": setup_state,
            "next_actions": self._next_actions(
                setup_state=setup_state,
            ),
        }

    def build_setup_state(
        self,
        *,
        installer_status: dict[str, Any],
        ea_status: EAStatus,
        diagnostics: dict[str, Any],
        protection_level: str | None = None,
        backend_blocker_running: bool | None = None,
    ) -> dict[str, Any]:
        terminal_count = int(installer_status.get("terminal_count", 0) or 0)
        installed_count = int(installer_status.get("installed_count", 0) or 0)
        compiled_count = int(installer_status.get("compiled_count", 0) or 0)
        source_exists = bool(installer_status.get("source_exists"))
        metaeditor_exists = bool(installer_status.get("metaeditor_exists"))
        config_written = bool(diagnostics.get("config_file_exists"))
        command_queued = bool(diagnostics.get("command_file_exists"))
        status_file_exists = bool(diagnostics.get("status_file_exists"))
        heartbeat_ok = ea_status.connected and not ea_status.stale
        protection_full = (protection_level or "").upper() == "FULL"

        if terminal_count == 0:
            return self._state(
                code="open_mt5",
                headline="Open MT5 to start setup",
                detail="TradingDesk cannot see any MetaTrader 5 terminal yet.",
                primary_action="Open MT5",
                can_run_one_click=False,
                blocking_issue=True,
            )
        if not source_exists:
            return self._state(
                code="missing_ea_source",
                headline="EA package is missing",
                detail="TradingDeskGuardEA.mq5 is not available in the app package.",
                primary_action="Restore EA package",
                can_run_one_click=False,
                blocking_issue=True,
            )
        if installed_count == 0:
            return self._state(
                code="install_required",
                headline="Install EA into MT5",
                detail="One-click setup needs to copy TradingDeskGuardEA into MT5 Experts.",
                primary_action="Run one-click setup",
                can_run_one_click=True,
                blocking_issue=False,
            )
        if compiled_count == 0:
            detail = (
                "One-click setup can compile TradingDeskGuardEA in MetaEditor."
                if metaeditor_exists
                else "MetaEditor was not detected. Install the full MT5 desktop package, then compile the EA."
            )
            return self._state(
                code="compile_required",
                headline="Compile EA before protection can start",
                detail=detail,
                primary_action="Run one-click setup" if metaeditor_exists else "Install MetaEditor",
                can_run_one_click=metaeditor_exists,
                blocking_issue=not metaeditor_exists,
            )
        if not config_written or not command_queued:
            return self._state(
                code="config_required",
                headline="Write runtime config for EA",
                detail="One-click setup needs to write ea_config.json and queue a reload command.",
                primary_action="Run one-click setup",
                can_run_one_click=True,
                blocking_issue=False,
            )
        if not status_file_exists:
            return self._state(
                code="attach_ea",
                headline="Attach EA to one MT5 chart",
                detail="The EA has not written ea_status.json yet. Drag TradingDeskGuardEA onto a chart.",
                primary_action="Attach EA in MT5",
                can_run_one_click=False,
                blocking_issue=False,
            )
        if not heartbeat_ok:
            return self._state(
                code="heartbeat_pending",
                headline="Enable Algo Trading and wait for heartbeat",
                detail="The EA status file exists, but the backend is not receiving a fresh heartbeat yet.",
                primary_action="Enable Algo Trading",
                can_run_one_click=False,
                blocking_issue=False,
            )
        if backend_blocker_running is False:
            return self._state(
                code="backend_waiting",
                headline="Start backend protection loop",
                detail="EA heartbeat is live, but the backend enforcement loop is not running yet.",
                primary_action="Refresh backend",
                can_run_one_click=False,
                blocking_issue=False,
            )
        if not protection_full:
            return self._state(
                code="protection_syncing",
                headline="Protection is connecting",
                detail="Heartbeat is live. TradingDesk is finishing protection verification.",
                primary_action="Refresh status",
                can_run_one_click=False,
                blocking_issue=False,
            )
        return self._state(
            code="ready",
            headline="Protection is connected",
            detail="MT5, EA heartbeat, and backend protection are all ready.",
            primary_action="Ready",
            can_run_one_click=False,
            blocking_issue=False,
            ready=True,
        )

    def _next_actions(
        self,
        *,
        setup_state: dict[str, Any],
    ) -> list[str]:
        actions_map = {
            "open_mt5": ["Open MetaTrader 5 so TradingDesk can detect the terminal."],
            "missing_ea_source": ["Restore TradingDeskGuardEA.mq5 in the app package."],
            "install_required": ["Run one-click setup to copy the EA into MT5 Experts."],
            "compile_required": ["Run one-click setup to compile TradingDeskGuardEA in MetaEditor."],
            "config_required": ["Run one-click setup to write ea_config.json and queue reload_config."],
            "attach_ea": ["Attach TradingDeskGuardEA to one MT5 chart."],
            "heartbeat_pending": ["Enable Algo Trading in MT5 and wait for a fresh EA heartbeat."],
            "backend_waiting": ["Keep the TradingDesk backend process running until protection reconnects."],
            "protection_syncing": ["Refresh after TradingDesk finishes protection verification."],
            "ready": ["Confirm protection status shows FULL before live use."],
        }
        return actions_map.get(setup_state.get("code"), ["Review MT5 setup diagnostics."])

    def _installer_status_snapshot(
        self,
        install_result: dict[str, Any],
    ) -> dict[str, Any]:
        status_fn = getattr(self._installer, "status", None)
        if callable(status_fn):
            status = status_fn()
            if isinstance(status, dict):
                return status
        installed = bool(install_result.get("installed"))
        compiled = bool(install_result.get("compiled"))
        verified = bool(install_result.get("verified"))
        terminal_id = install_result.get("terminal_id")
        return {
            "terminal_count": 1 if terminal_id else 0,
            "installed_count": 1 if installed else 0,
            "compiled_count": 1 if compiled and verified else 0,
            "source_exists": True,
            "metaeditor_exists": compiled or verified,
            "targets": [],
        }

    def _state(
        self,
        *,
        code: str,
        headline: str,
        detail: str,
        primary_action: str,
        can_run_one_click: bool,
        blocking_issue: bool,
        ready: bool = False,
    ) -> dict[str, Any]:
        return {
            "code": code,
            "headline": headline,
            "detail": detail,
            "primary_action": primary_action,
            "can_run_one_click": can_run_one_click,
            "blocking_issue": blocking_issue,
            "ready": ready,
        }
