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
