# Architect Plan: Google Fonts Runtime Fetch Bug Fix

## Feature Slug

`bug/google-fonts-runtime-fetch`

---

## Problem Summary

The `google_fonts` package is fetching font assets over HTTP at runtime from fonts.gstatic.com instead of loading them from local app bundle assets. This occurs because:

1. No `fonts:` section exists in `pubspec.yaml`
2. `GoogleFonts.config.allowRuntimeFetching` is never set to `false`

The default behavior of the google_fonts package when a font is not bundled locally is to download it over HTTP on first use. On web, this causes an extra network round-trip on cold load and potential FOUT (Flash of Unstyled Text) / layout shift. The package's own documentation explicitly discourages this for production apps in favor of bundling specific weights as local assets.

**Impact:** Web platform (primary) — visible on every cold/incognito load. Also applies to iOS/Android/macOS on first use, though device-level caching makes repeat-visit impact less visible.

---

## Root Cause

**Confidence Level:** HIGH (confirmed in code)

The google_fonts package defaults to runtime HTTP fetching when:

- The font is not found in a local `fonts:` section in `pubspec.yaml`
- `GoogleFonts.config.allowRuntimeFetching` has not been explicitly set to `false`

**Evidence:**

- `pubspec.yaml` (line 77-82): no `fonts:` section exists
- `lib/` directory: grep confirms no `GoogleFonts.config` call exists
- 7 files use `GoogleFonts.*` calls:
  1. `lib/features/setlists/services/setlist_print_service.dart` (PDF generation: PdfGoogleFonts)
  2. `lib/features/setlists/widgets/empty_setlists_state.dart`
  3. `lib/features/home/widgets/rehearsal_card.dart`
  4. `lib/features/home/widgets/potential_gig_card.dart`
  5. `lib/features/home/widgets/empty_section_card.dart`
  6. `lib/app/theme/design_tokens.dart`
  7. `lib/app/theme/app_theme.dart`

All of these files call GoogleFonts methods without bundled font assets, triggering runtime fetches on first use.

---

## Package Source Verification

**Investigation performed:** 2026-07-23  
**Packages inspected:** `google_fonts` 8.0.0, `printing` 5.14.2  
**Location:** `~/.pub-cache/hosted/pub.dev/`

### Key Findings

**`google_fonts` package (for UI):**

- **Does NOT check Flutter's `fonts:` section**
- Checks `AssetManifest` for files matching pattern `{Family}-{Variant}.ttf` (e.g., `DM Sans-Regular.ttf`)
- Implementation: `google_fonts_base.dart:128-206` (`loadFontIfNecessary` function)
  - Line 144-155: Checks asset bundle via `findFamilyWithVariantAssetPath()`
  - Line 157-165: Checks device file system cache
  - Line 168-182: Falls back to HTTP fetch if `allowRuntimeFetching` is true
- Filename matching: `google_fonts_base.dart:307-334` searches manifest for files ending with API filename prefix
- Variant naming: `google_fonts_variant.dart:119-128` converts FontWeight/FontStyle to filename parts (e.g., w400 → "Regular", w600 → "SemiBold")

**`printing` package (for PDF):**

- **Does NOT check Flutter's `fonts:` section**
- Expects assets at fixed path: `google_fonts/{name}.ttf` (e.g., `google_fonts/NotoSans-Regular.ttf`)
- Implementation: `fonts/font.dart:38-64` (`DownloadableFont.getFont` method)
  - Line 42: Default `assetPrefix` is `'google_fonts/'`
  - Line 46-54: Checks `AssetManifest.contains('$assetPrefix$name.ttf')`
  - Line 56-64: Falls back to HTTP fetch via cache if not found

**Critical Flutter fact:** Files in `pubspec.yaml` `fonts:` section do **NOT** appear in `AssetManifest` — only files in `assets:` do. The `fonts:` section creates a TextStyle fontFamily registry, which the `google_fonts` and `printing` packages do not query.

**Conclusion:** Original plan assumption was incorrect. Adding a `fonts:` section does NOT make these packages use local fonts automatically. Code changes are required to use standard Flutter font APIs.

---

## Reference Docs Consulted

Not applicable — this is a font bundling configuration issue, not a domain-specific feature.

---

## Existing System Analysis

### Current Behavior

1. App initializes with `google_fonts: ^8.0.0` dependency declared
2. UI code calls `GoogleFonts.dmSans(...)` for text styling (6 files)
3. PDF service calls `PdfGoogleFonts.notoSans*()` for PDF generation (1 file)
4. On first render, google_fonts package checks for local font assets in `pubspec.yaml`
5. No fonts are found locally → package downloads font files over HTTP from fonts.gstatic.com
6. On web: visible network request on cold load, potential FOUT/layout shift
7. On native platforms: same fetch occurs on first use, then cached locally by OS

### Exact Font Usage

**Flutter UI (DM Sans family):**

- **DM Sans 400 (Regular)** — used in callout and caption text styles (design_tokens.dart)
- **DM Sans 600 (SemiBold)** — heavily used across card widgets, buttons, labels, metadata
- **DM Sans 700 (Bold)** — used for titles, headers, emphasized text

**PDF Generation (Noto Sans family):**

- **Noto Sans Regular (400)** — base PDF text
- **Noto Sans Bold (700)** — bold PDF text
- **Noto Sans Italic (400 italic)** — italic PDF text
- **Noto Sans Bold Italic (700 italic)** — bold italic PDF text

---

## Proposed Solution

**Bundle fonts locally and update code to use them**, eliminating runtime HTTP dependency.

### Approach: Standard Flutter Font Bundling with Code Updates (REQUIRED)

**Verified mechanism (from package source inspection):**

The `google_fonts` package checks Flutter's `AssetManifest` for specific filename patterns (e.g., `DM Sans-Regular.ttf`), **NOT** the `fonts:` section. However, `AssetManifest` only includes files from `assets:`, not `fonts:`. Therefore, to eliminate HTTP fetching:

1. **For UI code:** Replace `GoogleFonts.dmSans(...)` calls with `TextStyle(fontFamily: 'DM Sans', ...)` and use standard `fonts:` section
2. **For PDF code:** Replace `PdfGoogleFonts.notoSans*()` calls with direct `pw.Font.ttf(await rootBundle.load(...))` from bundled assets

**Why this approach:**

1. **Performance**: Eliminates network round-trip on cold load (fastest possible load time)
2. **User experience**: No FOUT or layout shift — fonts render immediately
3. **Offline capability**: Works without network connection
4. **Minimal cost**: Only 7 font files needed (~500KB total), negligible bundle size increase
5. **Branding consistency**: DM Sans is a core branding element used throughout the app
6. **Standard Flutter pattern**: Uses Flutter's native font system instead of google_fonts dynamic loading

**Why code changes are necessary:**

The google_fonts package's `loadFontIfNecessary()` function (source: `google_fonts-8.0.0/lib/src/google_fonts_base.dart:144-155`) checks `AssetManifest` for files matching `{Family}-{Variant}.ttf` patterns, which requires files in `assets:`, not `fonts:`. Since we're using the standard `fonts:` section, we must replace the `GoogleFonts.*()` helper calls with standard Flutter `TextStyle(fontFamily: ...)` to use the bundled fonts.

The printing package's `PdfGoogleFonts` class (source: `printing-5.14.2/lib/src/fonts/font.dart:46-54`) expects assets at path `google_fonts/{name}.ttf`, which also doesn't match the standard `fonts:` section structure. Direct `pw.Font.ttf()` loading is cleaner.

### Implementation Steps

1. **Download font files from Google Fonts** (Engineer task):
   - DM Sans: weights 400, 600, 700 (Regular, SemiBold, Bold)
   - Noto Sans: Regular, Bold, Italic, Bold Italic
   - Total: 7 font files in TTF format

2. **Add font files to project** (Engineer task):
   - Create `assets/fonts/` directory
   - Place downloaded font files in `assets/fonts/`

3. **Declare fonts in pubspec.yaml** (Engineer task):
   - Add `fonts:` section referencing all 7 font files
   - Follow standard Flutter font asset syntax

4. **Update Dart code** (Engineer task):
   - **6 UI files:** Replace `GoogleFonts.dmSans(...)` → `TextStyle(fontFamily: 'DM Sans', fontWeight: ...)`
   - **1 PDF file:** Replace `PdfGoogleFonts.notoSans*()` → `pw.Font.ttf(await rootBundle.load(...))`

5. **Verification** (Engineer + QA task):
   - Run app on web with DevTools Network tab open
   - Confirm NO requests to fonts.gstatic.com on cold load
   - Visual check: fonts render correctly across all screens
   - Test on iOS/Android: fonts render correctly, no fetch on first use

---

## Database Impact

**Not applicable** — this is a client-side asset bundling change only.

---

## Flutter Architecture Changes

**Code changes required** — replacing dynamic font loading with static bundled fonts.

**Affected layers:**

- Asset bundling: `pubspec.yaml` fonts section (new)
- UI layer: 6 files using `GoogleFonts.dmSans(...)` → replace with `TextStyle(fontFamily: 'DM Sans', ...)`
- PDF service layer: 1 file using `PdfGoogleFonts.notoSans*()` → replace with direct `pw.Font.ttf()` loading

**Rationale for code changes:**

Package source inspection confirms:
- `google_fonts` package checks `AssetManifest` for filename patterns like `{Family}-{Variant}.ttf`, which requires `assets:` section, not `fonts:` section (source: `google_fonts-8.0.0/lib/src/google_fonts_base.dart:144-155`)
- `printing` package's `PdfGoogleFonts` expects assets at `google_fonts/{name}.ttf` path (source: `printing-5.14.2/lib/src/fonts/font.dart:46-54`)
- Flutter's `fonts:` section does NOT populate `AssetManifest` — only `assets:` does

**Solution:** Use Flutter's standard font bundling mechanism (`fonts:` section) and replace the dynamic helper calls with standard Flutter font APIs

---

## Files to Create

| File Path                              | Justification                                               |
| -------------------------------------- | ----------------------------------------------------------- |
| `assets/fonts/DMSans-Regular.ttf`      | DM Sans weight 400 (Regular) — used in callout/caption text |
| `assets/fonts/DMSans-SemiBold.ttf`     | DM Sans weight 600 (SemiBold) — heavily used across UI      |
| `assets/fonts/DMSans-Bold.ttf`         | DM Sans weight 700 (Bold) — used in titles/headers          |
| `assets/fonts/NotoSans-Regular.ttf`    | Noto Sans Regular — PDF generation base text                |
| `assets/fonts/NotoSans-Bold.ttf`       | Noto Sans Bold — PDF generation bold text                   |
| `assets/fonts/NotoSans-Italic.ttf`     | Noto Sans Italic — PDF generation italic text               |
| `assets/fonts/NotoSans-BoldItalic.ttf` | Noto Sans Bold Italic — PDF generation bold italic          |
| `assets/fonts/` (directory)            | Container for all font files                                |

---

## Files to Modify

| File                                                             | What Changes                                                                                                                              |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `pubspec.yaml`                                                   | Add `fonts:` section declaring all 7 font files under the existing `flutter:` section                                                    |
| `lib/app/theme/design_tokens.dart`                              | Replace `GoogleFonts.dmSans(...)` → `TextStyle(fontFamily: 'DM Sans', fontWeight: ...)` in callout/caption text style definitions        |
| `lib/app/theme/app_theme.dart`                                  | Replace `GoogleFonts.dmSans(...)` → `TextStyle(fontFamily: 'DM Sans', fontWeight: ...)` in theme definitions                             |
| `lib/features/setlists/widgets/empty_setlists_state.dart`       | Replace `GoogleFonts.dmSans(...)` → `TextStyle(fontFamily: 'DM Sans', fontWeight: ...)` in widget text styling                           |
| `lib/features/home/widgets/rehearsal_card.dart`                 | Replace `GoogleFonts.dmSans(...)` → `TextStyle(fontFamily: 'DM Sans', fontWeight: ...)` in card text styling                             |
| `lib/features/home/widgets/potential_gig_card.dart`             | Replace `GoogleFonts.dmSans(...)` → `TextStyle(fontFamily: 'DM Sans', fontWeight: ...)` in card text styling                             |
| `lib/features/home/widgets/empty_section_card.dart`             | Replace `GoogleFonts.dmSans(...)` → `TextStyle(fontFamily: 'DM Sans', fontWeight: ...)` in card text styling                             |
| `lib/features/setlists/services/setlist_print_service.dart`     | Replace `PdfGoogleFonts.notoSansRegular()` → `pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))` (and all variants) |

---

## Files Off-Limits

| File                | Reason                                              |
| ------------------- | --------------------------------------------------- |
| `lib/main.dart`     | Initialization order must not change                |
| `pubspec.lock`      | Auto-generated, must not be manually edited         |
| All other Dart files | Only the 7 files listed in "Files to Modify" should be touched |

---

## System Impact Map

| System                                 | Impact                                                                                                                       |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected (fonts render correctly with bundled assets)                                                                      |
| Rehearsals                             | unaffected (fonts render correctly with bundled assets)                                                                      |
| Setlists / Catalog                     | unaffected (fonts render correctly with bundled assets)                                                                      |
| Members / RBAC                         | unaffected                                                                                                                   |
| Auth / Session                         | unaffected                                                                                                                   |
| Routing                                | unaffected                                                                                                                   |
| Notifications                          | unaffected                                                                                                                   |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms benefit from local font loading; web sees biggest improvement (eliminates cold-load HTTP fetch) |

---

## Regression Risk

**Level:** LOW-MEDIUM

**Rationale:**

- Asset configuration change + straightforward code replacements
- Risk: Font rendering changes if TextStyle attributes (weight, style) don't match exactly
- Risk: PDF generation could fail if font loading fails or paths are wrong
- Mitigated by: Direct 1:1 replacement of existing font calls with equivalent standard Flutter APIs
- Easy to verify: visual inspection + DevTools Network tab check
- Rollback: revert code changes and remove fonts section from pubspec.yaml

**Testing scope:**

- Visual pass across all major screens (Home, Setlists, Gigs, Rehearsals, Settings)
- PDF generation verification (setlist print preview must render correctly)
- Web cold-load network check (no fonts.gstatic.com requests)
- iOS/Android first-launch check (fonts render immediately)
- Font weight/style verification (ensure DM Sans 400, 600, 700 render as before)

**Increased risk vs. original plan:** Original plan assumed no code changes, but package source inspection proved that assumption wrong. Current plan involves 7 file modifications, increasing surface area. However, changes are mechanical (direct API replacements) with no logic changes.

---

## Engineer Task Breakdown

Execute in strict order:

1. **Download font files from Google Fonts**
   - Navigate to https://fonts.google.com/
   - Download DM Sans: select weights 400, 600, 700 → download TTF files
   - Download Noto Sans: select Regular, Bold, Italic, Bold Italic → download TTF files
   - Total: 7 TTF files

2. **Create assets directory structure**
   - Create `assets/fonts/` directory in project root
   - Place all 7 downloaded TTF files in `assets/fonts/`

3. **Update pubspec.yaml**
   - Add `fonts:` section under the existing `flutter:` block
   - Declare all 7 font files with correct family names and weights
   - Syntax:
     ```yaml
     fonts:
       - family: DM Sans
         fonts:
           - asset: assets/fonts/DMSans-Regular.ttf
             weight: 400
           - asset: assets/fonts/DMSans-SemiBold.ttf
             weight: 600
           - asset: assets/fonts/DMSans-Bold.ttf
             weight: 700
       - family: Noto Sans
         fonts:
           - asset: assets/fonts/NotoSans-Regular.ttf
           - asset: assets/fonts/NotoSans-Bold.ttf
             weight: 700
           - asset: assets/fonts/NotoSans-Italic.ttf
             style: italic
           - asset: assets/fonts/NotoSans-BoldItalic.ttf
             weight: 700
             style: italic
     ```

4. **Update UI files — Replace GoogleFonts calls**
   - For each of the 6 UI files:
     - Find all `GoogleFonts.dmSans(...)` calls
     - Replace with `TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.wXXX)`
     - Preserve all other style attributes (fontSize, color, letterSpacing, etc.)
   - Files to update:
     - `lib/app/theme/design_tokens.dart`
     - `lib/app/theme/app_theme.dart`
     - `lib/features/setlists/widgets/empty_setlists_state.dart`
     - `lib/features/home/widgets/rehearsal_card.dart`
     - `lib/features/home/widgets/potential_gig_card.dart`
     - `lib/features/home/widgets/empty_section_card.dart`

5. **Update PDF service — Replace PdfGoogleFonts calls**
   - File: `lib/features/setlists/services/setlist_print_service.dart`
   - Replace:
     - `await PdfGoogleFonts.notoSansRegular()` → `pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'))`
     - `await PdfGoogleFonts.notoSansBold()` → `pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'))`
     - `await PdfGoogleFonts.notoSansItalic()` → `pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Italic.ttf'))`
     - `await PdfGoogleFonts.notoSansBoldItalic()` → `pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-BoldItalic.ttf'))`
   - Ensure `rootBundle` is imported: `import 'package:flutter/services.dart';`

6. **Run flutter pub get**
   - Execute: `flutter pub get`
   - Verify: no errors related to font asset paths

7. **Build and run app on web**
   - Execute: `flutter run -d chrome`
   - Open DevTools → Network tab
   - Perform a hard refresh (clear cache)
   - Verify: NO requests to fonts.gstatic.com appear

8. **Visual verification pass**
   - Navigate through all major screens: Home, Setlists, Gigs, Rehearsals, Settings
   - Check that DM Sans renders correctly (titles, labels, buttons)
   - Generate a setlist PDF preview
   - Check that Noto Sans renders correctly in PDF output

9. **Test on iOS/Android (optional but recommended)**
   - Build and run on a physical device or simulator
   - Verify fonts render correctly on first launch
   - No network fetch should occur (check with network monitor if available)

---

## Verification Plan

### Tier 1 — Pre-deployment (N/A)

Not applicable — no database or backend changes.

### Tier 2 — Post-deployment (after `flutter pub get`)

**POST-DEPLOY TEST 1: Verify font files exist in assets/**

```bash
# Manual check
ls -la assets/fonts/

# Expected: 7 TTF files present
# DMSans-Regular.ttf
# DMSans-SemiBold.ttf
# DMSans-Bold.ttf
# NotoSans-Regular.ttf
# NotoSans-Bold.ttf
# NotoSans-Italic.ttf
# NotoSans-BoldItalic.ttf
```

**POST-DEPLOY TEST 2: Verify pubspec.yaml fonts section**

```bash
# Manual check
grep -A 20 "fonts:" pubspec.yaml

# Expected: fonts: section exists with 7 font declarations under 2 families
```

**POST-DEPLOY TEST 3: Verify no runtime font fetching on web**

```bash
# Manual check in Chrome DevTools
# 1. Open app in Chrome with DevTools Network tab
# 2. Hard refresh (Cmd+Shift+R / Ctrl+Shift+R)
# 3. Filter network requests by "gstatic"
# 4. Verify: ZERO requests to fonts.gstatic.com
```

**POST-DEPLOY TEST 4: Visual regression check**

```bash
# Manual visual inspection
# 1. Navigate to Home screen → verify rehearsal cards, gig cards, section headers render with DM Sans
# 2. Navigate to Setlists screen → verify setlist cards, empty state text renders with DM Sans
# 3. Navigate to Settings screen → verify all labels and buttons render with DM Sans
# 4. Generate a setlist PDF → verify PDF renders with Noto Sans (no placeholder glyphs)
# 5. Compare rendered fonts against pre-fix screenshots (if available) — fonts should look identical
```

---

## QA Regression Areas

QA must specifically test the following areas to confirm no visual regressions:

### Primary Verification (Must Pass)

1. **Web cold-load performance**
   - Open app in incognito browser
   - Open DevTools Network tab
   - Load Home screen
   - **Verify:** No requests to fonts.gstatic.com
   - **Verify:** Fonts render immediately (no FOUT)

2. **Font rendering accuracy**
   - **DM Sans weight 400:** Check callout text, captions
   - **DM Sans weight 600:** Check buttons, labels, card metadata
   - **DM Sans weight 700:** Check page titles, section headers, emphasized text
   - **Noto Sans PDF:** Generate setlist PDF, verify no placeholder/missing glyphs

3. **Platform coverage**
   - **Web:** Chrome, Safari, Firefox (if time permits)
   - **iOS:** Simulator or device
   - **Android:** Emulator or device (if time permits)
   - **macOS:** Desktop app (if time permits)

### Regression Testing (Spot Check)

4. **Visual consistency across major screens**
   - Home screen: rehearsal cards, gig cards, quick actions
   - Setlists screen: setlist cards, empty state
   - Catalog screen: song cards, add song flow
   - Settings screen: all labels and toggle text
   - Modals: create gig, create rehearsal, edit member

5. **Edge cases**
   - Long text truncation (does ellipsis render correctly?)
   - Unicode/emoji rendering (do special characters still work?)
   - Dark/light mode (if light mode is supported)

---

## Rollout / Migration Strategy

**Not applicable** — this is an immediate deploy change.

**Rollback:** If fonts render incorrectly after deploy, rollback is trivial:

1. Remove `fonts:` section from pubspec.yaml
2. Run `flutter pub get`
3. Rebuild and deploy

**Monitoring:** After deploy, check web analytics for any spike in fonts.gstatic.com requests (should drop to zero). No backend monitoring required.

---

## Out of Scope

- Adding additional font weights beyond what's currently in use (400, 600, 700 for DM Sans)
- Switching to a different font family (DM Sans and Noto Sans are established branding)
- Optimizing font file size (variable fonts, subsetting) — out of scope for this bug fix
- Preloading fonts in the HTML head tag (web-specific optimization, not required)
- Using the `google_fonts` package's asset auto-detection mechanism (package source inspection confirmed it requires `assets:` section, not `fonts:`, making standard Flutter fonts approach cleaner)
