#!/bin/bash
# =============================================================================
# Web Build Script with Deployment Versioning
# 
# This script builds the Flutter web app with a commit SHA injected for
# deployment identification. The SHA appears in the app footer as:
#   "Version X.Y.Z (Build N) • abc123"
#
# Usage:
#   ./scripts/build_web.sh          # Uses current git commit
#   ./scripts/build_web.sh abc123   # Uses provided SHA (for CI override)
#
# Environment Variables (Vercel):
#   VERCEL_GIT_COMMIT_SHA - Preferred, set by Vercel
#   VERCEL_DEPLOYMENT_ID  - Fallback if SHA not available
# =============================================================================

set -e

# Determine commit SHA
# Priority: 1) CLI arg, 2) VERCEL_GIT_COMMIT_SHA, 3) VERCEL_DEPLOYMENT_ID, 4) git rev-parse
if [ -n "$1" ]; then
    COMMIT_SHA="$1"
elif [ -n "$VERCEL_GIT_COMMIT_SHA" ]; then
    COMMIT_SHA="$VERCEL_GIT_COMMIT_SHA"
elif [ -n "$VERCEL_DEPLOYMENT_ID" ]; then
    COMMIT_SHA="$VERCEL_DEPLOYMENT_ID"
else
    COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
fi

echo "🔧 Building Flutter Web..."
echo "   Commit SHA: ${COMMIT_SHA:-'(not set)'}"

# Build with commit SHA injected
if [ -n "$COMMIT_SHA" ]; then
    flutter build web --release --dart-define=COMMIT_SHA="$COMMIT_SHA"
else
    flutter build web --release
fi

echo "✅ Build complete!"
echo "   Output: build/web/"
