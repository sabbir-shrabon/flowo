#!/usr/bin/env bash
set -e
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env file. Copy .env.example to .env and fill in your values."
  exit 1
fi

set -o allexport
source "$ENV_FILE"
set +o allexport

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ] || [ -z "$API_BASE_URL" ] || [ -z "$GOOGLE_WEB_CLIENT_ID" ]; then
  echo "Missing required environment variables."
  echo "Please set SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL, and GOOGLE_WEB_CLIENT_ID in life_agent_flutter/.env."
  exit 1
fi

flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID"
