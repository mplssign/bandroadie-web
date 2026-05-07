#!/usr/bin/env bash
# =============================================================================
# BandRoadie — iOS Release Build Script
#
# This file is GITIGNORED. It lives only on the developer's machine.
# Sources .env for credentials and passes them via --dart-define.
#
# Usage:
#   ./tools/build_ios.sh          # Build .app for device testing
#   ./tools/build_ios.sh --ipa    # Build .ipa for App Store / TestFlight
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Parse flags ──────────────────────────────────────────────
BUILD_IPA=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --ipa) BUILD_IPA=true ;;
    --help|-h)
      echo "Usage:"
      echo "  ./tools/build_ios.sh          # Build .app"
      echo "  ./tools/build_ios.sh --ipa    # Build .ipa for App Store"
      exit 0
      ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
  shift
done

# ── Load credentials ─────────────────────────────────────────
ENV_FILE="$PROJECT_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  echo "Create it from .env.example and fill in your credentials."
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

REQUIRED_VARS=(
  SUPABASE_URL
  SUPABASE_ANON_KEY
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set in .env"
    exit 1
  fi
done

echo "✅ Credentials loaded"

# ── Build ─────────────────────────────────────────────────────
cd "$PROJECT_ROOT"

DART_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
)

if [[ "$BUILD_IPA" == true ]]; then
  echo "🔨 Building iOS .ipa (release)..."
  flutter build ipa --release "${DART_DEFINES[@]}"
  echo ""
  echo "✅ IPA built. Upload via:"
  echo "   open build/ios/ipa/*.ipa"
  echo "   — or use Transporter / 'xcrun altool' to upload to App Store Connect"
else
  echo "🔨 Building iOS .app (release)..."
  flutter build ios --release "${DART_DEFINES[@]}"
  echo ""
  echo "✅ Build complete. Open Xcode to archive and submit:"
  echo "   open ios/Runner.xcworkspace"
fi
