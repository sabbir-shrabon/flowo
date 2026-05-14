param(
    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl
)

$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envFile)) {
    Write-Error "Missing .env file. Copy .env.example to .env and fill in your values."
    exit 1
}

$definesMap = @{}
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#')) {
        $parts = $line -split '=', 2
        if ($parts.Length -eq 2) {
            $key = $parts[0].Trim()
            $val = $parts[1].Trim()
            $definesMap[$key] = $val
        }
    }
}

if ($ApiBaseUrl) {
    $definesMap['API_BASE_URL'] = $ApiBaseUrl
}

if (-not $definesMap.ContainsKey('SUPABASE_URL') -or [string]::IsNullOrWhiteSpace($definesMap['SUPABASE_URL'])) {
    Write-Error "SUPABASE_URL is missing in .env."
    exit 1
}

if (-not $definesMap.ContainsKey('SUPABASE_ANON_KEY') -or [string]::IsNullOrWhiteSpace($definesMap['SUPABASE_ANON_KEY'])) {
    Write-Error "SUPABASE_ANON_KEY is missing in .env."
    exit 1
}

if (-not $definesMap.ContainsKey('API_BASE_URL') -or [string]::IsNullOrWhiteSpace($definesMap['API_BASE_URL'])) {
    Write-Error "API_BASE_URL is missing. Pass -ApiBaseUrl https://your-backend.onrender.com or set it in .env."
    exit 1
}

$defines = @()
foreach ($key in $definesMap.Keys) {
    $defines += "--dart-define=$key=$($definesMap[$key])"
}

Write-Host "Building Flutter web with defines:" -ForegroundColor Cyan
$defines | ForEach-Object {
    if ($_ -like '--dart-define=SUPABASE_ANON_KEY=*') {
        Write-Host "  --dart-define=SUPABASE_ANON_KEY=***" -ForegroundColor Gray
    } else {
        Write-Host "  $_" -ForegroundColor Gray
    }
}

Set-Location $PSScriptRoot
flutter build web --release @defines
