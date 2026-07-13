"""Smoke tests for MT5 EA installer helper.

Run directly:
    installer\python-runtime\python.exe backend\tests\test_mt5_ea_installer_smoke.py
"""
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / "backend" / ".deps"), str(ROOT / "backend")]

from app.application.mt5_ea_installer import (
    COMPILE_LOG_FILENAME,
    EA_COMPILED_FILENAME,
    EA_FILENAME,
    METAEDITOR_FALLBACK_LOG_FILENAME,
    Mt5EAInstallerService,
)


class FakeCompilingInstaller(Mt5EAInstallerService):
    def _resolve_metaeditor_path(self):
        fake = self._appdata_dir / "MetaEditor64.exe"
        fake.write_text("fake compiler", encoding="utf-8")
        return fake

    def _compile_target(self, target, metaeditor_path):
        target.ex5_path.write_text("compiled", encoding="utf-8")
        log_path = target.terminal_dir / "MQL5" / "Logs" / COMPILE_LOG_FILENAME
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("Result: 0 errors, 0 warnings, 12 ms elapsed", encoding="utf-8")
        return {
            **self._refresh_target(target).to_dict(),
            "compiled": True,
            "verified": True,
            "return_code": 0,
            "errors": 0,
            "warnings": 0,
            "compile_log_path": str(log_path),
            "compile_log_tail": ["Result: 0 errors, 0 warnings, 12 ms elapsed"],
            "stdout": "",
            "stderr": "",
        }


def make_fake_terminal(root: Path, terminal_id: str = "ABC123") -> Path:
    experts = root / "Terminal" / terminal_id / "MQL5" / "Experts"
    experts.mkdir(parents=True)
    return experts


def test_installer_detects_mt5_terminal_target() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        metaquotes = Path(tmp) / "MetaQuotes"
        experts = make_fake_terminal(metaquotes)
        service = Mt5EAInstallerService(appdata_dir=metaquotes)

        status = service.status()

        assert status["terminal_count"] == 1
        assert status["installed_count"] == 0
        assert status["compiled_count"] == 0
        assert status["targets"][0]["terminal_id"] == "ABC123"
        assert status["targets"][0]["experts_dir"] == str(experts)
        assert status["targets"][0]["installed"] is False
        assert status["targets"][0]["compiled"] is False
        assert "Enable Algo Trading in MT5." in status["manual_steps"]


def test_installer_copies_compiles_and_verifies_selected_terminal() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        metaquotes = base / "MetaQuotes"
        source = base / EA_FILENAME
        source.write_text("// test ea", encoding="utf-8")
        experts = make_fake_terminal(metaquotes, terminal_id="TERM1")
        make_fake_terminal(metaquotes, terminal_id="TERM2")
        service = FakeCompilingInstaller(
            appdata_dir=metaquotes,
            source_ea_path=source,
        )

        result = service.install(terminal_id="TERM1")
        installed = experts / EA_FILENAME
        compiled = experts / EA_COMPILED_FILENAME
        status = service.status()

        assert result["installed"] is True
        assert result["compiled"] is True
        assert result["verified"] is True
        assert result["installed_count"] == 1
        assert installed.exists()
        assert compiled.exists()
        assert installed.read_text(encoding="utf-8") == "// test ea"
        assert status["installed_count"] == 1
        assert status["compiled_count"] == 1
        assert result["compile_results"][0]["compiled"] is True
        assert result["compile_results"][0]["verified"] is True
        assert any("compile" in step.lower() for step in result["next_steps"])


def test_installer_can_copy_without_compile() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        metaquotes = base / "MetaQuotes"
        source = base / EA_FILENAME
        source.write_text("// test ea", encoding="utf-8")
        experts = make_fake_terminal(metaquotes, terminal_id="TERM1")
        service = Mt5EAInstallerService(
            appdata_dir=metaquotes,
            source_ea_path=source,
        )

        result = service.install(terminal_id="TERM1", compile_after_install=False)

        assert result["installed"] is True
        assert result["compiled"] is False
        assert result["verified"] is False
        assert (experts / EA_FILENAME).exists()
        assert result["compile_results"] == []


def test_installer_open_experts_folder_dry_run_returns_path() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        metaquotes = Path(tmp) / "MetaQuotes"
        experts = make_fake_terminal(metaquotes, terminal_id="TERM1")
        service = Mt5EAInstallerService(appdata_dir=metaquotes)

        result = service.open_experts_folder(terminal_id="TERM1", dry_run=True)

        assert result["opened"] is False
        assert result["dry_run"] is True
        assert result["path"] == str(experts)
        assert result["target"]["terminal_id"] == "TERM1"


def test_installer_returns_error_when_source_missing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        metaquotes = Path(tmp) / "MetaQuotes"
        make_fake_terminal(metaquotes, terminal_id="TERM1")
        service = Mt5EAInstallerService(
            appdata_dir=metaquotes,
            source_ea_path=Path(tmp) / "missing.mq5",
        )

        result = service.install(terminal_id="TERM1")

        assert result["installed"] is False
        assert "not found" in result["error"]


def test_compile_result_parser_reads_metaeditor_summary() -> None:
    service = Mt5EAInstallerService()

    parsed = service._parse_compile_result("anything\nResult: 0 errors, 1 warnings, 686 ms elapsed")

    assert parsed == {"errors": 0, "warnings": 1}


def test_compile_log_reader_uses_metaeditor_fallback_log() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        service = Mt5EAInstallerService(appdata_dir=base / "MetaQuotes")
        primary = base / COMPILE_LOG_FILENAME
        fallback = base / METAEDITOR_FALLBACK_LOG_FILENAME
        fallback.write_text(
            "Result: 0 errors, 0 warnings, 12 ms elapsed",
            encoding="utf-8",
        )

        log_text = service._read_compile_log_with_fallback(primary, fallback)

        assert "0 errors, 0 warnings" in log_text


if __name__ == "__main__":
    test_installer_detects_mt5_terminal_target()
    test_installer_copies_compiles_and_verifies_selected_terminal()
    test_installer_can_copy_without_compile()
    test_installer_open_experts_folder_dry_run_returns_path()
    test_installer_returns_error_when_source_missing()
    test_compile_result_parser_reads_metaeditor_summary()
    test_compile_log_reader_uses_metaeditor_fallback_log()
    print("test_mt5_ea_installer_smoke: PASS")
