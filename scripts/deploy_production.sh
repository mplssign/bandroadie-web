#!/bin/bash
# ============================================================================
# DEPLOY TO PRODUCTION
#
# Safe deployment script for bandroadie.com
# Builds Flutter web, verifies output, deploys to production only.
#
# Usage:
#   ./scripts/deploy_production.sh
#
# Safety guarantees:
#   - Requires explicit confirmation before deploying
#   - Always builds fresh (flutter clean + build)
#   - Verifies build output exists before deploying
#   - Deploys ONLY to the production Vercel project (by project ID)
#   - Never touches staging
#   - Never copies build output into web/ (prevents recursive nesting)
# ============================================================================

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
PRODUCTION_PROJECT_ID="prj_Aq7Q0pRo2oezPMOy01E0gMKO0Sk9"
PRODUCTION_PROJECT_NAME="web"
PRODUCTION_DOMAIN="bandroadie.com"
BUILD_DIR="build/web"

# ── Resolve project root (script may be called from anywhere) ────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ⚠️  DEPLOY → PRODUCTION ($PRODUCTION_DOMAIN)"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Confirmation gate ────────────────────────────────────────────────────────
read -p "⚠️  Deploy to PRODUCTION ($PRODUCTION_DOMAIN)? Type 'deploy' to confirm: " CONFIRM
if [[ "$CONFIRM" != "deploy" ]]; then
  echo "❌ Aborted."
  exit 1
fi

# ── Pre-flight: verify tools ─────────────────────────────────────────────────
if ! command -v flutter &> /dev/null; then
  echo "❌ flutter not found in PATH"
  exit 1
fi
if ! command -v vercel &> /dev/null; then
  echo "❌ vercel CLI not found. Install: npm i -g vercel"
  exit 1
fi

# ── Auto-increment build number ──────────────────────────────────────────────
CURRENT_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
VERSION_NAME=$(echo "$CURRENT_VERSION" | cut -d+ -f1)
BUILD_NUMBER=$(echo "$CURRENT_VERSION" | cut -d+ -f2)
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION="$VERSION_NAME+$NEW_BUILD_NUMBER"
sed -i '' "s/version: .*/version: $NEW_VERSION/" pubspec.yaml
echo "📦 Version: $NEW_VERSION"

# ── Clean & build ────────────────────────────────────────────────────────────
echo "🧹 Cleaning..."
flutter clean
echo "📦 Getting packages..."
flutter pub get
echo "🔨 Building web..."
flutter build web --release --no-wasm-dry-run

# ── Verify build ─────────────────────────────────────────────────────────────
if [[ ! -f "$BUILD_DIR/main.dart.js" ]] || [[ ! -f "$BUILD_DIR/index.html" ]]; then
  echo "❌ Build failed: $BUILD_DIR/main.dart.js or index.html missing"
  exit 1
fi
echo "✅ Build verified: $BUILD_DIR"

# ── Safety check: ensure correct Vercel project ─────────────────────────────
# Write the production project config directly — never rely on leftover state
mkdir -p "$BUILD_DIR/.vercel"
cat > "$BUILD_DIR/.vercel/project.json" << EOF
{"projectId":"$PRODUCTION_PROJECT_ID","orgId":"team_LNX9yS07KHOWq7cDTKno558g","projectName":"$PRODUCTION_PROJECT_NAME"}
EOF

echo "🚀 Deploying to PRODUCTION..."
cd "$BUILD_DIR"
vercel --prod

# ── Restore staging config for build/web (default safe state) ────────────────
cd "$PROJECT_ROOT"
cat > "$BUILD_DIR/.vercel/project.json" << EOF
{"projectId":"prj_nPoARX3pVNg5zYG12jucXJK7Ole6","orgId":"team_LNX9yS07KHOWq7cDTKno558g","projectName":"bandroadie-staging"}
EOF

echo ""
echo "✅ Production deploy complete: $NEW_VERSION"
echo "🔗 https://$PRODUCTION_DOMAIN"
echo ""
