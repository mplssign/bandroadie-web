#!/bin/bash
# ============================================================================
# DEPLOY TO STAGING
#
# Safe deployment script for bandroadie-staging.vercel.app
# Builds Flutter web, verifies output, deploys to staging only.
#
# Usage:
#   ./scripts/deploy_staging.sh
#
# Safety guarantees:
#   - Always builds fresh (flutter clean + build)
#   - Verifies build output exists before deploying
#   - Deploys ONLY to the staging Vercel project (by project ID)
#   - Never touches production
#   - Never copies build output into web/ (prevents recursive nesting)
# ============================================================================

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
STAGING_PROJECT_ID="prj_nPoARX3pVNg5zYG12jucXJK7Ole6"
STAGING_PROJECT_NAME="bandroadie-staging"
BUILD_DIR="build/web"

# ── Resolve project root (script may be called from anywhere) ────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  DEPLOY → STAGING ($STAGING_PROJECT_NAME)"
echo "═══════════════════════════════════════════════════════"
echo ""

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
# Write the staging project config directly — never rely on leftover state
mkdir -p "$BUILD_DIR/.vercel"
cat > "$BUILD_DIR/.vercel/project.json" << EOF
{"projectId":"$STAGING_PROJECT_ID","orgId":"team_LNX9yS07KHOWq7cDTKno558g","projectName":"$STAGING_PROJECT_NAME"}
EOF

echo "🚀 Deploying to STAGING..."
cd "$BUILD_DIR"
vercel --prod

echo ""
echo "✅ Staging deploy complete: $NEW_VERSION"
echo "🔗 https://bandroadie-staging.vercel.app"
echo ""
