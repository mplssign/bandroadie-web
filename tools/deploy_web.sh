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

python3 <<EOF
import re, json, pathlib

pubspec = pathlib.Path("$PUBSPEC")
version_json = pathlib.Path("$VERSION_JSON")

text = pubspec.read_text()

match = re.search(r"version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)", text)
if not match:
    raise SystemExit("Could not parse pubspec version")

version = match.group(1)
build = int(match.group(2)) + 1

new_version = f"{version}+{build}"

updated = re.sub(
    r"version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+",
    f"version: {new_version}",
    text
)

pubspec.write_text(updated)

data = {
    "app_name": "bandroadie",
    "version": version,
    "build_number": str(build),
    "package_name": "bandroadie"
}

version_json.write_text(json.dumps(data, indent=2))

print("Updated pubspec:", new_version)
print("Generated version.json")
EOF

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