# Run Flutter app on Android Emulator with environment variables
# Using the default emulator ID or the first available one

$SUPABASE_URL="https://luaijkhveihlfzbdalfw.supabase.co"
$SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx1YWlqa2h2ZWlobGZ6YmRhbGZ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU3NDY2ODQsImV4cCI6MjA5MTMyMjY4NH0.x7WnYUzGBL7yla-dmDpMQmtUz79ZBii5XsIXHhtfrO0"
$API_BASE_URL="http://10.0.2.2:8000"

# Target emulator from your list
$DEVICE_ID="emulator-5554"

cd life_agent_flutter

flutter run -d $DEVICE_ID `
  --dart-define=SUPABASE_URL=$SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY `
  --dart-define=API_BASE_URL=$API_BASE_URL
