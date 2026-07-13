$ErrorActionPreference = "Stop"

Write-Host "Building Trading Desk Windows release..." -ForegroundColor Cyan

Get-Process -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessName -in @("dart", "dartvm", "dartaotruntime", "flutter") } |
  Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item -LiteralPath "D:\flutter\bin\cache\flutter.bat.lock", "D:\flutter\bin\cache\lockfile" `
  -Force -ErrorAction SilentlyContinue

$env:FLUTTER_SKIP_UPDATE_CHECK = "true"

& "D:\flutter\bin\flutter.bat" --no-version-check build windows --release

Write-Host ""
Write-Host "Built: build\windows\x64\runner\Release\trading_desk.exe" -ForegroundColor Green
