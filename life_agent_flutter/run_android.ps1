# Run Flutter app on Android Emulator with environment variables
# Using the default emulator ID or the first available one

$SUPABASE_URL="https://luaijkhveihlfzbdalfw.supabase.co"
$SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1YWlqa2h2ZWlobGZ6YmRhbGZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3NDY2ODQsImV4cCI6MjA5MTMyMjY4NH0.x7WnYUzGBL7yla-dmDpMQmtUz79ZBii5XsIXHhtfrO0"
$API_BASE_URL="http://10.0.2.2:8000"
$GOOGLE_WEB_CLIENT_ID="294911446807-g08pqvu7kjjll8ltruue0lju5hhrkhu8.apps.googleusercontent.com"

# Always run from the Flutter project directory, no matter where the script is launched from.
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectDir

# Optional: set a specific Android device/emulator id here.
$DEVICE_ID=""

if ([string]::IsNullOrWhiteSpace($DEVICE_ID)) {
  $androidDevice = flutter devices --machine | ConvertFrom-Json | Where-Object {
    $_.targetPlatform -like "android-*"
  } | Select-Object -First 1

  if (-not $androidDevice) {
    Write-Error "No Android device or emulator found. Start an Android emulator or connect a physical Android device, then run this script again."
    exit 1
  }

  $DEVICE_ID = $androidDevice.id
}

flutter run -d $DEVICE_ID `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY `
  --dart-define=API_BASE_URL=$API_BASE_URL `
  --dart-define=GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID
