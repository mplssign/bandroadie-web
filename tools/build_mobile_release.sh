#!/usr/bin/env bash
# =============================================================================
# build_mobile_release.sh — Build BandRoadie mobile binaries with required config
#
# Prevents release builds that miss compile-time config by always injecting
# SUPABASE_URL and SUPABASE_ANON_KEY from local .env.
# =============================================================================

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

usage() {
  cat <<'EOF'
Usage:
  ./tools/build_mobile_release.sh ios
  ./tools/build_mobile_release.sh android-aab
  ./tools/build_mobile_release.sh android-apk

Options:
  --flavor <name>            Build flavor (optional)
  --target <path>            Dart entrypoint (default: lib/main.dart)
  --build-name <x.y.z>       Override version name
  --build-number <n>         Override build number

Examples:
  ./tools/build_mobile_release.sh ios --build-number 412
  ./tools/build_mobile_release.sh android-aab --flavor production
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

PLATFORM="$1"
shift

FLAVOR=""
TARGET="lib/main.dart"
BUILD_NAME=""
BUILD_NUMBER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flavor)
      FLAVOR="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --build-name)
      BUILD_NAME="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  echo "Create it from .env.example and set SUPABASE_URL + SUPABASE_ANON_KEY."
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "ERROR: SUPABASE_URL missing in .env"
  exit 1
fi

if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "ERROR: SUPABASE_ANON_KEY missing in .env"
  exit 1
fi

BUILD_ARGS=(
  "--release"
  "--target=$TARGET"
  "--dart-define=SUPABASE_URL=${SUPABASE_URL}"
  "--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
)

if [[ -n "$FLAVOR" ]]; then
  BUILD_ARGS+=("--flavor=$FLAVOR")
fi

if [[ -n "$BUILD_NAME" ]]; then
  BUILD_ARGS+=("--build-name=$BUILD_NAME")
fi

if [[ -n "$BUILD_NUMBER" ]]; then
  BUILD_ARGS+=("--build-number=$BUILD_NUMBER")
fi

cd "$ROOT_DIR"

# ── Clean build environment ──────────────────────────────────
# Release builds are infrequent; correctness beats speed.
# Always clean to prevent cached artifacts from contaminating the build.
echo ""
echo "Cleaning build environment..."
flutter clean
echo ""

case "$PLATFORM" in
  ios)
    flutter build ipa "${BUILD_ARGS[@]}"
    ;;
  android-aab)
    flutter build appbundle "${BUILD_ARGS[@]}"
    ;;
  android-apk)
    flutter build apk "${BUILD_ARGS[@]}"
    ;;
  *)
    echo "Unsupported platform: $PLATFORM"
    usage
    exit 1
    ;;
esac

# ── Verify build artifact contains production config ──────────
echo ""
echo "Verifying artifact contains production configuration..."

ARTIFACT_PATH=""
PROD_CONFIG_PATTERN="https://nekwjxvgbveheooyorjo.supabase.co"

case "$PLATFORM" in
  ios)
    # iOS: .ipa is a zip, extract Payload/*.app/Frameworks/App.framework/App
    ARTIFACT_PATH="build/ios/ipa/*.ipa"
    if ! ls $ARTIFACT_PATH 1> /dev/null 2>&1; then
      echo "ERROR: IPA artifact not found at $ARTIFACT_PATH"
      exit 1
    fi
    # Extract and check the App binary
    TEMP_DIR=$(mktemp -d)
    unzip -q "$ROOT_DIR"/build/ios/ipa/*.ipa -d "$TEMP_DIR"
    APP_BINARY=$(find "$TEMP_DIR/Payload" -name "App" -type f | head -1)
    MATCHES=$(strings "$APP_BINARY" | grep -c "$PROD_CONFIG_PATTERN" || true)
    rm -rf "$TEMP_DIR"
    if [[ "$MATCHES" -gt 0 ]]; then
      echo "✅ PASS: Production Supabase config found ($MATCHES occurrences)"
    else
      echo "❌ FAIL: Production Supabase config NOT found"
      echo "   Expected pattern: $PROD_CONFIG_PATTERN"
      echo "   Artifact: $ARTIFACT_PATH"
      exit 1
    fi
    ;;

  android-aab)
    ARTIFACT_PATH="build/app/outputs/bundle/release/app-release.aab"
    if [[ ! -f "$ARTIFACT_PATH" ]]; then
      echo "ERROR: AAB artifact not found at $ARTIFACT_PATH"
      exit 1
    fi
    # AAB: unzip and check base/lib/arm64-v8a/libapp.so
    TMP_SO=$(mktemp)
    unzip -p "$ARTIFACT_PATH" 'base/lib/arm64-v8a/libapp.so' > "$TMP_SO"
    MATCHES=$(strings "$TMP_SO" | grep -c "$PROD_CONFIG_PATTERN" || true)
    if [[ "$MATCHES" -gt 0 ]]; then
      echo "✅ PASS: Production Supabase config found ($MATCHES occurrences)"
    else
      echo "❌ FAIL: Production Supabase config NOT found"
      echo "   Expected pattern: $PROD_CONFIG_PATTERN"
      echo "   Artifact: $ARTIFACT_PATH"
      rm -f "$TMP_SO"
      exit 1
    fi
    rm -f "$TMP_SO"
    ;;

  android-apk)
    ARTIFACT_PATH="build/app/outputs/flutter-apk/app-release.apk"
    if [[ ! -f "$ARTIFACT_PATH" ]]; then
      echo "ERROR: APK artifact not found at $ARTIFACT_PATH"
      exit 1
    fi
    # APK: unzip and check lib/arm64-v8a/libapp.so
    TMP_SO=$(mktemp)
    unzip -p "$ARTIFACT_PATH" 'lib/arm64-v8a/libapp.so' > "$TMP_SO"
    MATCHES=$(strings "$TMP_SO" | grep -c "$PROD_CONFIG_PATTERN" || true)
    rm -f "$TMP_SO"
    if [[ "$MATCHES" -gt 0 ]]; then
      echo "✅ PASS: Production Supabase config found ($MATCHES occurrences)"
    else
      echo "❌ FAIL: Production Supabase config NOT found"
      echo "   Expected pattern: $PROD_CONFIG_PATTERN"
      echo "   Artifact: $ARTIFACT_PATH"
      exit 1
    fi
    ;;
esac

echo ""
