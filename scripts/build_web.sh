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
