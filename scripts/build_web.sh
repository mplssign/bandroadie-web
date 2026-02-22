#!/usr/bin/env bash
set -e

echo "Installing Flutter..."
git clone https://github.com/flutter/flutter.git --depth 1 -b stable
export PATH="$PWD/flutter/bin:$PATH"

flutter doctor
flutter pub get

# Build with environment variables from Vercel
# These must be set as Vercel environment variables
# See: https://vercel.com/docs/concepts/projects/environment-variables
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

# Copy files Flutter doesn't include in web builds
# .well-known is required for Android App Links (assetlinks.json)
if [ -d "web/.well-known" ]; then
  cp -r web/.well-known build/web/.well-known
  echo "Copied .well-known to build/web/"
fi

# Copy vercel.json to build output
if [ -f "web/vercel.json" ]; then
  cp web/vercel.json build/web/vercel.json
  echo "Copied vercel.json to build/web/"
fi
