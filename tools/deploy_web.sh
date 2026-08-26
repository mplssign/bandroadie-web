#!/usr/bin/env bash
#
# deploy_web.sh — Build & deploy BandRoadie web app to Vercel
#

set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────────

PROJECT_NAME="web"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/web"

PUBSPEC="$ROOT_DIR/pubspec.yaml"
VERSION_JSON="$ROOT_DIR/web/version.json"

DEPLOY_HISTORY="$ROOT_DIR/tools/deploy_history.log"

# ─────────────────────────────────────────────────────────────
# Parse flags
# ─────────────────────────────────────────────────────────────

PREVIEW=false
SKIP_TESTS=false
ROLLBACK_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --preview) PREVIEW=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    --rollback) ROLLBACK_URL="$2"; shift ;;
    --help|-h)
      echo "Usage:"
      echo "  ./tools/deploy_web.sh"
      echo "  ./tools/deploy_web.sh --preview"
      echo "  ./tools/deploy_web.sh --rollback <deployment-url>"
      exit 0
      ;;
    *)
      echo "Unknown flag: $1"
      exit 1
      ;;
  esac
  shift
done

# ─────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}▸ $1${NC}"; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

# ─────────────────────────────────────────────────────────────
# Load credentials
# ─────────────────────────────────────────────────────────────

if [[ ! -f "$ROOT_DIR/.env" ]]; then
  fail ".env file not found — credentials required for build"
fi

set -a
# shellcheck source=/dev/null
source "$ROOT_DIR/.env"
set +a

[[ -z "${SUPABASE_URL:-}" ]] && fail "SUPABASE_URL not set in .env"
[[ -z "${SUPABASE_ANON_KEY:-}" ]] && fail "SUPABASE_ANON_KEY not set in .env"
[[ -z "${FIREBASE_API_KEY:-}" ]] && fail "FIREBASE_API_KEY not set in .env"
[[ -z "${FIREBASE_APP_ID:-}" ]] && fail "FIREBASE_APP_ID not set in .env"
[[ -z "${DEMO_PASSWORD:-}" ]] && fail "DEMO_PASSWORD not set in .env"

ok "Credentials loaded"

# ─────────────────────────────────────────────────────────────
# Rollback
# ─────────────────────────────────────────────────────────────

if [[ -n "$ROLLBACK_URL" ]]; then

  step "Rolling back deployment"

  vercel alias set "$ROLLBACK_URL" app.bandroadie.com

  ok "Rollback complete"
  echo "Restored deployment:"
  echo "$ROLLBACK_URL"

  exit 0
fi

# ─────────────────────────────────────────────────────────────
# Preflight checks
# ─────────────────────────────────────────────────────────────

step "Preflight checks"

command -v flutter >/dev/null || fail "Flutter not installed"
command -v vercel >/dev/null || fail "Vercel CLI not installed"
command -v python3 >/dev/null || fail "Python3 required"

cd "$ROOT_DIR"

CURRENT_BRANCH=$(git branch --show-current)

if [[ "$PREVIEW" == false && "$CURRENT_BRANCH" != "main" ]]; then
  fail "Production deploy must run from 'main'"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  fail "Uncommitted changes detected"
fi

if [[ "$PREVIEW" == false ]]; then

  step "Verifying local main is synced"

  git fetch origin

  LOCAL=$(git rev-parse main)
  REMOTE=$(git rev-parse origin/main)

  if [[ "$LOCAL" != "$REMOTE" ]]; then
    fail "Local main not synced with origin/main"
  fi

  ok "Local branch matches origin/main"
fi

ok "Branch: $CURRENT_BRANCH"

# ─────────────────────────────────────────────────────────────
# Sync mobile + web versioning
# ─────────────────────────────────────────────────────────────

step "Syncing version across web + mobile"

python3 - "$PUBSPEC" "$VERSION_JSON" <<'PY'
import json
import pathlib
import re
import sys
from datetime import date

pubspec = pathlib.Path(sys.argv[1])
version_json = pathlib.Path(sys.argv[2])

text = pubspec.read_text()
version_match = re.search(r"^version:\s*([^\s]+)\s*$", text, re.MULTILINE)
if not version_match:
    raise SystemExit("Could not parse version")

current = version_match.group(1)
legacy = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)\+(\d+)", current)
date_based = re.fullmatch(r"(\d{2})\.(\d{1,2})\.(\d{1,2})\+(\d{6})(\d{2})", current)

today = date.today()
current_day_code = int(today.strftime("%y%m%d"))

same_day_counter = 1
if date_based:
    yy = int(date_based.group(1))
    mm = int(date_based.group(2))
    dd = int(date_based.group(3))
    parsed_date = date(2000 + yy, mm, dd)
    current_day_num = int(f"{yy:02d}{mm:02d}{dd:02d}")
    persisted_counter = int(date_based.group(5))
    if parsed_date == today and current_day_num == current_day_code:
        same_day_counter = persisted_counter + 1
elif legacy:
    same_day_counter = 1
else:
    same_day_counter = 1

display_yy = int(today.strftime("%y"))
display_mm = today.month
display_dd = today.day

display_version = f"{display_yy}.{display_mm}.{display_dd}"
date_num = int(today.strftime("%y%m%d"))
build = date_num * 100 + same_day_counter
new_version = f"{display_version}+{build}"

updated = re.sub(r"(?m)^version:\s*.*$", f"version: {new_version}", text, count=1)
if updated == text:
    raise SystemExit("Could not update pubspec version")
pubspec.write_text(updated)

version_json.write_text(json.dumps({
    "app_name": "bandroadie",
    "version": display_version,
    "build_number": str(build),
    "package_name": "bandroadie"
}, indent=2))

print(f"Updated pubspec: {new_version}")
print("Generated version.json")
PY

ok "Versions synced"

# ─────────────────────────────────────────────────────────────
# Commit version bump
# ─────────────────────────────────────────────────────────────

step "Committing version bump"

git add pubspec.yaml web/version.json
git commit -m "chore: bump build version" || true
git push origin main

ok "Version committed"

# ─────────────────────────────────────────────────────────────
# Clean build environment
# ─────────────────────────────────────────────────────────────

step "Cleaning build environment"

flutter clean
flutter pub get

ok "Build environment clean"

# ─────────────────────────────────────────────────────────────
# Analyze
# ─────────────────────────────────────────────────────────────

step "Running flutter analyze"

flutter analyze --no-fatal-infos || fail "Analyzer failed"

ok "No analysis issues"

# ─────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────

if [[ "$SKIP_TESTS" == true ]]; then
  warn "Skipping tests"
else
  step "Running tests"
  flutter test || fail "Tests failed"
  ok "Tests passed"
fi

# ─────────────────────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────────────────────

step "Building Flutter web"

BUILD_TS=$(date +%s)

flutter build web \
  --release \
  --dart-define=BUILD_TIMESTAMP=$BUILD_TS \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=FIREBASE_API_KEY="${FIREBASE_API_KEY}" \
  --dart-define=FIREBASE_AUTH_DOMAIN="${FIREBASE_AUTH_DOMAIN}" \
  --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID}" \
  --dart-define=FIREBASE_STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_APP_ID="${FIREBASE_APP_ID}" \
  --dart-define=FIREBASE_MEASUREMENT_ID="${FIREBASE_MEASUREMENT_ID}" \
  --dart-define=DEMO_PASSWORD="${DEMO_PASSWORD}" \
  || fail "Flutter build failed"

ok "Build complete"

# ─────────────────────────────────────────────────────────────
# Verify Vercel project link
# ─────────────────────────────────────────────────────────────

step "Verifying Vercel project link"

cd "$BUILD_DIR"

if [[ ! -f ".vercel/project.json" ]]; then
  vercel link --yes --project "$PROJECT_NAME"
fi

ok "Linked to Vercel project"

# ─────────────────────────────────────────────────────────────
# Deploy
# ─────────────────────────────────────────────────────────────

if [[ "$PREVIEW" == true ]]; then

  step "Deploying preview"

  DEPLOY_OUTPUT=$(vercel deploy --yes 2>&1)

else

  step "Deploying production"

  DEPLOY_OUTPUT=$(vercel deploy --prod --yes 2>&1)

fi

# Extract URL from "Production: https://... [Xs]" or "Preview: https://... [Xs]" line
DEPLOY_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE '(Production|Preview): https://[^ ]+' | grep -oE 'https://[^ ]+' | tail -1)

# Fallback: any bare https:// line, strip trailing non-URL chars
if [[ -z "$DEPLOY_URL" ]]; then
  DEPLOY_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[a-zA-Z0-9._/-]+' | grep -v 'vercel.com/tholmes/web/' | tail -1)
fi

echo "$DEPLOY_OUTPUT"

cd "$ROOT_DIR"

if [[ -z "$DEPLOY_URL" ]]; then
  fail "Could not determine deployment URL"
fi

ok "Deployment complete"
echo "$DEPLOY_URL"

# ─────────────────────────────────────────────────────────────
# Safe aliasing
# ─────────────────────────────────────────────────────────────

step "Updating domain aliases"

vercel alias set "$DEPLOY_URL" app.bandroadie.com

ok "Aliases updated"

# ─────────────────────────────────────────────────────────────
# Record deploy history
# ─────────────────────────────────────────────────────────────

step "Recording deployment"

SHA=$(git rev-parse --short HEAD)
DATE=$(date)

echo "$DATE | $SHA | $DEPLOY_URL" >> "$DEPLOY_HISTORY"

ok "Deployment recorded"

# ─────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}🚀 Deployment finished successfully${NC}"
echo ""
echo "Deployment URL:"
echo "$DEPLOY_URL"
echo ""
echo "Rollback command:"
echo "./tools/deploy_web.sh --rollback $DEPLOY_URL"
echo ""