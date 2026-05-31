# ARCHITECT_PLAN.md — feature/webflow-marketing-site

**Date:** 2026-05-30  
**Author:** Architect Agent  
**Branch:** `feature/webflow-marketing-site`  
**Docs path:** `docs/features/webflow-marketing-site/ARCHITECT_PLAN.md`

---

## 1. Problem Statement

`bandroadie.com` is currently served by the same Vercel project (`web`) as `app.bandroadie.com`. The Flutter `main.dart` uses `_isMarketingHost()` to detect the hostname and route to `LandingPage` vs `AuthGate`. A new, purpose-built Webflow-exported marketing site must replace this arrangement: `bandroadie.com` and `www.bandroadie.com` must be served from a new, isolated Vercel project backed by the Webflow export. `app.bandroadie.com` must be completely unaffected.

---

## 2. Scope

### In Scope
- Create `marketing/` directory at repo root to house the Webflow export.
- Write `marketing/vercel.json` with appropriate cache headers.
- Copy `web/privacy.html` and `web/support.html` into `marketing/` (see §7).
- Write `tools/deploy_marketing.sh` for one-command deploys of the marketing project.
- Modify `tools/deploy_web.sh` to remove the `bandroadie.com` alias from both the production deploy step and the rollback path.
- Document manual Vercel dashboard steps required to migrate domains.

### Out of Scope (Explicitly Deferred)
- `lib/features/landing/` — do not delete or modify.
- `_isMarketingHost()` in `lib/main.dart` — do not modify. It is dead code once the domain is migrated; it is safe to leave in place.

---

## 3. Webflow Export — Structure Summary

**Source:** `/Users/tonyholmes/Documents/BandRoadie/New BandRoadie Website/genienova.webflow.io/`

| Item | Description |
|------|-------------|
| `index.html` | Full self-contained marketing homepage. Loads CSS/JS from Webflow CDN (`cdn.prod.website-files.com`). Canonical URL already set to `https://bandroadie.com/`. |
| `404.html` | Custom 404 page from Webflow. |
| `changelog.html` | Changelog page. |
| `_downloads.html` | Downloads page. |
| `license.html` | License page. |
| `style-guide.html` | Webflow style guide (internal). |
| `images/` | 26 files: PNGs (UUID-named + named assets), JPGs, GIFs. All image references in HTML point to this local directory. |

**External dependencies:** Webflow CDN (`cdn.prod.website-files.com`) serves all CSS and JavaScript at runtime. No local CSS or JS files exist in the export. No build step is required.

**Note:** `index.html` contains `data-wf-domain="genienova.webflow.io"` on the `<html>` element. The Engineer must update this attribute to `data-wf-domain="bandroadie.com"` before deploying, so Webflow's runtime JS binds correctly to the production domain.

---

## 4. Repository Layout — New Files

The Engineer must create the following structure. **All Webflow export files are copied verbatim except the `data-wf-domain` attribute fix noted above.**

```
marketing/                         ← new directory at repo root
├── vercel.json                    ← new (see §5)
├── index.html                     ← copied from Webflow export
├── 404.html                       ← copied from Webflow export
├── changelog.html                 ← copied from Webflow export
├── _downloads.html                ← copied from Webflow export
├── license.html                   ← copied from Webflow export
├── style-guide.html               ← copied from Webflow export
├── privacy.html                   ← copied from web/privacy.html (see §7)
├── support.html                   ← copied from web/support.html (see §7)
└── images/                        ← copied from Webflow export images/
    ├── [all 26 image files]
    └── ...
```

**Why `marketing/` at repo root:**  
- Keeps the Webflow site entirely separate from the Flutter `web/` build source directory.  
- `flutter build web` cannot accidentally include `marketing/` files.  
- A distinct Vercel project root can be set to `marketing/` without ambiguity.  
- Consistent with the repo's convention of top-level purpose directories (`web/`, `tools/`, `docs/`).

---

## 5. `marketing/vercel.json`

The Webflow export is pure static HTML + local images. CSS/JS are served from Webflow's CDN and are not in this directory. Cache strategy:

- **HTML files:** no-cache — content changes with every Webflow publish.
- **Images:** long-lived immutable cache — UUID-named files never change at a given path.
- **Custom 404:** Vercel natively supports a `404.html` file; explicit routing is not required but is listed for clarity.

```json
{
  "cleanUrls": true,
  "trailingSlash": false,
  "headers": [
    {
      "source": "/",
      "headers": [
        { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
      ]
    },
    {
      "source": "/(.*)\\.html",
      "headers": [
        { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
      ]
    },
    {
      "source": "/privacy",
      "headers": [
        { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
      ]
    },
    {
      "source": "/support",
      "headers": [
        { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
      ]
    },
    {
      "source": "/images/(.*)",
      "headers": [
        { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
      ]
    }
  ]
}
```

`cleanUrls: true` causes Vercel to serve `/changelog.html` at `/changelog`, `/privacy.html` at `/privacy`, etc., without redirect noise.

---

## 6. Changes to `tools/deploy_web.sh`

Two sections must be modified. No other lines in this file may be touched.

### 6.1 — Rollback section (approx. line 99–107)

**Remove** the `bandroadie.com` alias line from the rollback block. The rollback command must only restore `app.bandroadie.com`.

**Before:**
```bash
  vercel alias set "$ROLLBACK_URL" bandroadie.com
  vercel alias set "$ROLLBACK_URL" app.bandroadie.com
```

**After:**
```bash
  vercel alias set "$ROLLBACK_URL" app.bandroadie.com
```

### 6.2 — Production alias section (approx. line 293–297)

**Remove** the `bandroadie.com` alias line from the "Updating domain aliases" step. The deploy script must only alias `app.bandroadie.com`.

**Before:**
```bash
vercel alias set "$DEPLOY_URL" bandroadie.com
vercel alias set "$DEPLOY_URL" app.bandroadie.com
```

**After:**
```bash
vercel alias set "$DEPLOY_URL" app.bandroadie.com
```

---

## 7. `privacy.html` and `support.html` Assessment

### Current state
Both files exist in `web/privacy.html` and `web/support.html`. They are static HTML pages served by the Flutter Vercel project (`app.bandroadie.com/privacy`, `app.bandroadie.com/support`).

### Webflow export
Neither `privacy.html` nor `support.html` is present in the Webflow export. The Webflow site does not include these pages.

### Decision: Copy both to `marketing/`
**Reason:** Apple App Store and Google Play Store require a publicly accessible privacy policy URL. This is commonly registered as `bandroadie.com/privacy`. Once `bandroadie.com` is served by the marketing project rather than the Flutter app project, `bandroadie.com/privacy` would return 404 unless the file is present in `marketing/`.

**Action:** The Engineer must copy (not move) both files:
- `web/privacy.html` → `marketing/privacy.html`
- `web/support.html` → `marketing/support.html`

The originals in `web/` must not be deleted; `app.bandroadie.com/privacy` and `app.bandroadie.com/support` must continue to work.

---

## 8. New Script: `tools/deploy_marketing.sh`

A dedicated deploy script is required because:
- No Flutter build step is needed (pure static files).
- No `--dart-define` credentials are required.
- The Vercel project is different from the `web` project.
- The root directory is `marketing/`, not `build/web/`.

```bash
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
```

---

## 9. Manual Vercel Steps (Tony Must Run)

These steps cannot be scripted because they require authentication in the Vercel dashboard and domain ownership transfers between projects. They must be run **after** the feature branch is merged to `main` and the marketing deploy has succeeded at least once.

### Step 1 — Create the Vercel project

```bash
cd /path/to/bandroadie/marketing
vercel link
# When prompted:
#   Set up and deploy? → Y
#   Which scope? → tholmes (or your team account)
#   Link to existing project? → N (create new)
#   Project name? → marketing   (or bandroadie-marketing)
#   Which directory? → ./  (current, i.e. marketing/)
```

This creates `marketing/.vercel/project.json` — commit this file to the repo.

### Step 2 — First deploy (preview, confirm it works)

```bash
./tools/deploy_marketing.sh --preview
```

Open the preview URL in a browser and verify the Webflow homepage renders correctly.

### Step 3 — Move domains in the Vercel dashboard

1. Go to **Vercel Dashboard → Projects → web (the Flutter app project)**.
2. Navigate to **Settings → Domains**.
3. **Remove** `bandroadie.com` from the `web` project.
4. **Remove** `www.bandroadie.com` from the `web` project (if present).
5. Go to **Projects → marketing (the new project)**.
6. Navigate to **Settings → Domains**.
7. **Add** `bandroadie.com`.
8. **Add** `www.bandroadie.com`.
9. Follow Vercel's DNS verification prompts (existing DNS records may already satisfy verification since the domain was previously on Vercel).

> **Important:** `app.bandroadie.com` must remain assigned to the `web` project. Do not remove it.

### Step 4 — Production deploy

```bash
./tools/deploy_marketing.sh
```

### Step 5 — Verify (see §11)

---

## 10. Forbidden Areas

The Engineer must not touch any of the following. Any modification to these files or directories is a blocking error.

| Path | Reason |
|------|--------|
| `lib/` (entire directory) | Flutter source — zero changes required |
| `lib/main.dart` | `_isMarketingHost()` removal is explicitly deferred |
| `lib/features/landing/` | Removal is explicitly deferred |
| `web/` (entire directory) | Flutter app web assets — must not be modified |
| `web/vercel.json` | App project Vercel config — must not change |
| `web/index.html` | Flutter app entry point |
| `web/privacy.html` | Must remain for `app.bandroadie.com/privacy` |
| `web/support.html` | Must remain for `app.bandroadie.com/support` |
| `supabase/` (entire directory) | No database or edge function changes |
| `ios/`, `android/`, `macos/` | Native platform files — unaffected |
| `pubspec.yaml` | No new dependencies |
| `analysis_options.yaml` | Dart analysis config |
| `test/` | No test changes |

---

## 11. Verification Plan

Run these checks **after** domains have been migrated and `deploy_marketing.sh` has run in production mode.

### 11.1 — bandroadie.com serves the Webflow site

1. Open `https://bandroadie.com` in an **incognito** browser window.  
   **Expected:** Webflow marketing homepage renders. BandRoadie hero, App Store / Play Store badges visible.

2. Open `https://www.bandroadie.com`.  
   **Expected:** Same Webflow homepage (not a redirect error).

3. Open `https://bandroadie.com/changelog`.  
   **Expected:** Changelog page renders (cleanUrls resolved correctly).

4. Open `https://bandroadie.com/privacy`.  
   **Expected:** Privacy policy page renders.

5. Open `https://bandroadie.com/support`.  
   **Expected:** Support page renders.

6. Open `https://bandroadie.com/nonexistent-path`.  
   **Expected:** Custom Webflow 404 page renders (not a Vercel generic 404).

### 11.2 — app.bandroadie.com is unaffected

7. Open `https://app.bandroadie.com` in incognito.  
   **Expected:** Flutter app loads — shows the login / auth gate screen.

8. Open `https://app.bandroadie.com/auth/confirm` (will 404 without valid token — that is acceptable).  
   **Expected:** Flutter app loads; page does not error catastrophically. Supabase auth confirm handler is reachable.

9. Trigger a real magic-link login and confirm the email. Clicking the link must redirect to `https://app.bandroadie.com/auth/confirm?...`.  
   **Expected:** Auth completes and app loads with user session.

10. Open `https://app.bandroadie.com/privacy`.  
    **Expected:** Privacy policy page still serves from the Flutter app project.

### 11.3 — deploy_web.sh no longer aliases bandroadie.com

11. Inspect `tools/deploy_web.sh` in the diff.  
    **Expected:** Zero occurrences of `bandroadie.com` in alias commands.

12. Run a preview deploy: `./tools/deploy_web.sh --preview`.  
    **Expected:** No alias commands execute in preview mode; bandroadie.com is not altered.

---

## 12. System Impact Summary

| System | Impact |
|--------|--------|
| Marketing site (bandroadie.com) | **Changed** — served from new Vercel project |
| Flutter app (app.bandroadie.com) | **Unaffected** — same project, same build, same domain |
| Supabase auth redirect | **Unaffected** — still `https://app.bandroadie.com/auth/confirm` |
| iOS / Android native apps | **Unaffected** — no Flutter changes |
| Setlists / Catalog | **Unaffected** |
| Gigs / Rehearsals | **Unaffected** |
| Push notifications | **Unaffected** |
| `_isMarketingHost()` | **Dead code after migration** — not removed (deferred) |

---

## 13. Files Modified Summary

| File | Action |
|------|--------|
| `marketing/` | **CREATE** — new directory |
| `marketing/vercel.json` | **CREATE** — new file (see §5) |
| `marketing/index.html` | **CREATE** — from Webflow export (update `data-wf-domain`) |
| `marketing/404.html` | **CREATE** — from Webflow export |
| `marketing/changelog.html` | **CREATE** — from Webflow export |
| `marketing/_downloads.html` | **CREATE** — from Webflow export |
| `marketing/license.html` | **CREATE** — from Webflow export |
| `marketing/style-guide.html` | **CREATE** — from Webflow export |
| `marketing/images/` | **CREATE** — all 26 image files from Webflow export |
| `marketing/privacy.html` | **CREATE** — copy of `web/privacy.html` |
| `marketing/support.html` | **CREATE** — copy of `web/support.html` |
| `tools/deploy_marketing.sh` | **CREATE** — new deploy script |
| `tools/deploy_web.sh` | **MODIFY** — remove 2 `bandroadie.com` alias lines |

**Total files modified in existing source:** 1 (`tools/deploy_web.sh`)  
**Total new files:** 12 + image directory contents

---

*Plan complete. Awaiting Engineer implementation.*
