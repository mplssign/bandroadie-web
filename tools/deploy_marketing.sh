#!/usr/bin/env bash
#
# deploy_marketing.sh — Deploy BandRoadie marketing site to Vercel
#

set -euo pipefail

MARKETING_PROJECT="marketing"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MARKETING_DIR="$ROOT_DIR/marketing"
DEPLOY_HISTORY="$ROOT_DIR/tools/deploy_history.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PREVIEW=false
ROLLBACK_URL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --preview) PREVIEW=true ;;
    --rollback) ROLLBACK_URL="$2"; shift ;;
    --help|-h)
      echo "Usage:"
      echo "  ./tools/deploy_marketing.sh"
      echo "  ./tools/deploy_marketing.sh --preview"
      echo "  ./tools/deploy_marketing.sh --rollback <deployment-url>"
      exit 0
      ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
  shift
done

step() { echo -e "\n${CYAN}▸ $1${NC}"; }
ok()   { echo -e "${GREEN}  ✓ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

# ── Rollback ──────────────────────────────────────────────────

if [[ -n "$ROLLBACK_URL" ]]; then
  step "Rolling back marketing deployment"
  vercel alias set "$ROLLBACK_URL" bandroadie.com
  vercel alias set "$ROLLBACK_URL" www.bandroadie.com
  ok "Rollback complete: $ROLLBACK_URL"
  exit 0
fi

# ── Preflight ─────────────────────────────────────────────────

step "Preflight checks"

command -v vercel >/dev/null || fail "Vercel CLI not installed"

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

# ── Verify Vercel project link ────────────────────────────────

step "Verifying Vercel project link"

cd "$MARKETING_DIR"

if [[ ! -f ".vercel/project.json" ]]; then
  vercel link --yes --project "$MARKETING_PROJECT"
fi

ok "Linked to Vercel project: $MARKETING_PROJECT"

# ── Deploy ────────────────────────────────────────────────────

if [[ "$PREVIEW" == true ]]; then
  step "Deploying preview"
  DEPLOY_OUTPUT=$(vercel deploy --yes 2>&1)
else
  step "Deploying production"
  DEPLOY_OUTPUT=$(vercel deploy --prod --yes 2>&1)
fi

DEPLOY_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE '(Production|Preview): https://[^ ]+' | grep -oE 'https://[^ ]+' | tail -1)

if [[ -z "$DEPLOY_URL" ]]; then
  DEPLOY_URL=$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[a-zA-Z0-9._/-]+' | grep -v 'vercel.com/tholmes/marketing/' | tail -1)
fi

echo "$DEPLOY_OUTPUT"

cd "$ROOT_DIR"

if [[ -z "$DEPLOY_URL" ]]; then
  fail "Could not determine deployment URL"
fi

ok "Deployment complete"
echo "$DEPLOY_URL"

# ── Alias domains (production only) ──────────────────────────

if [[ "$PREVIEW" == false ]]; then
  step "Updating domain aliases"
  vercel alias set "$DEPLOY_URL" bandroadie.com
  vercel alias set "$DEPLOY_URL" www.bandroadie.com
  ok "Aliases updated"
fi

# ── Record history ────────────────────────────────────────────

step "Recording deployment"
SHA=$(git rev-parse --short HEAD)
DATE=$(date)
echo "$DATE | marketing | $SHA | $DEPLOY_URL" >> "$DEPLOY_HISTORY"
ok "Deployment recorded"

echo ""
echo -e "${GREEN}🚀 Marketing deployment finished${NC}"
echo ""
echo "Deployment URL: $DEPLOY_URL"
echo ""
echo "Rollback command:"
echo "./tools/deploy_marketing.sh --rollback $DEPLOY_URL"
echo ""
