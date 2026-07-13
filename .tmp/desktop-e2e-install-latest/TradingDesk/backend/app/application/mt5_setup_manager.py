from __future__ import annotations

from typing import Any

from app.application.mt5_ea_installer import Mt5EAInstallerService
from app.application.mt5_protection import (
    DEFAULT_MT5_BACKEND_BASE_URL,
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
        ea_status = self._ea_layer.read_ea_status()
        diagnostics = self._ea_layer.diagnostics(account_id=account_id)
        installed = bool(install_result.get("installed"))
        compiled = bool(install_result.get("compiled")) if compile_after_install else True

        return {
            "repaired": installed and compiled,
            "account_id": account_id,
            "config": config,
            "install": install_result,
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
            "next_actions": self._next_actions(
                installed=installed,
                compiled=compiled,
                ea_connected=ea_status.connected,
            ),
        }

    def _next_actions(
        self,
        *,
        installed: bool,
        compiled: bool,
        ea_connected: bool,
    ) -> list[str]:
        actions: list[str] = []
        if not installed:
            actions.append("Install TradingDeskGuardEA into the selected MT5 terminal.")
        if not compiled:
            actions.append("Compile TradingDeskGuardEA in MetaEditor and review compile logs.")
        if not ea_connected:
            actions.append("Attach TradingDeskGuardEA to one MT5 chart and enable Algo Trading.")
        if not actions:
            actions.append("Confirm protection status shows PROTECTED before live use.")
        return actions
