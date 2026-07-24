#!/bin/bash
set -e

echo "Setting up Flutter for Web deployment on Vercel..."

# Download and install Flutter
if [ ! -d "flutter" ]; then
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git
fi
export PATH="$PATH:$PWD/flutter/bin"

flutter config --no-analytics
flutter pub get

# Build flutter web
echo "Building Flutter Web..."
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID"

echo "Build completed successfully!"
