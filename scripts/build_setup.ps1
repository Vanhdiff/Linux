param(
  [Parameter(Mandatory = $false)]
  [string]$InstallerScript = "installer.iss"
)

$ErrorActionPreference = "Stop"

function Resolve-IsccPath {
  $command = Get-Command iscc -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }

  $candidates = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "Inno Setup Compiler (ISCC.exe) was not found. Install Inno Setup 6 first, then rerun this script."
}

if (-not (Test-Path $InstallerScript)) {
  throw "Installer script not found: $InstallerScript"
}

$iscc = Resolve-IsccPath

Write-Host "Building installer with $iscc" -ForegroundColor Cyan
& $iscc $InstallerScript

Write-Host ""
Write-Host "Done. Check the installer folder for trading-desk-setup-1.0.0.exe" -ForegroundColor Green
