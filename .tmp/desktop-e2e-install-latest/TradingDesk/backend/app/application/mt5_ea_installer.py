"""MT5 EA installer helpers.

Provides safe filesystem-only detection/install for the TradingDesk MT5 EA.
It does not edit MT5 security settings, registry, or terminal config files.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

EA_FILENAME = "TradingDeskGuardEA.mq5"
EA_COMPILED_FILENAME = "TradingDeskGuardEA.ex5"
COMPILE_LOG_FILENAME = "tradingdesk_guard_compile.log"
METAEDITOR_FALLBACK_LOG_FILENAME = "td_compile.log"


@dataclass(frozen=True)
class Mt5TerminalInstallTarget:
    terminal_id: str
    terminal_dir: Path
    experts_dir: Path
    ea_path: Path
    ex5_path: Path
    installed: bool
    compiled: bool

    def to_dict(self) -> dict[str, Any]:
        return {
            "terminal_id": self.terminal_id,
            "terminal_dir": str(self.terminal_dir),
            "experts_dir": str(self.experts_dir),
            "ea_path": str(self.ea_path),
            "ex5_path": str(self.ex5_path),
            "installed": self.installed,
            "compiled": self.compiled,
        }


class Mt5EAInstallerService:
    def __init__(
        self,
        *,
        appdata_dir: Path | None = None,
        source_ea_path: Path | None = None,
        metaeditor_path: Path | None = None,
    ) -> None:
        self._appdata_dir = appdata_dir or self._default_metaquotes_dir()
        self._source_ea_path = source_ea_path or self._default_source_ea_path()
        self._metaeditor_path = metaeditor_path

    def status(self) -> dict[str, Any]:
        targets = self.detect_targets()
        installed_count = sum(1 for target in targets if target.installed)
        compiled_count = sum(1 for target in targets if target.compiled)
        metaeditor_path = self._resolve_metaeditor_path()
        return {
            "source_ea_path": str(self._source_ea_path),
            "source_exists": self._source_ea_path.exists(),
            "metaquotes_dir": str(self._appdata_dir),
            "metaeditor_path": str(metaeditor_path) if metaeditor_path else None,
            "metaeditor_exists": bool(metaeditor_path and metaeditor_path.exists()),
            "terminal_count": len(targets),
            "installed_count": installed_count,
            "compiled_count": compiled_count,
            "targets": [target.to_dict() for target in targets],
            "manual_steps": [
                "Run Install EA to copy, compile, and verify TradingDeskGuardEA.",
                "Attach the EA to one chart in MT5.",
                "Enable Algo Trading in MT5.",
                "Allow WebRequest for http://127.0.0.1:8000 if pre-trade validation is used.",
            ],
        }

    def install(
        self,
        *,
        terminal_id: str | None = None,
        compile_after_install: bool = True,
    ) -> dict[str, Any]:
        if not self._source_ea_path.exists():
            return {
                "installed": False,
                "compiled": False,
                "verified": False,
                "error": f"EA source file not found: {self._source_ea_path}",
                "targets": [],
            }

        targets = self.detect_targets()
        if terminal_id:
            targets = [target for target in targets if target.terminal_id == terminal_id]
        if not targets:
            return {
                "installed": False,
                "compiled": False,
                "verified": False,
                "error": "No MT5 terminal target found.",
                "targets": [],
            }

        installed_targets = []
        compile_results = []
        errors = []
        for target in targets:
            try:
                target.experts_dir.mkdir(parents=True, exist_ok=True)
                shutil.copy2(self._source_ea_path, target.ea_path)
                installed_target = self._refresh_target(target)
                installed_targets.append({**installed_target.to_dict(), "installed": True})
                if compile_after_install:
                    compile_results.append(self.compile(terminal_id=target.terminal_id))
            except Exception as exc:
                errors.append({**target.to_dict(), "error": str(exc)})

        compiled = any(result.get("compiled") for result in compile_results) if compile_after_install else False
        verified = any(result.get("verified") for result in compile_results) if compile_after_install else False
        return {
            "installed": bool(installed_targets) and not errors,
            "compiled": compiled,
            "verified": verified,
            "installed_count": len(installed_targets),
            "targets": installed_targets,
            "compile_results": compile_results,
            "errors": errors,
            "next_steps": [
                "Restart MT5 or refresh Navigator if the EA is not visible.",
                "Review compile_results if MetaEditor did not produce TradingDeskGuardEA.ex5.",
                "Attach TradingDeskGuardEA to a chart.",
                "Enable Algo Trading and confirm EA heartbeat in TradingDesk.",
            ],
        }

    def compile(self, *, terminal_id: str | None = None) -> dict[str, Any]:
        metaeditor_path = self._resolve_metaeditor_path()
        targets = self.detect_targets()
        if terminal_id:
            targets = [target for target in targets if target.terminal_id == terminal_id]

        if not targets:
            return {
                "compiled": False,
                "verified": False,
                "error": "No MT5 terminal target found.",
                "targets": [],
            }

        if metaeditor_path is None or not metaeditor_path.exists():
            return {
                "compiled": False,
                "verified": False,
                "error": "MetaEditor executable not found.",
                "metaeditor_path": None,
                "targets": [target.to_dict() for target in targets],
            }

        results = []
        for target in targets:
            results.append(self._compile_target(target, metaeditor_path))

        return {
            "compiled": all(bool(result.get("compiled")) for result in results),
            "verified": all(bool(result.get("verified")) for result in results),
            "metaeditor_path": str(metaeditor_path),
            "targets": results,
        }

    def open_experts_folder(
        self,
        *,
        terminal_id: str | None = None,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        targets = self.detect_targets()
        if terminal_id:
            targets = [target for target in targets if target.terminal_id == terminal_id]
        if not targets:
            return {
                "opened": False,
                "error": "No MT5 terminal target found.",
                "target": None,
            }

        target = targets[0]
        if not target.experts_dir.exists():
            return {
                "opened": False,
                "error": f"Experts folder not found: {target.experts_dir}",
                "target": target.to_dict(),
            }

        if not dry_run:
            self._open_folder(target.experts_dir)
        return {
            "opened": not dry_run,
            "dry_run": dry_run,
            "target": target.to_dict(),
            "path": str(target.experts_dir),
        }

    def _open_folder(self, path: Path) -> None:
        if sys.platform.startswith("win"):
            os.startfile(str(path))  # type: ignore[attr-defined]
            return
        if sys.platform == "darwin":
            subprocess.Popen(["open", str(path)])
            return
        subprocess.Popen(["xdg-open", str(path)])

    def detect_targets(self) -> list[Mt5TerminalInstallTarget]:
        terminal_root = self._appdata_dir / "Terminal"
        if not terminal_root.exists():
            return []

        targets: list[Mt5TerminalInstallTarget] = []
        for terminal_dir in sorted(terminal_root.iterdir()):
            if not terminal_dir.is_dir():
                continue
            experts_dir = terminal_dir / "MQL5" / "Experts"
            if not experts_dir.exists():
                continue
            ea_path = experts_dir / EA_FILENAME
            ex5_path = experts_dir / EA_COMPILED_FILENAME
            targets.append(
                Mt5TerminalInstallTarget(
                    terminal_id=terminal_dir.name,
                    terminal_dir=terminal_dir,
                    experts_dir=experts_dir,
                    ea_path=ea_path,
                    ex5_path=ex5_path,
                    installed=ea_path.exists(),
                    compiled=ex5_path.exists(),
                )
            )
        return targets

    def _refresh_target(self, target: Mt5TerminalInstallTarget) -> Mt5TerminalInstallTarget:
        return Mt5TerminalInstallTarget(
            terminal_id=target.terminal_id,
            terminal_dir=target.terminal_dir,
            experts_dir=target.experts_dir,
            ea_path=target.ea_path,
            ex5_path=target.ex5_path,
            installed=target.ea_path.exists(),
            compiled=target.ex5_path.exists(),
        )

    def _compile_target(
        self,
        target: Mt5TerminalInstallTarget,
        metaeditor_path: Path,
    ) -> dict[str, Any]:
        if not target.ea_path.exists():
            return {
                **target.to_dict(),
                "compiled": False,
                "verified": False,
                "error": f"EA file not found: {target.ea_path}",
            }

        logs_dir = target.terminal_dir / "MQL5" / "Logs"
        log_path = logs_dir / COMPILE_LOG_FILENAME
        fallback_log_path = logs_dir / METAEDITOR_FALLBACK_LOG_FILENAME
        logs_dir.mkdir(parents=True, exist_ok=True)
        command = [
            str(metaeditor_path),
            f"/compile:{target.ea_path}",
            f"/log:{log_path}",
        ]
        started_mtime = target.ex5_path.stat().st_mtime if target.ex5_path.exists() else None
        try:
            completed = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            return {
                **self._refresh_target(target).to_dict(),
                "compiled": False,
                "verified": target.ex5_path.exists(),
                "return_code": None,
                "errors": None,
                "warnings": None,
                "compile_log_path": str(log_path),
                "compile_log_tail": self._compile_log_tail(
                    self._read_compile_log_with_fallback(log_path, fallback_log_path)
                ),
                "stdout": exc.stdout or "",
                "stderr": exc.stderr or "",
                "error": "MetaEditor compile timed out.",
            }
        except OSError as exc:
            return {
                **self._refresh_target(target).to_dict(),
                "compiled": False,
                "verified": target.ex5_path.exists(),
                "return_code": None,
                "errors": None,
                "warnings": None,
                "compile_log_path": str(log_path),
                "compile_log_tail": self._compile_log_tail(
                    self._read_compile_log_with_fallback(log_path, fallback_log_path)
                ),
                "stdout": "",
                "stderr": "",
                "error": str(exc),
            }
        log_text = self._read_compile_log_with_fallback(log_path, fallback_log_path)
        parsed = self._parse_compile_result(log_text)
        verified = (
            target.ex5_path.exists()
            and (started_mtime is None or target.ex5_path.stat().st_mtime >= started_mtime)
        )
        compiled = completed.returncode == 0 and parsed.get("errors", 1) == 0 and verified
        return {
            **self._refresh_target(target).to_dict(),
            "compiled": compiled,
            "verified": verified,
            "return_code": completed.returncode,
            "errors": parsed.get("errors"),
            "warnings": parsed.get("warnings"),
            "compile_log_path": str(
                log_path if log_path.exists() else fallback_log_path
            ),
            "compile_log_tail": self._compile_log_tail(log_text),
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        }

    def _read_compile_log_with_fallback(
        self,
        log_path: Path,
        fallback_log_path: Path,
    ) -> str:
        primary = self._read_compile_log(log_path)
        if primary.strip():
            return primary
        return self._read_compile_log(fallback_log_path)

    def _read_compile_log(self, log_path: Path) -> str:
        if not log_path.exists():
            return ""
        for encoding in ("utf-16", "utf-8", "cp1252"):
            try:
                return log_path.read_text(encoding=encoding, errors="ignore")
            except UnicodeError:
                continue
        return log_path.read_text(errors="ignore")

    def _parse_compile_result(self, log_text: str) -> dict[str, int | None]:
        for line in reversed(log_text.splitlines()):
            if "Result:" not in line:
                continue
            errors = self._parse_count_before(line, "errors")
            warnings = self._parse_count_before(line, "warnings")
            return {"errors": errors, "warnings": warnings}
        return {"errors": None, "warnings": None}

    def _parse_count_before(self, line: str, marker: str) -> int | None:
        marker_index = line.find(marker)
        if marker_index < 0:
            return None
        before = line[:marker_index].strip().split()
        if not before:
            return None
        try:
            return int(before[-1])
        except ValueError:
            return None

    def _compile_log_tail(self, log_text: str, *, max_lines: int = 20) -> list[str]:
        lines = [line for line in log_text.splitlines() if line.strip()]
        return lines[-max_lines:]

    def _resolve_metaeditor_path(self) -> Path | None:
        if self._metaeditor_path is not None:
            return self._metaeditor_path

        candidates = [
            Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "MetaTrader 5" / "MetaEditor64.exe",
            Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")) / "MetaTrader 5" / "MetaEditor64.exe",
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate
        return None

    def _default_metaquotes_dir(self) -> Path:
        appdata = os.environ.get("APPDATA")
        if appdata:
            return Path(appdata) / "MetaQuotes"
        return Path.home() / "AppData" / "Roaming" / "MetaQuotes"

    def _default_source_ea_path(self) -> Path:
        return Path(__file__).resolve().parents[3] / "mt5" / "Experts" / EA_FILENAME
