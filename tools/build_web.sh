#!/usr/bin/env bash
#
# deploy_web.sh — Build & deploy BandRoadie web app to Vercel
#

set -euo pipefail

PROJECT_NAME="web"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/web"

PUBSPEC="$ROOT_DIR/pubspec.yaml"
VERSION_JSON="$ROOT_DIR/web/version.json"

DEPLOY_HISTORY="$ROOT_DIR/tools/deploy_history.log"

PREVIEW=false
SKIP_TESTS=false
ROLLBACK_URL=""
FORCE_PROD=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --preview) PREVIEW=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    --rollback) ROLLBACK_URL="$2"; shift ;;
    --prod) FORCE_PROD=true ;;
    --help|-h)
      echo "./tools/deploy_web.sh"
      echo "./tools/deploy_web.sh --preview"
      echo "./tools/deploy_web.sh --prod"
      echo "./tools/deploy_web.sh --rollback <deployment-url>"
      exit 0
      ;;
    *)
      echo "Unknown flag: $1"
      exit 1
      ;;
  esac
  shift
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step(){ echo -e "\n${CYAN}▸ $1${NC}"; }
ok(){ echo -e "${GREEN}  ✓ $1${NC}"; }
warn(){ echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail(){ echo -e "${RED}  ✗ $1${NC}"; exit 1; }

# Rollback
if [[ -n "$ROLLBACK_URL" ]]; then
  step "Rolling back deployment"
  vercel alias set "$ROLLBACK_URL" bandroadie.com
  vercel alias set "$ROLLBACK_URL" app.bandroadie.com
  ok "Rollback complete"
  exit 0
fi

step "Preflight checks"

command -v flutter >/dev/null || fail "Flutter not installed"
command -v vercel >/dev/null || fail "Vercel CLI not installed"
command -v python3 >/dev/null || fail "Python3 required"

cd "$ROOT_DIR"

CURRENT_BRANCH=$(git branch --show-current)

if [[ "$PREVIEW" == false && "$CURRENT_BRANCH" != "main" && "$FORCE_PROD" == false ]]; then
  fail "Production deploy must run from main (or use --prod to override)"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  fail "Uncommitted changes detected"
fi

if [[ "$PREVIEW" == false ]]; then
  step "Verifying main branch sync"
  git fetch origin
  LOCAL=$(git rev-parse main)
  REMOTE=$(git rev-parse origin/main)

  if [[ "$LOCAL" != "$REMOTE" ]]; then
    fail "Local main not synced with origin/main"
  fi
fi

ok "Branch: $CURRENT_BRANCH"

# Version sync
step "Syncing version across web + mobile"

python3 <<EOF
import re,json,pathlib
pubspec=pathlib.Path("$PUBSPEC")
version_json=pathlib.Path("$VERSION_JSON")

text=pubspec.read_text()

m=re.search(r"version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)",text)
if not m: raise SystemExit("Could not parse version")

version=m.group(1)
build=int(m.group(2))+1
new=f"{version}+{build}"

updated=re.sub(
r"version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+",
f"version: {new}",text)

pubspec.write_text(updated)

data={
"app_name":"bandroadie",
"version":version,
"build_number":str(build),
"package_name":"bandroadie"
}

version_json.write_text(json.dumps(data,indent=2))
print("Updated version:",new)
EOF

ok "Versions synced"

# Commit version bump
step "Committing version bump"

git add pubspec.yaml web/version.json

if ! git diff --cached --quiet; then
  git commit -m "chore: bump build version"
  git push origin main
fi

ok "Version committed"

# Analyze
step "Running flutter analyze"
flutter analyze || fail "Analyzer failed"
ok "No issues"

# Tests
if [[ "$SKIP_TESTS" == true ]]; then
  warn "Skipping tests"
else
  step "Running tests"
  flutter test || fail "Tests failed"
  ok "Tests passed"
fi

# Smart rebuild
step "Checking if Flutter rebuild required"

NEEDS_BUILD=false
WATCH_PATHS=("lib" "web" "pubspec.yaml" "assets")

for path in "${WATCH_PATHS[@]}"; do
  if git diff --name-only HEAD^ HEAD | grep -q "^$path"; then
    NEEDS_BUILD=true
    break
  fi
done

if [[ ! -d "$BUILD_DIR" ]]; then
  NEEDS_BUILD=true
fi

if [[ "$NEEDS_BUILD" == true ]]; then
  step "Building Flutter web"
  BUILD_TS=$(date +%s)

  flutter build web \
    --release \
    --pwa-strategy=none \
    --dart-define=BUILD_TIMESTAMP=$BUILD_TS \
    || fail "Flutter build failed"

  ok "Build complete"
else
  warn "Skipping Flutter build"
fi

# Ensure Vercel project
step "Verifying Vercel project"

cd "$BUILD_DIR"

if [[ ! -f ".vercel/project.json" ]]; then
  vercel link --yes --project "$PROJECT_NAME"
fi

ok "Linked to Vercel project"

# Deploy
if [[ "$PREVIEW" == true ]]; then
  step "Deploying preview"
  DEPLOY_JSON=$(vercel --yes --confirm --output=json 2>/dev/null)
else
  step "Deploying production"
  DEPLOY_JSON=$(vercel --prod --yes --confirm --output=json 2>/dev/null)
fi

DEPLOY_URL=$(echo "$DEPLOY_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['url'])")

cd "$ROOT_DIR"

if [[ -z "$DEPLOY_URL" ]]; then
  fail "Could not determine deployment URL"
fi

ok "Deployment complete"

# Safe aliasing
step "Updating aliases"

vercel alias set "$DEPLOY_URL" bandroadie.com
vercel alias set "$DEPLOY_URL" app.bandroadie.com

ok "Aliases updated"

# Save deploy history
step "Recording deployment"

touch "$DEPLOY_HISTORY"

SHA=$(git rev-parse --short HEAD)
DATE=$(date)

echo "$DATE | $SHA | $DEPLOY_URL" >> "$DEPLOY_HISTORY"

ok "Deployment recorded"

echo ""
echo -e "${GREEN}🚀 Deployment finished successfully${NC}"
echo ""
echo "$DEPLOY_URL"
echo ""
echo "Rollback:"
echo "./tools/deploy_web.sh --rollback $DEPLOY_URL"
echo ""