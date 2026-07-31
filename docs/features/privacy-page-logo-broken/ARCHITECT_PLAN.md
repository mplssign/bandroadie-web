# Architect Plan

## Feature Slug

`bug/privacy-page-logo-broken`

## Problem Summary

The logo image on the live marketing privacy policy page (`bandroadie.com/privacy`) fails to load. The HTML references a non-existent file at an incorrect path: `assets/images/bandroadie_logo_stacked.png`. The correct logo file exists at `marketing/images/BandRoadie_stencil_logo.png` and is used successfully on the homepage (`marketing/index.html`).

## Root Cause

**Confidence Level:** HIGH

**Primary Failure:** Incorrect image path and filename in `marketing/privacy.html` line 109.

**Analysis:**

Line 109 of `marketing/privacy.html` contains:

```html
<img src="assets/images/bandroadie_logo_stacked.png" alt="Band Roadie" />
```

Two errors present:

1. **Wrong directory path:** `assets/images/` does not exist. The marketing site structure uses `images/` directly (no `assets/` parent folder).

2. **Wrong filename:** `bandroadie_logo_stacked.png` does not exist. The actual logo file is named `BandRoadie_stencil_logo.png` (with capital B).

**Verified evidence:**

- Directory listing of `marketing/images/` shows `BandRoadie_stencil_logo.png` exists (confirmed via `list_dir`)
- `marketing/index.html` lines 61 and 149 correctly reference `images/BandRoadie_stencil_logo.png` — logo displays properly on homepage
- No `assets/` directory exists in `marketing/` folder
- No `bandroadie_logo_stacked.png` file exists anywhere in marketing directory

**Scope:** Isolated to `marketing/privacy.html` only. No other marketing pages are affected. The Flutter app's `PrivacyPolicyScreen` uses a completely different logo system (`BandRoadieLogo` widget with SVG asset from Flutter assets) and is not affected.

## Reference Docs Consulted

- `docs/agents/PROJECT_CONTEXT.md` — Hosting and Domain Architecture section confirms `marketing/` is a static Webflow export served by separate Vercel project at `bandroadie.com`
- `docs/agents/GUARDRAILS.md` — Code change discipline
- `docs/agents/OPERATING_MODEL.md` — Feature pipeline and roles

No notification domain reference docs exist or are applicable.

## Existing System Analysis

**Current behavior:**

1. User navigates to `https://bandroadie.com/privacy` or `https://www.bandroadie.com/privacy`
2. Request routed to Vercel `marketing` project (separate from Flutter app)
3. Static `marketing/privacy.html` returned
4. Browser attempts to load logo from relative path `assets/images/bandroadie_logo_stacked.png`
5. **404 response** — file does not exist at that path
6. Logo displays as broken image

**Verified working reference (homepage):**

`marketing/index.html` line 61:

```html
<img
  src="images/BandRoadie_stencil_logo.png"
  alt="BandRoadie"
  width="800"
  height="200"
  decoding="async"
/>
```

This path resolves correctly to `https://bandroadie.com/images/BandRoadie_stencil_logo.png` and displays properly.

**Data flow:**

```
User request (bandroadie.com/privacy)
  ↓
Vercel `marketing` project
  ↓
marketing/privacy.html served
  ↓
Browser parses HTML, encounters <img src="assets/images/bandroadie_logo_stacked.png">
  ↓
Browser sends GET request for https://bandroadie.com/assets/images/bandroadie_logo_stacked.png
  ↓
404 Not Found — file does not exist
  ↓
Broken image displayed
```

## Proposed Solution

**Change:** Correct the logo image path and filename in `marketing/privacy.html` line 109 to match the working pattern used on the homepage.

**Implementation:**

Replace line 109:

```html
<img src="assets/images/bandroadie_logo_stacked.png" alt="Band Roadie" />
```

With:

```html
<img
  src="images/BandRoadie_stencil_logo.png"
  alt="BandRoadie"
  width="800"
  height="200"
  decoding="async"
/>
```

**Rationale:**

1. Corrects directory path: `assets/images/` → `images/` (matches actual structure)
2. Corrects filename: `bandroadie_logo_stacked.png` → `BandRoadie_stencil_logo.png` (matches existing file)
3. Adds `width`, `height`, and `decoding` attributes for consistency with homepage implementation (line 61)
4. Matches working pattern already deployed and verified on production homepage

**Why this is minimal and safe:**

- Single line change in one file
- Copies proven working pattern from homepage (zero new risk)
- No CSS, JavaScript, or routing changes
- No other marketing pages affected
- Zero Flutter code changes (app's privacy screen unaffected)

## Database Impact

**Not applicable** — this is a static HTML file change. No database, migration, RLS, RPC, trigger, or backend involvement.

## Flutter Architecture Changes

**Not applicable** — zero Flutter code changes. The issue is isolated to the static marketing site HTML. The Flutter app's `PrivacyPolicyScreen` (`lib/features/legal/privacy_policy_screen.dart`) uses the `BandRoadieLogo` widget with a different SVG asset (`assets/images/bandroadie_logo_rose_tag.svg`) and is not affected by this bug or its fix.

## Files to Create

**None.**

## Files to Modify

| File                     | Change Description                                                                                                                                                                                                              |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `marketing/privacy.html` | Line 109: Replace incorrect logo path `assets/images/bandroadie_logo_stacked.png` with correct path `images/BandRoadie_stencil_logo.png`. Add `width="800" height="200" decoding="async"` attributes to match homepage pattern. |

**Exact change required:**

**Before (line 109):**

```html
<img src="assets/images/bandroadie_logo_stacked.png" alt="Band Roadie" />
```

**After (line 109):**

```html
<img
  src="images/BandRoadie_stencil_logo.png"
  alt="BandRoadie"
  width="800"
  height="200"
  decoding="async"
/>
```

## Files Off-Limits

| File                                            | Reason                                                                                   |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `marketing/index.html`                          | Working correctly — logo path is already correct                                         |
| `marketing/support.html`                        | Not affected — uses inline SVG, not image file                                           |
| `marketing/style.css`                           | No CSS changes needed                                                                    |
| `lib/features/legal/privacy_policy_screen.dart` | Flutter app privacy screen — separate system, uses `BandRoadieLogo` widget, not affected |
| `lib/features/landing/**`                       | Flutter landing page — served by separate `web` project, unreachable at bandroadie.com   |
| `web/privacy.html`                              | Dead duplicate — never served, intercepted by `web/vercel.json` rewrite                  |
| All other `marketing/*.html` files              | Not affected — privacy.html is only page with broken logo                                |

## System Impact Map

| System                                 | Impact                                                                        |
| -------------------------------------- | ----------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                    |
| Rehearsals                             | unaffected                                                                    |
| Setlists / Catalog                     | unaffected                                                                    |
| Members / RBAC                         | unaffected                                                                    |
| Auth / Session                         | unaffected                                                                    |
| Routing                                | unaffected                                                                    |
| Notifications                          | unaffected                                                                    |
| Platform (iOS / Android / Web / macOS) | unaffected — Flutter app uses different logo system                           |
| Marketing Site (static HTML)           | **affected** — `marketing/privacy.html` logo will display correctly after fix |
| SEO / Public Website                   | **affected** — broken image on SEO-indexed `/privacy` page will be resolved   |

## Regression Risk

**Level:** LOW

**Rationale:**

- Single static HTML file modified
- Single line change (logo `<img>` tag)
- Copies proven working pattern from homepage (production-verified for months)
- No code logic, no JavaScript, no CSS changes
- No routing or configuration changes
- No dependencies on other systems
- No shared components or includes affected
- Logo file already exists and is served correctly on homepage
- Change is purely corrective — restores intended behavior

**Potential regression vectors (all assessed as minimal risk):**

1. **Logo fails to load after fix:** Extremely unlikely — same path works on homepage, file existence verified
2. **Layout breaks:** Extremely unlikely — adding width/height/decoding attributes matches homepage pattern, no CSS changes
3. **Other marketing pages affected:** Not possible — privacy.html is isolated, no shared templates or includes modified

## Engineer Task Breakdown

**Task 1:** Modify `marketing/privacy.html` line 109

- Open `marketing/privacy.html`
- Locate line 109 inside `.logo-container` div (around line 109, inside `<body>` tag after opening style)
- Replace the entire `<img>` tag with corrected version matching homepage pattern
- Verify the change: search for `assets/images` in file — should return zero matches after change
- Verify the change: search for `BandRoadie_stencil_logo.png` in file — should return one match (the corrected line)

**Task 2:** Verify file integrity

- Open `marketing/privacy.html` in browser locally (or via `cat` command)
- Confirm line 109 now reads: `<img src="images/BandRoadie_stencil_logo.png" alt="BandRoadie" width="800" height="200" decoding="async"/>`
- Confirm no other `<img>` tags exist in the file
- Confirm no accidental formatting changes elsewhere in file

**Task 3:** Static validation

- Run `grep -n "assets/images" marketing/privacy.html` — should return empty (no matches)
- Run `grep -n "bandroadie_logo_stacked.png" marketing/privacy.html` — should return empty (no matches)
- Run `grep -n "BandRoadie_stencil_logo.png" marketing/privacy.html` — should return one match at line 109

**Task 4:** Git validation

- Run `git diff marketing/privacy.html`
- Verify exactly one line changed (line 109)
- Verify no other files modified
- Verify no whitespace or formatting changes elsewhere in file

**Task 5:** Complete implementation report

- Create `ENGINEER_REPORT.md` in `docs/features/privacy-page-logo-broken/`
- Document all four tasks as complete
- Include `git diff` output
- Note: `flutter analyze` not applicable (no Dart code changes)

## Verification Plan

**Tier 1 — Pre-deployment (local verification, no database/backend involved)**

**PRE-DEPLOY TEST 1: File existence check**

```bash
# Verify the logo file actually exists at the path we're correcting to
ls -lh marketing/images/BandRoadie_stencil_logo.png
# Expected: File exists, approximately 20-50KB (typical PNG logo size)
```

**PRE-DEPLOY TEST 2: Path audit**

```bash
# Verify no remaining incorrect "assets/images" references in privacy.html
grep -n "assets/images" marketing/privacy.html
# Expected: Empty output (no matches)
```

**PRE-DEPLOY TEST 3: Filename audit**

```bash
# Verify no remaining incorrect "bandroadie_logo_stacked.png" references
grep -n "bandroadie_logo_stacked.png" marketing/privacy.html
# Expected: Empty output (no matches)
```

**PRE-DEPLOY TEST 4: Corrected path verification**

```bash
# Verify exactly one occurrence of corrected logo filename in privacy.html
grep -n "BandRoadie_stencil_logo.png" marketing/privacy.html
# Expected: Single match at line 109
```

**PRE-DEPLOY TEST 5: Homepage consistency check**

```bash
# Verify homepage uses same logo file (pattern we're copying)
grep -n "BandRoadie_stencil_logo.png" marketing/index.html
# Expected: Two matches (lines 61, 149) — confirms homepage uses same file
```

**PRE-DEPLOY TEST 6: Diff scope verification**

```bash
# Verify only one line changed, no incidental formatting changes
git diff marketing/privacy.html | grep -E '^[+-]' | grep -v '^[+-]{3}' | wc -l
# Expected: 2 (one deletion line, one addition line — single line change)
```

**PRE-DEPLOY TEST 7: No Flutter code touched**

```bash
# Verify no Dart files modified (app's privacy screen should be untouched)
git diff --name-only | grep -E '\.dart$'
# Expected: Empty output (no Dart files modified)
```

**Tier 2 — Post-deployment (live site verification after Vercel deploy)**

**POST-DEPLOY TEST 1: Live logo load verification**

```bash
# Verify logo file is accessible via HTTP from live marketing site
curl -I https://bandroadie.com/images/BandRoadie_stencil_logo.png
# Expected: HTTP 200 OK, Content-Type: image/png
```

**POST-DEPLOY TEST 2: Privacy page HTML source verification**

```bash
# Verify live privacy page HTML contains corrected logo path
curl -s https://bandroadie.com/privacy | grep -o 'images/BandRoadie_stencil_logo.png'
# Expected: Exact match found (confirms deploy succeeded and HTML is updated)
```

**POST-DEPLOY TEST 3: Visual inspection**

- Navigate to `https://bandroadie.com/privacy` in browser (incognito mode)
- Verify logo displays correctly at top of page
- Verify no broken image icon or missing alt text
- Visual comparison: logo should match appearance on `https://bandroadie.com/` (homepage)

**POST-DEPLOY TEST 4: Cross-browser check** (if time permits)

- Test in Safari, Chrome, Firefox (desktop)
- Test on iOS Safari, Android Chrome (mobile)
- Verify logo displays consistently across browsers

**POST-DEPLOY TEST 5: App privacy screen unaffected**

- Navigate to `https://app.bandroadie.com/privacy` (Flutter app)
- Verify logo displays correctly (should be SVG-based `BandRoadieLogo` widget, unaffected by marketing site change)
- Confirm no visual regression in Flutter app

**POST-DEPLOY TEST 6: SEO/metadata unchanged**

```bash
# Verify meta tags, title, and structured data unchanged
curl -s https://bandroadie.com/privacy | grep -E '<title>|<meta name="description"'
# Expected: Title and description unchanged from before deployment
```

**Success Criteria:**

- All Tier 1 tests pass before deployment
- All Tier 2 tests pass after deployment
- Logo displays correctly on live `bandroadie.com/privacy`
- Zero visual or functional regressions on homepage or other marketing pages
- Flutter app's privacy screen unaffected

## Additional Context

**Marketing site architecture (from PROJECT_CONTEXT.md):**

The `marketing/` directory is a static Webflow export deployed to a separate Vercel project (`marketing`, project ID `prj_6XAVv0lp4ySiYWAoBTPaWgT52DzW`) serving `bandroadie.com` and `www.bandroadie.com`. It is completely independent from the Flutter `web` project serving `app.bandroadie.com`.

**Deployment:** After Engineer implementation and QA approval, deploy via:

```bash
./tools/deploy_marketing.sh
```

This script deploys the `marketing/` directory to the Vercel `marketing` project. **Do not use `./tools/deploy_web.sh`** — that deploys the Flutter app to a different Vercel project.

**Root cause timeline:**

Likely introduced during initial Webflow export or manual privacy page creation. The homepage (`index.html`) was created/exported correctly with proper logo path, but `privacy.html` was either:

1. Created from a different template/source with incorrect path assumptions, or
2. Hand-edited with incorrect path guessed without verifying file structure

This is not a regression from recent code changes — it is a pre-existing issue in the static marketing site that has persisted since the privacy page was added.

**No related issues found:**

- `marketing/support.html` uses inline SVG for logo (different approach, not affected)
- `marketing/index.html` uses correct logo path (working as expected)
- No other marketing pages reference the logo via `<img>` tag

**Flutter app isolation confirmed:**

`lib/features/legal/privacy_policy_screen.dart` uses `BandRoadieLogo` widget (lines 28-31) with SVG asset `assets/images/bandroadie_logo_rose_tag.svg`. This is Flutter's asset system, completely separate from marketing site static files. The Flutter app's privacy screen is unaffected by this bug and its fix.

---

## Implementation Authorization

This plan is approved for Engineer implementation. Proceed with Task 1 through Task 5 as specified above.
