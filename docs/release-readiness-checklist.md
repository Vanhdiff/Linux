# Release Readiness Checklist

Use this checklist before preparing a commercial desktop build.

## Static Checks

- [ ] Run Flutter analyzer:
  `D:\flutter\bin\flutter.bat analyze`
- [ ] Compile critical backend modules:
  `installer\python-runtime\python.exe -m py_compile backend\app\api\mt5.py backend\app\application\mt5_setup_manager.py backend\app\application\mt5_protection.py backend\app\application\mt5_demo_harness.py`

## Backend Smoke Suite

- [ ] Run every backend smoke/regression test:
  `Get-ChildItem -LiteralPath backend\tests -Filter test_*.py | ForEach-Object { & installer\python-runtime\python.exe $_.FullName }`
- [ ] Confirm every test exits with code 0.
- [ ] Treat expected error logs from negative-path tests as acceptable only when the test process still passes.

## MT5 / EA Verification

- [ ] Run the real MetaEditor compile for `TradingDeskGuardEA.mq5`.
- [ ] Confirm compile result is exactly `0 errors, 0 warnings`.
- [ ] Confirm backend and EA shared filesystem diagnostics match.
- [ ] Confirm `ea_config.json` exists after Repair Setup.
- [ ] Confirm `ea_command.json` is queued after Repair Setup and cleared/processed by the EA.
- [ ] Confirm `ea_status.json` heartbeat refreshes while the EA is attached to a chart.

## Protection FULL Flow

- [ ] Open Guardrails.
- [ ] Click Install / Repair.
- [ ] Attach `TradingDeskGuardEA` to one MT5 chart.
- [ ] Enable Algo Trading.
- [ ] Confirm the Protection FULL verification card passes all setup and heartbeat checks.
- [ ] Trigger a real demo block scenario.
- [ ] Confirm timing audit captures:
  - rule detected
  - block persisted
  - block file written
  - EA transaction received
  - close request sent
  - close confirmed
- [ ] Confirm the app does not claim broker execution under 500ms unless close confirmation is measured.

## Desktop Build Gate

- [ ] Build Windows release:
  `powershell -ExecutionPolicy Bypass -File scripts\build_windows_release.ps1`
- [ ] For online-license builds, use:
  `powershell -ExecutionPolicy Bypass -File scripts\build_windows_online_license.ps1 -AnonKey <public-anon-key>`
- [ ] If Flutter hangs before printing build progress, clear stale Flutter tool locks and rerun with `--no-version-check`.
- [ ] Build installer:
  `powershell -ExecutionPolicy Bypass -File scripts\build_setup.ps1`
- [ ] Confirm installer exists:
  `installer\trading-desk-setup-1.0.0.exe`
- [ ] Launch the packaged app on a clean user profile.
- [ ] Confirm backend process starts from the app.
- [ ] Confirm packaged app smoke endpoints pass after launch:
  - `/health`
  - `/api/dashboard`
  - `/api/guardrails/status`
  - `/api/mt5/ea/setup/report`
- [ ] Confirm package contains `backend\run.py`, `backend\.deps`, `python\python.exe`, and `mt5\Experts\TradingDeskGuardEA.mq5`.
- [ ] Confirm MT5 setup, diagnostics, and demo validation are visible without developer tools.
- [ ] Confirm logs and reports can be copied from the app for support.
