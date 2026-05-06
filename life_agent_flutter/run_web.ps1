# Reads .env and runs flutter run -d chrome with --dart-define flags
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

Write-Host "Running flutter run -d chrome with defines:" -ForegroundColor Cyan
$defines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

Set-Location $PSScriptRoot
flutter run -d chrome @defines
