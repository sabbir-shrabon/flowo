# Reads .env and runs Flutter web in Chrome at http://localhost:5000.
# For Google OAuth on web, `http://localhost:5000` must also be added to:
# 1. Google Cloud OAuth authorized JavaScript origins
# 2. Supabase Auth URL configuration (site URL / additional redirect URLs)
$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envFile)) {
    Write-Error "Missing .env file. Copy .env.example to .env and fill in your values."
    exit 1
}

$defines = @()
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        $parts = $line -split '=', 2
        if ($parts.Length -eq 2) {
            $key = $parts[0].Trim()
            $val = $parts[1].Trim()
            # For web, replace 10.0.2.2 with localhost
            if ($val -match '10\.0\.2\.2') {
                $val = $val -replace '10\.0\.2\.2', 'localhost'
            }
            $defines += "--dart-define=$key=$val"
        }
    }
}

Write-Host "Running Flutter web in Chrome at http://localhost:5000 with defines:" -ForegroundColor Cyan
$defines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

Set-Location $PSScriptRoot
flutter run -d chrome --web-hostname=localhost --web-port=5000 @defines
