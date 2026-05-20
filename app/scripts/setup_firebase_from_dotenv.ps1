# Load app/.env into the process environment, then write native Firebase config files.
$AppRoot = Split-Path $PSScriptRoot -Parent
$EnvFile = Join-Path $AppRoot '.env'
if (-not (Test-Path $EnvFile)) {
  throw "Missing $EnvFile — copy from .env.example and add FIREBASE_* values from your team or Firebase Console."
}
Get-Content $EnvFile | ForEach-Object {
  if ($_ -match '^\s*#' -or $_ -notmatch '^\s*([^=]+)=(.*)$') { return }
  $name = $matches[1].Trim()
  $value = $matches[2].Trim()
  Set-Item -Path "env:$name" -Value $value
}
& (Join-Path $PSScriptRoot 'write_firebase_native_config.ps1') -AppRoot $AppRoot
Write-Host 'Done. Run: flutter run --dart-define-from-file=.env'
