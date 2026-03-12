#!/usr/bin/env bash
#
# deploy_web.sh — Build & deploy BandRoadie web app to Vercel
#
# Usage:
#   ./tools/deploy_web.sh           # Build, test, deploy to production
#   ./tools/deploy_web.sh --preview # Build, test, deploy preview (no prod)
#   ./tools/deploy_web.sh --skip-tests # Skip flutter test (faster)
#
# Prerequisites:
#   - Vercel CLI installed: npm i -g vercel
#   - Logged into Vercel: vercel login
#   - Project linked (one-time): cd build/web && vercel link --project bandroadie-web
#
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────
PROJECT_NAME="bandroadie-web"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/web"

# ── Parse flags ─────────────────────────────────────────────────────────
PREVIEW=false
SKIP_TESTS=false
for arg in "$@"; do
  case $arg in
    --preview)  PREVIEW=true ;;
    --skip-tests) SKIP_TESTS=true ;;
    --help|-h)
      echo "Usage: ./tools/deploy_web.sh [--preview] [--skip-tests]"
      echo ""
      echo "  --preview      Deploy a preview URL instead of production"
      echo "  --skip-tests   Skip 'flutter test' step"
      exit 0
      ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

step() { echo -e "\n${CYAN}▸ $1${NC}"; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

# ── Preflight checks ───────────────────────────────────────────────────
step "Preflight checks"

command -v flutter >/dev/null 2>&1 || fail "flutter not found. Install Flutter first."
command -v vercel  >/dev/null 2>&1 || fail "vercel CLI not found. Run: npm i -g vercel"

cd "$ROOT_DIR"

# Verify we're on main branch for production deploys
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$PREVIEW" == false && "$CURRENT_BRANCH" != "main" ]]; then
  fail "Production deploys must be from 'main' branch. You're on '$CURRENT_BRANCH'.\n  Switch with: git checkout main\n  Or use: ./tools/deploy_web.sh --preview"
fi

# Check for uncommitted changes
if [[ -n "$(git status --porcelain)" ]]; then
  if [[ "$PREVIEW" == false ]]; then
    fail "Uncommitted changes detected. Commit or stash before production deploy."
  else
    warn "Uncommitted changes detected (OK for preview deploy)"
  fi
fi

ok "Branch: $CURRENT_BRANCH"

# ── Analyze ─────────────────────────────────────────────────────────────
step "Running flutter analyze"
flutter analyze || fail "Analysis errors found. Fix them before deploying."
ok "No analysis issues"

# ── Test ────────────────────────────────────────────────────────────────
if [[ "$SKIP_TESTS" == true ]]; then
  warn "Skipping tests (--skip-tests)"
else
  step "Running flutter test"
  flutter test || fail "Tests failed. Fix them before deploying."
  ok "All tests passed"
fi

# ── Build ───────────────────────────────────────────────────────────────
step "Building web release"
flutter build web --release || fail "Build failed."
ok "Build complete: $BUILD_DIR"

# ── Verify Vercel link ──────────────────────────────────────────────────
step "Verifying Vercel project link"
VERCEL_PROJECT_FILE="$BUILD_DIR/.vercel/project.json"

if [[ -f "$VERCEL_PROJECT_FILE" ]]; then
  LINKED_PROJECT=$(python3 -c "import json; print(json.load(open('$VERCEL_PROJECT_FILE')).get('projectName',''))" 2>/dev/null || echo "")
  if [[ "$LINKED_PROJECT" != "$PROJECT_NAME" ]]; then
    warn "Linked to '$LINKED_PROJECT' instead of '$PROJECT_NAME'. Re-linking..."
    cd "$BUILD_DIR"
    vercel link --yes --project "$PROJECT_NAME"
    cd "$ROOT_DIR"
  fi
else
  warn "Not linked to Vercel. Linking now..."
  cd "$BUILD_DIR"
  vercel link --yes --project "$PROJECT_NAME"
  cd "$ROOT_DIR"
fi
ok "Linked to Vercel project: $PROJECT_NAME"

# ── Deploy ──────────────────────────────────────────────────────────────
cd "$BUILD_DIR"

if [[ "$PREVIEW" == true ]]; then
  step "Deploying preview"
  DEPLOY_URL=$(vercel 2>&1 | tail -1)
  ok "Preview deployed: $DEPLOY_URL"
else
  step "Deploying to PRODUCTION"
  echo -e "${YELLOW}  Deploying to bandroadie.com + app.bandroadie.com${NC}"
  vercel --prod || fail "Production deploy failed."
  ok "Production deploy complete!"
  echo ""
  echo -e "${GREEN}  🎸 Live at:${NC}"
  echo -e "${GREEN}     https://bandroadie.com        (marketing)${NC}"
  echo -e "${GREEN}     https://app.bandroadie.com    (web app)${NC}"
fi

cd "$ROOT_DIR"
echo ""
