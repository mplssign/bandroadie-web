#!/usr/bin/env bash
# =============================================================================
# gen_dart_defines.sh — Generate dart_defines.json from .env
#
# Reads credentials from .env and writes them to dart_defines.json for use
# with flutter build --dart-define-from-file=dart_defines.json
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_FILE="$PROJECT_ROOT/dart_defines.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Generate JSON from environment variables
cat > "$OUTPUT_FILE" <<EOF
{
  "SUPABASE_URL": "${SUPABASE_URL}",
  "SUPABASE_ANON_KEY": "${SUPABASE_ANON_KEY}",
  "FIREBASE_API_KEY": "${FIREBASE_API_KEY:-}",
  "FIREBASE_AUTH_DOMAIN": "${FIREBASE_AUTH_DOMAIN:-}",
  "FIREBASE_PROJECT_ID": "${FIREBASE_PROJECT_ID:-}",
  "FIREBASE_STORAGE_BUCKET": "${FIREBASE_STORAGE_BUCKET:-}",
  "FIREBASE_MESSAGING_SENDER_ID": "${FIREBASE_MESSAGING_SENDER_ID:-}",
  "FIREBASE_APP_ID": "${FIREBASE_APP_ID:-}",
  "FIREBASE_MEASUREMENT_ID": "${FIREBASE_MEASUREMENT_ID:-}"
}
EOF

echo "Generated: $OUTPUT_FILE"
