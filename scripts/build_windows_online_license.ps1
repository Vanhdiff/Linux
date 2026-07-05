param(
  [Parameter(Mandatory = $false)]
  [string]$SupabaseUrl = "https://kcylkaiawiftlkkkltly.supabase.co",

  [Parameter(Mandatory = $true)]
  [string]$AnonKey
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AnonKey)) {
  throw "AnonKey is required. Pass the current Supabase anon public key."
}

Write-Host "Building Trading Desk with online license enabled..." -ForegroundColor Cyan
Write-Host "Supabase URL: $SupabaseUrl" -ForegroundColor Cyan

& "D:\flutter\bin\flutter.bat" build windows --release `
  --dart-define=SUPABASE_LICENSE_ENABLED=true `
  --dart-define=SUPABASE_URL=$SupabaseUrl `
  --dart-define=SUPABASE_ANON_KEY=$AnonKey

Write-Host ""
Write-Host "Built: build\windows\x64\runner\Release\trading_desk.exe" -ForegroundColor Green
