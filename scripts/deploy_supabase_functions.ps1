param(
  [Parameter(Mandatory = $false)]
  [string]$ProjectRef = "kcylkaiawiftlkkkltly",

  [Parameter(Mandatory = $false)]
  [string]$SupabaseUrl = "https://kcylkaiawiftlkkkltly.supabase.co"
)

$ErrorActionPreference = "Stop"

function Assert-SupabaseCli {
  $command = Get-Command supabase -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    throw "Supabase CLI is not installed. Install it first, then rerun this script."
  }
}

Assert-SupabaseCli

Write-Host "Linking project $ProjectRef..." -ForegroundColor Cyan
supabase link --project-ref $ProjectRef

Write-Host "Supabase reserved env vars are provided automatically inside hosted Edge Functions." -ForegroundColor Yellow
Write-Host "No manual SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY secret setup is required." -ForegroundColor Yellow

Write-Host "Deploying activate-license..." -ForegroundColor Cyan
supabase functions deploy activate-license

Write-Host "Deploying validate-license..." -ForegroundColor Cyan
supabase functions deploy validate-license

Write-Host ""
Write-Host "Done. Function URLs:" -ForegroundColor Green
Write-Host "  $SupabaseUrl/functions/v1/activate-license"
Write-Host "  $SupabaseUrl/functions/v1/validate-license"
