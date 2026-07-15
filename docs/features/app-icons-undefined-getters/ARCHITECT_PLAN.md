# ARCHITECT_PLAN.md

## Feature Slug

`bug/app-icons-undefined-getters`

---

## Problem Summary

The app fails to compile on all platforms with 5 hard compile-time errors (`undefined_getter`) in `lib/features/setlists/widgets/song_details_bottom_sheet.dart`. The file references `AppIcons.spotify`, `AppIcons.appleMusic`, `AppIcons.amazonMusic`, `AppIcons.pdf`, and `AppIcons.link` — none of which exist in the `AppIcons` class. This is not a lint warning; it's a blocking `kernel_snapshot_program` build failure that prevents the app from being built or run on any platform.

---

## Root Cause

**Confidence: HIGH** (confirmed by direct code inspection and `flutter analyze` output)

The `feature/song-links-multi-type` branch (merged to `main` before `feature/song-notes-view-drawer` was created) added multi-type song link support with type-specific icon rendering. The Architect Plan for that feature (Task 6) instructed the Engineer to use raw `LucideIcons.*` references directly in helper methods. However, the Engineer attempted to follow the codebase convention documented in `lib/app/theme/app_icons.dart`:

> "Always use AppIcons._ instead of LucideIcons._ or Icons.\*"

The Engineer changed the implementation to reference `AppIcons.spotify`, `AppIcons.appleMusic`, `AppIcons.amazonMusic`, `AppIcons.pdf`, and `AppIcons.link` (instead of the raw Lucide icons suggested in the Architect Plan), but **failed to actually add these 5 static members to `app_icons.dart`**.

The Engineer Report for `feature/song-links-multi-type` falsely claimed these icons were added:

- **Line 41** (Files Modified section): _"Added `AppIcons.link` constant (LucideIcons.link) to Music/Setlists section"_
- **Line 42**: _"Added service-specific icons: `spotify` (disc3), `appleMusic` (music2), `amazonMusic` (radio), `pdf` (fileType)"_
- **Deviation #2**: _"added `AppIcons.link = LucideIcons.link` to the Music/Setlists section"_
- **Deviation #4**: _"Added four new icon constants to `AppIcons`: `spotify` (disc3), `appleMusic` (music2), `amazonMusic` (radio), and `pdf` (fileType)"_

None of these additions were actually made to `app_icons.dart` (verified via `grep` search showing zero matches for `static const IconData spotify`, `static const IconData link`, etc.).

**Evidence:**

1. `flutter analyze` on `main` produces 5 `undefined_getter` errors:
   - Line 663: `AppIcons.spotify`
   - Line 665: `AppIcons.appleMusic`
   - Line 667: `AppIcons.amazonMusic`
   - Line 673: `AppIcons.pdf`
   - Line 1089: `AppIcons.link`

2. `lib/app/theme/app_icons.dart` contains no definitions for `spotify`, `appleMusic`, `amazonMusic`, `pdf`, or `link` (verified via `grep` search).

3. The QA Report for `feature/song-notes-view-drawer` explicitly documented these as pre-existing errors unrelated to that feature (confirmed via `git stash` + `flutter analyze` comparison).

4. `./run.sh macos` fails with:
   ```
   Target kernel_snapshot_program failed: Exception
   Error: Member not found: 'spotify'
   ```

**Why all platforms are affected:**

Dart's frontend compiler (shared by iOS, Android, macOS, and Web) performs static analysis during the kernel snapshot generation phase. This phase occurs before any platform-specific compilation (Xcode, Gradle, etc.). Since these are **compile-time errors** (not runtime errors or lint warnings), the build fails early and no platform-specific artifacts are generated.

---

## Reference Docs Consulted

No domain-specific reference documentation exists for icons/assets in `docs/reference/`. This is a straightforward missing-code issue diagnosed via direct inspection of:

- `lib/app/theme/app_icons.dart` (reviewed in full — confirmed 5 members missing)
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart` (confirmed 5 call sites)
- `docs/features/song-links-multi-type/ARCHITECT_PLAN.md` (reviewed Task 6 icon mappings)
- `docs/features/song-links-multi-type/ENGINEER_REPORT.md` (confirmed false claim of adding icons)

---

## Existing System Analysis

### AppIcons Convention

`lib/app/theme/app_icons.dart` serves as the central icon registry for BandRoadie. File header comment (line 4):

> "Always use AppIcons._ instead of LucideIcons._ or Icons.\*"

All icons are defined as `static const IconData` members wrapping Lucide or Material icons. The file is organized into sections:

- Navigation (lines 10–26)
- Core Actions (lines 28–48)
- Status / Alerts (lines 50–58)
- **Music / Setlists (lines 60–82)** ← missing icons belong here
- Calendar / Events (lines 84–98)
- Users / Members (lines 100–116)
- Notifications (lines 118–126)
- System / Settings (lines 128–142)
- Media (lines 144–148)
- Marketing / Landing (lines 150–158)

### Current Icon Rendering in song_details_bottom_sheet.dart

The `_getIconForLinkType(SongLinkType type)` method (lines 658–678) maps link types to icons:

```dart
case SongLinkType.youtube:
  return Icons.play_circle_outline;  // ✅ Material icon (not via AppIcons)
case SongLinkType.spotify:
  return AppIcons.spotify;            // ❌ undefined
case SongLinkType.appleMusic:
  return AppIcons.appleMusic;         // ❌ undefined
case SongLinkType.amazonMusic:
  return AppIcons.amazonMusic;        // ❌ undefined
case SongLinkType.soundcloud:
  return LucideIcons.music;           // ✅ direct Lucide (pre-existing exception)
case SongLinkType.googleDocs:
  return LucideIcons.fileText;        // ✅ direct Lucide (pre-existing exception)
case SongLinkType.pdf:
  return AppIcons.pdf;                // ❌ undefined
case SongLinkType.googleSheets:
  return LucideIcons.table;           // ✅ direct Lucide (pre-existing exception)
case SongLinkType.generic:
  return AppIcons.globe;              // ✅ already exists (line 144 of app_icons.dart)
```

The "Add a link" button (line 1089) also references:

```dart
Icon(AppIcons.link, color: AppColors.primary, size: 16)  // ❌ undefined
```

### Why 4 link types use raw LucideIcons

The Architect Plan for `feature/song-links-multi-type` explicitly specified using raw `LucideIcons.*` for all music services and document types. The Engineer partially implemented this (4 types use raw Lucide icons), but changed 5 types to use `AppIcons.*` without adding the definitions. This inconsistency suggests the Engineer started refactoring to follow the convention but left it incomplete.

---

## Proposed Solution

**Minimal fix:** Add the 5 missing static members to `lib/app/theme/app_icons.dart` in the "Music / Setlists" section.

### Exact Code Addition

Insert after line 82 (`static const IconData library = LucideIcons.library;`) and before line 84 (the "Calendar / Events" section comment):

```dart
  // Song link types
  static const IconData spotify = LucideIcons.disc3;
  static const IconData appleMusic = LucideIcons.music2;
  static const IconData amazonMusic = LucideIcons.radio;
  static const IconData pdf = LucideIcons.fileType;
  static const IconData link = LucideIcons.link;
```

### Icon Mappings Rationale

These mappings use the distinct icons originally intended by the `feature/song-links-multi-type` Engineer (verified to exist in `lucide_flutter` v0.575.0):

| AppIcons Member | Lucide Icon            | Reason                                                                 |
| --------------- | ---------------------- | ---------------------------------------------------------------------- |
| `spotify`       | `LucideIcons.disc3`    | Disc icon (variant 3) — evokes vinyl/music media for streaming service |
| `appleMusic`    | `LucideIcons.music2`   | Music note icon (variant 2) — distinct from generic music icon         |
| `amazonMusic`   | `LucideIcons.radio`    | Radio icon — evokes broadcast/streaming service                        |
| `pdf`           | `LucideIcons.fileType` | File-type icon — more specific than generic fileText                   |
| `link`          | `LucideIcons.link`     | Generic hyperlink icon                                                 |

**Why distinct icons per service:**

- Visual differentiation: Each streaming service gets a unique icon shape, not just color
- Accessibility: Icon shape differences help users distinguish services without relying solely on color
- Original intent: The Engineer Report for `feature/song-links-multi-type` specified these exact icons (lines 42, Deviation #4)
- Verified availability: All 5 icons confirmed to exist in `lucide_flutter` v0.575.0 via package inspection

**Icon selection verification:**

```bash
# Confirmed via ~/.pub-cache/hosted/pub.dev/lucide_flutter-0.575.0/lib/src/icons.g.dart:
LucideIcons.disc3      ✓ (line search: "static const IconData disc3")
LucideIcons.music2     ✓ (line search: "static const IconData music2")
LucideIcons.radio      ✓ (line search: "static const IconData radio")
LucideIcons.fileType   ✓ (line search: "static const IconData fileType")
LucideIcons.link       ✓ (line search: "static const IconData link")
```

**Why not change call sites to use raw LucideIcons:**

- The codebase convention explicitly mandates `AppIcons.*` usage
- Changing call sites would be a larger diff and would violate the "Always use AppIcons.\*" rule
- The current call-site pattern is architecturally correct — only the definitions are missing

---

## Database Impact

**Not applicable.** This is a pure Dart/Flutter code issue with no database, RLS, RPC, migration, or edge function involvement.

---

## Flutter Architecture Changes

### State Management

No changes. This fix does not affect controllers, providers, or repositories.

### Models

No changes. `SongLink` and `SongLinkType` (created by `feature/song-links-multi-type`) are unaffected.

### Widgets

No changes. `song_details_bottom_sheet.dart` call sites are already correct and will compile once the `AppIcons` definitions exist.

### Theme

**Modified:** `lib/app/theme/app_icons.dart`

- Add 5 new static const members in Music/Setlists section
- Purely additive — no changes to existing definitions

---

## Files to Create

**None.**

---

## Files to Modify

| File                           | What changes                                                                                                                       |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `lib/app/theme/app_icons.dart` | Add 5 static const IconData members after line 82 in Music/Setlists section: `spotify`, `appleMusic`, `amazonMusic`, `pdf`, `link` |

---

## Files Off-Limits

| File                                                           | Reason                                                                           |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Call sites are already correct — changing them would violate AppIcons convention |
| `lib/main.dart`                                                | Init order must not change                                                       |
| `lib/features/setlists/links/song_link.dart`                   | Model is correct — no changes needed                                             |
| `lib/features/setlists/links/song_link_detector.dart`          | Detector logic is correct — no changes needed                                    |
| Any test files                                                 | No test coverage exists for this area (known debt)                               |

---

## System Impact Map

| System                                 | Impact                                                                                                      |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected — does not use song link icons                                                                   |
| Rehearsals                             | unaffected — does not use song link icons                                                                   |
| Setlists / Catalog                     | **affected** — song details bottom sheet uses these icons when rendering multi-type song links              |
| Members / RBAC                         | unaffected                                                                                                  |
| Auth / Session                         | unaffected                                                                                                  |
| Routing                                | unaffected                                                                                                  |
| Notifications                          | unaffected                                                                                                  |
| Platform (iOS / Android / Web / macOS) | **ALL affected (currently broken)** — compile-time error blocks kernel snapshot generation on all platforms |

---

## Regression Risk

**LOW**

**Rationale:**

- **Single-file change**: Only `app_icons.dart` is modified (5 new constant definitions)
- **Purely additive**: No existing definitions are changed or removed
- **No logic changes**: Only data (icon mappings) is added
- **Compile-time verification**: If the Lucide icon names are wrong, new compile errors will immediately surface (fail-fast)
- **Icons verified to exist**: All 5 Lucide icons (`disc3`, `music2`, `radio`, `fileType`, `link`) confirmed present in `lucide_flutter` v0.575.0 via package inspection
- **Call sites unchanged**: No changes to `song_details_bottom_sheet.dart` or any other file
- **No database, RLS, auth, routing, or initialization changes**
- **No platform-specific code**

**What could go wrong:**

1. **Wrong Lucide icon names used** → New compile errors (mitigated: all 5 icon names verified via direct package inspection of `~/.pub-cache/hosted/pub.dev/lucide_flutter-0.575.0/lib/src/icons.g.dart`)
2. **Icons placed in wrong section** → No functional impact, only organizational (mitigated: explicit line number placement in plan)

**Mitigation:**

- Engineer must verify `flutter analyze` passes with **0 errors** after the change
- Engineer must verify app builds successfully on at least one platform (macOS or web)

---

## Engineer Task Breakdown

Execute in strict order. Each task must be complete and verified before proceeding.

---

### Task 1 — Add Missing Icon Definitions to app_icons.dart

**File:** `lib/app/theme/app_icons.dart`

**Location:** After line 82 (`static const IconData library = LucideIcons.library;`), before line 84 (the `// =============================` comment that starts the Calendar/Events section).

**Code to insert:**

```dart

  // Song link types
  static const IconData amazonMusic = LucideIcons.radio;
  static const IconData appleMusic = LucideIcons.music2;
  static const IconData link = LucideIcons.link;
  static const IconData pdf = LucideIcons.fileType;
  static const IconData spotify = LucideIcons.disc3;
```

**Formatting requirements:**

- Blank line before the comment (to match existing section spacing)
- Comment uses standard section comment style (no leading `=====` separators for subsections)
- Each `static const` declaration indented by 2 spaces
- Icon names use camelCase (match `appleMusic`, not `apple_music`)
- Declarations sorted alphabetically by member name (not grouped by service type)

**Acceptance Criteria:**

- All 5 definitions added in a single contiguous block
- Placed in Music/Setlists section (not in a different section)
- Uses exact Lucide icon names verified to exist in `lucide_flutter` v0.575.0: `disc3`, `music2`, `radio`, `fileType`, `link`
- No extra blank lines within the group (only one blank line before the comment)
- Matches indentation and style of surrounding code

---

### Task 2 — Verify Compilation

**Command:**

```bash
flutter analyze
```

**Acceptance Criteria:**

- **0 errors** (down from 5 errors on `main`)
- The 5 `undefined_getter` errors for `AppIcons.spotify`, `AppIcons.appleMusic`, `AppIcons.amazonMusic`, `AppIcons.pdf`, and `AppIcons.link` are resolved
- The 4 pre-existing `deprecated_member_use` warnings remain unchanged (expected — unrelated to this fix)
- No new errors or warnings introduced

**If errors remain:**

- Verify Lucide icon names are spelled correctly: `LucideIcons.disc3`, `LucideIcons.music2`, `LucideIcons.radio`, `LucideIcons.fileType`, `LucideIcons.link`
- Verify `static const IconData` syntax is correct
- Verify no typos in member names (e.g., `appleMusic` not `AppleMusic`)

---

### Task 3 — Verify Build Success

**Command (choose one platform):**

```bash
./run.sh macos
```

or

```bash
flutter run -d chrome --web-renderer html
```

**Acceptance Criteria:**

- Build completes successfully (no `kernel_snapshot_program` failure)
- App launches and shows the home screen
- No runtime errors in console related to icons

**If build fails:**

- Re-run `flutter clean && flutter pub get` to clear any cached intermediate build artifacts
- Check for typos in Lucide icon names
- Verify imports at top of `app_icons.dart` include `package:lucide_flutter/lucide_flutter.dart`

---

### Task 4 — Manual Verification of Icon Rendering

**Test scenario:**

1. Open the app and navigate to a setlist (Catalog or any regular setlist)
2. Tap any song to open the song details bottom sheet
3. If the song has no links, tap "Add a link" — verify the button shows a link icon (not an error/missing icon)
4. Add a Spotify link (e.g., `https://open.spotify.com/track/test`)
   - Verify: Spotify music icon renders (not a missing icon box)
   - Verify: Icon color is Spotify green
5. Add an Apple Music link (e.g., `https://music.apple.com/us/album/test`)
   - Verify: Apple Music music icon renders
   - Verify: Icon color is Apple Music pink/red
6. Add a PDF link (e.g., `https://example.com/sheet.pdf`)
   - Verify: PDF file-text icon renders
   - Verify: Icon color is red
7. Add a generic link (e.g., `https://example.com`)
   - Verify: Generic globe icon renders (this already worked — `AppIcons.globe` existed)
   - Verify: Icon color is default text color

**Acceptance Criteria:**

- All link types render with correct icons (no missing icon boxes)
- Icon colors match service branding (colors are handled by `_getColorForLinkType()` — no changes needed)
- "Add a link" button shows a link icon

**If icons don't render:**

- Check browser console (web) or Xcode console (macOS) for errors
- Verify hot reload picked up the change (if testing with `flutter run`, do a hot restart: `R` in terminal)
- Verify no typos in Lucide icon names

---

### Task 5 — Produce ENGINEER_REPORT.md

**File:** `docs/features/app-icons-undefined-getters/ENGINEER_REPORT.md`

**Required sections:**

1. **Summary** — One paragraph: what was changed and why
2. **Changes Made** — Git diff summary for `app_icons.dart`
3. **Files Modified** — Table with file path and description
4. **Verification** — `flutter analyze` output (0 errors)
5. **Build Confirmation** — Platform tested (macOS or web) and result
6. **Manual Testing** — Icon rendering verification results
7. **Task Completion** — Table with all 5 Architect tasks marked COMPLETE

---

## Verification Plan

This is a compile-time fix with no database, RLS, or RPC involvement. Verification is purely build and UI rendering.

### Pre-Deployment Verification

**Not applicable.** No Supabase database changes or edge function deployments are involved.

### Post-Implementation Verification

**Test 1 — Compilation**

```bash
flutter analyze
```

**Expected output:**

- 0 errors (down from 5 errors on `main`)
- 4 info notices (`deprecated_member_use` warnings — pre-existing, unrelated)
- No `undefined_getter` errors for `AppIcons.spotify`, `AppIcons.appleMusic`, `AppIcons.amazonMusic`, `AppIcons.pdf`, or `AppIcons.link`

**Test 2 — Build Success**

```bash
flutter clean && flutter pub get && ./run.sh macos
```

**Expected result:**

- Build completes successfully
- App launches to home screen
- No `kernel_snapshot_program` errors

**Test 3 — Icon Rendering (Manual UI Test)**

| Link Type    | Test URL                                | Expected Icon       | Expected Color     |
| ------------ | --------------------------------------- | ------------------- | ------------------ |
| Spotify      | `https://open.spotify.com/track/test`   | Disc icon (disc3)   | Spotify green      |
| Apple Music  | `https://music.apple.com/us/album/test` | Music note (music2) | Apple pink/red     |
| Amazon Music | `https://music.amazon.com/albums/test`  | Radio icon          | Amazon blue        |
| PDF          | `https://example.com/leadsheet.pdf`     | File-type icon      | Red                |
| Generic      | `https://example.com`                   | Globe icon          | Default text color |
| Add button   | Tap "Add a link" button                 | Link icon           | Primary rose       |

**Test procedure:**

1. Open any setlist or Catalog
2. Tap a song to open song details bottom sheet
3. Tap "Add a link" — verify button icon
4. Add each link type above
5. Verify icon and color for each link

**Expected result:**

- All icons render correctly (no missing icon boxes)
- Colors match service branding
- No runtime errors in console

**Test 4 — Backward Compatibility**

If production data contains songs with existing YouTube, Spotify, Apple Music, Amazon Music, or PDF links (from the `feature/song-links-multi-type` deploy):

1. Open any song with existing links
2. Verify links render with correct icons
3. Tap each link — verify it opens in browser/native app

**Expected result:**

- Existing links render and function correctly
- No parsing errors or missing icons

---

## QA Regression Areas

QA must validate the following areas to confirm no regressions were introduced:

### Critical Path — Song Link Rendering

- **Link icon rendering**: All 9 link types (YouTube, Spotify, Apple Music, Amazon Music, SoundCloud, Google Docs, Google Sheets, PDF, generic) display with correct icons
- **Link icon differentiation**: Spotify (disc), Apple Music (music note), and Amazon Music (radio) icons are visually distinct shapes, not just different colors — verify icons are distinguishable even without color
- **Link colors**: Icons render with service-specific brand colors (Spotify green, Apple pink, etc.)
- **Add link button**: "Add a link" button displays link icon (not play icon)
- **Link tap behavior**: Tapping any link opens correct URL in browser/native app

### Setlist and Catalog Integrity

- **Song details open**: Song details bottom sheet opens without errors
- **Link add flow**: Adding new links via modal works correctly, type is auto-detected
- **Link delete flow**: Deleting links via X icon works correctly
- **Multiple links per song**: Songs with multiple links display all links correctly

### Cross-Platform Consistency

Test on **all platforms** (not just macOS):

| Platform | Test Requirement                       |
| -------- | -------------------------------------- |
| macOS    | Build succeeds, icons render correctly |
| iOS      | Build succeeds, icons render correctly |
| Android  | Build succeeds, icons render correctly |
| Web      | Build succeeds, icons render correctly |

**Why all platforms:** The bug was a compile-time error in Dart frontend compilation, which is shared across all platforms. While the fix is also platform-agnostic, QA must verify no platform-specific rendering issues exist.

### Backward Compatibility

- Songs with existing `youtube_links` data (JSON without `type` field) parse and render correctly
- No data migration is required — confirm existing production links work unchanged

---

## Rollout / Migration Strategy

**Not applicable.** This is a client-side code fix with no database schema changes, no data migrations, no edge function changes, and no configuration changes.

**Deployment:**

1. Engineer implements fix and produces `ENGINEER_REPORT.md`
2. QA validates and produces `QA_REPORT.md` with verdict
3. If QA verdict is **APPROVED**, Manager authorizes commit
4. Push to `main`
5. Deploy web via `./tools/deploy_web.sh` (standard web deployment)
6. No Supabase deployment required

**Post-deploy verification (web only):**

1. Open https://bandroadie.com in incognito
2. Log in and navigate to a setlist
3. Open any song details
4. Verify icons render correctly
5. Add a new Spotify link — verify icon and color

---

## Out of Scope

The following are explicitly **not** part of this fix:

1. **Refactoring `song_details_bottom_sheet.dart` to remove raw Lucide icon references** — The file currently uses raw `LucideIcons.*` for SoundCloud, Google Docs, and Google Sheets (not via `AppIcons.*`). This inconsistency is pre-existing and was introduced by `feature/song-links-multi-type`. Fixing it would require:
   - Adding `AppIcons.soundcloud`, `AppIcons.googleDocs`, `AppIcons.googleSheets` to `app_icons.dart`
   - Updating call sites in `song_details_bottom_sheet.dart`
   - This is a **separate architectural cleanup task**, not a bug fix

2. **Adding brand-specific logo assets** — The current solution uses distinct Lucide icons (`disc3`, `music2`, `radio`, `fileType`, `link`) with service-specific brand colors. These provide visual differentiation between services via icon shape + color. Actual brand logos (Spotify logo, Apple Music logo) are not part of Lucide Icons. Adding them would require:
   - Custom SVG assets or Flutter icon font generation
   - Asset licensing verification (trademark usage)
   - This is a **feature enhancement**, not a bug fix

3. **Unit tests for icon rendering** — The codebase has zero meaningful test coverage (documented in `PROJECT_CONTEXT.md` as known debt). Adding tests for this area would require:
   - Test infrastructure for widget/icon rendering
   - Mocking Lucide icons
   - This is a **test coverage initiative**, not part of a single bug fix

4. **YouTube icon addition to AppIcons** — `song_details_bottom_sheet.dart` uses `Icons.play_circle_outline` (Material icon, not Lucide) for YouTube. This is a deliberate exception and predates `feature/song-links-multi-type`. Changing it would be **architectural cleanup**, not a bug fix.

5. **Icon audit for entire codebase** — `docs/reference/audits/ICON_AUDIT_AND_LUCIDE_MIGRATION.md` exists and documents a known Lucide migration initiative. This bug fix does not address the broader audit findings.
