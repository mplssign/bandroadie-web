# ARCHITECT_PLAN — Song Lookup Search Field Overflow

## Feature Slug

`bug/song-lookup-field-overflow`

## Problem Summary

The Song Lookup overlay's search input field throws a 2.0-pixel bottom overflow error, rendering a yellow/black striped debug banner directly beneath the field's border. The bug is cosmetic-only and confirmed on macOS desktop build. Platform scope beyond macOS is unconfirmed.

**Affected Component:** `lib/features/setlists/widgets/song_lookup_overlay.dart`, specifically the `_buildSearchField()` method (lines 500-565)

## Root Cause

**Confidence Level:** `HIGH` (Confirmed in code — direct observation)

The search field uses a **fixed-height Container** (44px at line 506) wrapping an `AppTextField` widget that has an **unsupported `decoration: InputDecoration(...)` prop** (lines 527-556).

**Why this fails:**

1. **AppTextField does not support `decoration`** — The widget wraps Forui's `FTextField`, which uses a builder pattern for prefix/suffix icons and does not honor Material's `InputDecoration` API. The `decoration` prop is explicitly documented as "not supported in Forui preview" (line 10-11 of `app_text_field.dart`).

2. **FTextField has intrinsic sizing** — Without the `decoration` controlling layout, `FTextField` sizes itself based on internal constraints (font metrics, padding, icon builders), which exceed the 44px outer container constraint by 2 pixels.

3. **Fixed-height constraint conflict** — The outer `Container(height: 44)` tries to force the text field into 44px, but Flutter's layout engine cannot reconcile this with `FTextField`'s intrinsic height (likely ~46px based on the 2px overflow).

**Code Evidence:**

```dart
// song_lookup_overlay.dart line 505-527
Container(
  height: 44,  // ← Fixed constraint
  decoration: BoxDecoration(...),
  child: AppTextField(
    controller: _searchController,
    focusNode: _searchFocus,
    autofocus: true,
    onChanged: _onSearchChanged,
    style: TextStyle(...),  // ← Not supported by AppTextField/FTextField
    decoration: InputDecoration(  // ← Not supported by AppTextField/FTextField
      hintText: 'Search songs or artists',
      prefixIcon: Icon(AppIcons.search, ...),
      suffixIcon: _searchController.text.isNotEmpty ? GestureDetector(...) : null,
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  ),
)
```

**Related System Knowledge:**

- `AppTextField` was migrated from Material `TextField` to Forui `FTextField` in prior feature work (see `docs/features/ui-facade-setlists-high-risk-3c-iii/` and related Forui migration features)
- The correct pattern is to use `AppTextField`'s **direct props**: `hintText`, `prefixIcon`, `suffixIcon` (see `lib/components/ui/app_text_field.dart` lines 54-57, 159-163)
- `prefixIcon` and `suffixIcon` accept `Widget?` and are converted to `prefixBuilder`/`suffixBuilder` under the hood
- The `style` prop is also not supported by `FTextField` (use Forui theme instead)

**Prior Art:**

- This file has been touched in multiple prior features related to keyboard/scroll issues (`bug/song-lookup-keyboard-scroll-blocked`, `bug/song-lookup-keyboard-scroll-blocked-v2`) and external search improvements (`itunes-search-cors-proxy`), but none touched this specific search field implementation
- The bug is pre-existing and unrelated to `feature/forui-card-consolidation` (confirmed via git diff — that branch does not touch this file)

## Reference Docs Consulted

**UI/Widget Reference:**

- `docs/reference/ui/` — Contains only `LANDING_PAGE_PREVIEW_GUIDE.md` (not relevant to Song Lookup)

**Feature History:**

- `docs/features/song-lookup-keyboard-scroll-blocked/` — Prior keyboard/scroll fix (v1)
- `docs/features/song-lookup-keyboard-scroll-blocked-v2/` — Second attempt at keyboard/scroll fix
- `docs/features/itunes-search-cors-proxy/` — External search error handling
- `docs/features/ui-facade-setlists-high-risk-3c-iii/` — Forui migration cycle that included this file (bulk add, song lookup, song details overlays)
- `docs/features/forui-style-overrides/` — Documents `AppTextField` prop restoration (prefixIcon, suffixIcon via builder pattern)

**Component Documentation:**

- `lib/components/ui/app_text_field.dart` — Defines supported props (lines 1-163)
- `lib/components/ui/README.md` — Lists restored props (prefixIcon, suffixIcon, hintText all supported)

## Existing System Analysis

**Current Behavior:**

1. User opens a setlist (Catalog or non-Catalog)
2. User triggers Song Lookup (tap "+" to add song)
3. Song Lookup overlay renders with full-screen modal animation
4. Search field renders at top with:
   - Outer padding container (16px horizontal, 12px vertical)
   - Inner decoration container (44px fixed height, rounded border, background color)
   - AppTextField with unsupported `decoration` prop
5. Flutter layout engine detects that `FTextField`'s intrinsic height (estimated 46px) exceeds the 44px constraint
6. Debug mode renders yellow/black striped overflow banner with "BOTTOM OVERFLOWED BY 2.0 PIXELS"

**Data Flow:** Not applicable (pure UI rendering bug, no data involved)

**Current Search Field Architecture:**

- Outer `Container` provides page padding (16px horizontal, 12px vertical)
- Inner `Container` provides visual styling (background, border, border radius) and fixed 44px height constraint
- `AppTextField` wraps `FTextField` from Forui
- `FTextField` uses builder pattern for prefix/suffix icons, sizes itself based on internal constraints
- Conflict: fixed height (44px) vs. intrinsic height (~46px) = 2px overflow

## Proposed Solution

**Minimal fix:** Remove the fixed-height constraint and convert to `AppTextField`'s supported prop API.

### Changes Required:

1. **Remove fixed `height: 44` constraint** from line 506
2. **Remove unsupported `decoration: InputDecoration(...)` prop** (lines 527-556)
3. **Replace with direct `AppTextField` props:**
   - `hintText: 'Search songs or artists'` (direct prop, line 21 of app_text_field.dart)
   - `prefixIcon: Icon(AppIcons.search, ...)` (direct prop, line 54)
   - `suffixIcon: _searchController.text.isNotEmpty ? GestureDetector(...) : null` (direct prop, line 57)
4. **Remove unsupported `style` prop** (FTextField uses Forui theme for text styling)

### Why This Works:

- `FTextField` sizes itself naturally when not constrained by a fixed-height parent
- The outer decoration container still provides background color, border, and rounded corners
- `prefixIcon` and `suffixIcon` are converted to `prefixBuilder`/`suffixBuilder` by `AppTextField` (lines 159-163 of app_text_field.dart)
- `hintText` is passed directly to `FTextField.hint` (line 139)
- Removing `style` prop aligns with Forui's theme-based text styling (documented in app_text_field.dart line 12)

### Why No Alternatives Considered:

- **Increasing height to 46px:** Masks the symptom, does not fix the root cause (using unsupported API)
- **Keeping `decoration` and adding `ConstrainedBox`:** Still uses unsupported API, creates fragile layout
- **Custom TextField subclass:** Violates guardrails (prefer existing patterns, no new abstractions)

**This is the minimal change that fully solves the problem.**

## Database Impact

**Not applicable** — Pure UI rendering bug, no database interaction.

## Flutter Architecture Changes

**State Management:** Not affected (search logic unchanged)

**Widget Tree Change:**

```dart
// BEFORE (broken):
Container(
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  child: Container(
    height: 44,  // ← REMOVE
    decoration: BoxDecoration(...),
    child: AppTextField(
      controller: ...,
      focusNode: ...,
      style: TextStyle(...),  // ← REMOVE
      decoration: InputDecoration(  // ← REMOVE
        hintText: '...',
        prefixIcon: Icon(...),
        suffixIcon: ...,
        border: InputBorder.none,
        contentPadding: ...,
      ),
    ),
  ),
)

// AFTER (fixed):
Container(
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  child: Container(
    // height: 44,  ← REMOVED
    decoration: BoxDecoration(...),  // Border, background, radius unchanged
    child: AppTextField(
      controller: ...,
      focusNode: ...,
      hintText: 'Search songs or artists',  // ← DIRECT PROP
      prefixIcon: Icon(AppIcons.search, size: 22, color: ...),  // ← DIRECT PROP
      suffixIcon: _searchController.text.isNotEmpty  // ← DIRECT PROP
          ? GestureDetector(
              onTap: () { ... },
              child: Icon(AppIcons.close, size: 20, color: ...),
            )
          : null,
      // style removed (use Forui theme)
      // decoration removed (not supported)
    ),
  ),
)
```

**Controllers/Providers:** Not affected

**Repositories:** Not affected

## Files to Create

**None**

## Files to Modify

| File                                                     | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | **Method:** `_buildSearchField()` (lines 500-565)<br/>**Changes:**<br/>1. Remove `height: 44` from inner Container (line 506)<br/>2. Remove `style: TextStyle(...)` from AppTextField (lines 521-525)<br/>3. Remove `decoration: InputDecoration(...)` block (lines 527-556)<br/>4. Add direct props to AppTextField: `hintText`, `prefixIcon`, `suffixIcon`<br/>5. Preserve all existing behavioral props: `controller`, `focusNode`, `autofocus: true`, `onChanged`<br/>6. Preserve outer Container padding (16/12) and inner Container decoration (background, border, radius)<br/>**Lines modified:** ~20 lines (mostly deletions, 3 new prop lines) |

## Files Off-Limits

| File                                    | Reason                                                                                          |
| --------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_text_field.dart` | Already supports all required props (hintText, prefixIcon, suffixIcon), no changes needed       |
| `lib/main.dart`                         | Initialization order must not change (GUARDRAILS.md §1)                                         |
| All other Song Lookup methods           | Only `_buildSearchField()` is affected; search logic, result rendering, callbacks all unchanged |

**Migration policy:** Not required (no database changes)

**Edge function deploy:** Not required (no backend changes)

**New dependencies:** Not allowed (no new packages)

**New files:** None

## System Impact Map

| System                                 | Impact                                                                                                                                                                                                                                                                                             |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | **unaffected** — Song Lookup is setlist-scoped                                                                                                                                                                                                                                                     |
| Rehearsals                             | **unaffected** — Song Lookup is setlist-scoped                                                                                                                                                                                                                                                     |
| Setlists / Catalog                     | **affected** — Visual-only fix to Song Lookup overlay search field (both Catalog and non-Catalog setlists use this overlay)                                                                                                                                                                        |
| Members / RBAC                         | **unaffected** — No permission logic touched                                                                                                                                                                                                                                                       |
| Auth / Session                         | **unaffected** — No auth flow touched                                                                                                                                                                                                                                                              |
| Routing                                | **unaffected** — No navigation changes                                                                                                                                                                                                                                                             |
| Notifications                          | **unaffected** — No notification logic                                                                                                                                                                                                                                                             |
| Platform (iOS / Android / Web / macOS) | **affected (unknown scope)** — Bug confirmed on macOS. Other platforms unconfirmed but likely also affected (Flutter layout overflow is consistent across platforms unless platform-specific widget adaptations exist, which AppTextField/FTextField do not have). **QA must test all platforms.** |

## Regression Risk

**Level:** `LOW`

**Rationale:**

1. **Single method change** — Only `_buildSearchField()` modified, 1 file touched
2. **No behavioral change** — Search logic, debouncing, result filtering, callbacks all unchanged
3. **No state management change** — Controllers, focus nodes, text editing unchanged
4. **No cross-feature impact** — Song Lookup is isolated to setlist screens, does not affect gigs, rehearsals, members, auth, or routing
5. **Well-documented pattern** — AppTextField's direct prop API is already used correctly in 100+ other locations (see `grep_search` results for `AppTextField` usage across codebase)
6. **No database/backend risk** — Pure UI change
7. **Forui migration precedent** — This file was already migrated to Forui in prior cycles (`ui-facade-setlists-high-risk-3c-iii`), this is just fixing a missed conversion from Material `decoration` to Forui direct props

**Risk Factors (mitigated):**

- **Platform-specific rendering differences:** Overflow confirmed only on macOS. iOS/Android/Web **must be tested** to confirm the fix works universally. However, Flutter's layout engine is consistent across platforms for non-adaptive widgets like `FTextField`, so cross-platform risk is low.
- **Visual regression:** Removing fixed-height constraint could change the field's rendered height by 2px. QA must confirm the field still looks correct (not too tall, padding/alignment preserved).

## Engineer Task Breakdown

Execute in order. Do not skip.

### Task 1: Read Forui `FTextField` Documentation

- **Goal:** Understand `FTextField`'s layout model and builder pattern
- **Action:** Read `lib/components/ui/app_text_field.dart` in full (163 lines)
- **Verification:** Confirm `prefixIcon`, `suffixIcon`, `hintText` are direct props; `decoration` and `style` are not supported

### Task 2: Locate and Isolate `_buildSearchField()`

- **File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`
- **Lines:** 500-565 (66 lines total)
- **Action:** Read method in full, identify all Container nesting levels and props
- **Verification:** Confirm line 506 has `height: 44`, line 512 has `AppTextField`, lines 527-556 have `decoration: InputDecoration(...)`

### Task 3: Remove Fixed-Height Constraint

- **File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`
- **Line:** 506
- **Action:** Delete `height: 44,` from inner Container
- **Verification:** Inner Container still has `decoration: BoxDecoration(...)` (background, border, radius), but no height constraint

### Task 4: Convert to Direct Props

- **File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`
- **Lines:** 512-556
- **Actions:**
  1. Remove `style: TextStyle(...)` (lines 521-525)
  2. Remove entire `decoration: InputDecoration(...)` block (lines 527-556)
  3. Add `hintText: 'Search songs or artists',` to AppTextField
  4. Add `prefixIcon: Icon(AppIcons.search, size: 22, color: context.colors.textMuted),` to AppTextField
  5. Extract suffix icon GestureDetector from old `decoration.suffixIcon` and add as direct prop: `suffixIcon: _searchController.text.isNotEmpty ? GestureDetector(...) : null,`
  6. Preserve all other props: `controller`, `focusNode`, `autofocus`, `onChanged`
- **Verification:**
  - AppTextField has exactly 6 props: `controller`, `focusNode`, `autofocus`, `onChanged`, `hintText`, `prefixIcon`, `suffixIcon`
  - No `style` prop
  - No `decoration` prop
  - Suffix icon GestureDetector logic unchanged (clear text on tap, set state)

### Task 5: Run `flutter analyze`

- **Command:** `flutter analyze`
- **Verification:** 0 errors, 0 warnings in `song_lookup_overlay.dart`

### Task 6: Visual Spot-Check (macOS Desktop)

- **Platform:** macOS
- **Steps:**
  1. Run app: `flutter run -d macos`
  2. Open any setlist (Catalog or non-Catalog)
  3. Tap "+" to trigger Song Lookup
  4. Observe search field at top of overlay
- **Verification:**
  - No yellow/black overflow banner
  - Search icon (magnifying glass) visible on left
  - Hint text "Search songs or artists" visible when field is empty
  - Clear icon (X) appears on right when text is entered
  - Field height looks correct (not too tall, not too short)
  - Background color, border, rounded corners preserved
  - Typing triggers debounced search (existing behavior unchanged)

### Task 7: Generate Engineer Report

- **File:** `docs/features/song-lookup-field-overflow/ENGINEER_REPORT.md`
- **Include:**
  - Summary of changes (lines modified, props removed/added)
  - Task completion checklist (6 tasks above)
  - `flutter analyze` output (confirm 0 errors)
  - Screenshot or description of visual verification
  - Git diff snippet showing exact changes
- **Verification:** Report is complete and accurate

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable** — No database migrations, RPC functions, or edge functions in this change. All verification is post-implementation.

### Tier 2 — Post-deployment

**Not applicable** — No database deployment required. All verification is in-app visual testing (see QA Regression Areas below).

### In-App Visual Testing (All Platforms)

#### Test 1: Overflow Banner Removed (macOS)

**Platform:** macOS desktop build

**Steps:**

1. Run `flutter run -d macos`
2. Open any setlist (Catalog or non-Catalog)
3. Tap "+" to add song (triggers Song Lookup overlay)
4. Observe search field at top of overlay

**Expected:** No yellow/black striped overflow banner. Field renders cleanly with rounded border.

**Actual:** _(QA fills in)_

---

#### Test 2: Search Field Visual Integrity (macOS)

**Platform:** macOS desktop build

**Steps:**

1. Song Lookup overlay open (from Test 1)
2. Observe search field layout

**Expected:**

- Background color: `context.colors.surfaceElevated` (dark elevated surface)
- Border: 1px, color `context.colors.border`, radius 8px
- Prefix icon: magnifying glass (AppIcons.search), size 22, muted color
- Hint text: "Search songs or artists" when field is empty, muted color
- Field height: natural (no fixed constraint), approximately 44-46px
- No visual distortion, clipping, or spacing issues

**Actual:** _(QA fills in)_

---

#### Test 3: Clear Button Appears on Text Entry (macOS)

**Platform:** macOS desktop build

**Steps:**

1. Song Lookup overlay open
2. Type any text in search field (e.g., "test")
3. Observe right side of field

**Expected:**

- Clear icon (X) appears on right when text is entered
- Tapping X clears text and removes icon
- Search results update (debounced) based on typed text

**Actual:** _(QA fills in)_

---

#### Test 4: Search Functionality Unchanged (macOS)

**Platform:** macOS desktop build

**Steps:**

1. Song Lookup overlay open
2. Type a song title or artist name that exists in the Catalog (e.g., "Hey Jude")
3. Wait for results to load (250ms debounce)

**Expected:**

- Internal/catalog results section shows matching songs
- Tapping a result adds the song to the setlist
- Overlay closes after song is added
- Song appears in setlist immediately

**Actual:** _(QA fills in)_

---

#### Test 5: External Search Unchanged (macOS)

**Platform:** macOS desktop build

**Steps:**

1. Song Lookup overlay open
2. Type a song title that does NOT exist in the Catalog (e.g., "Superstition")
3. Wait for external search to complete

**Expected:**

- External results section appears below internal results
- Results grouped by match type (exact/partial artist, exact/partial title)
- Tapping an external result triggers enrichment review sheet
- Adding external song creates it in Catalog and adds to setlist

**Actual:** _(QA fills in)_

---

#### Test 6: Overflow Banner Removed (iOS)

**Platform:** iOS physical device (iPhone)

**Steps:**

1. Build and deploy to iPhone: `flutter run -d <device-id>`
2. Open any setlist
3. Tap "+" to add song
4. Observe search field

**Expected:** No overflow banner. Field renders cleanly.

**Actual:** _(QA fills in)_

---

#### Test 7: iOS Keyboard Interaction

**Platform:** iOS physical device

**Steps:**

1. Song Lookup overlay open
2. Tap search field (keyboard appears)
3. Type text
4. Observe field layout and keyboard interaction

**Expected:**

- Keyboard does not obscure search field
- Field remains fixed at top of overlay
- Results list scrolls correctly behind keyboard (existing behavior from prior fixes: `bug/song-lookup-keyboard-scroll-blocked-v2`)
- No visual distortion or layout shift

**Actual:** _(QA fills in)_

---

#### Test 8: Overflow Banner Removed (Android)

**Platform:** Android physical device or emulator

**Steps:**

1. Build and deploy: `flutter run -d <device-id>`
2. Open any setlist
3. Tap "+" to add song
4. Observe search field

**Expected:** No overflow banner. Field renders cleanly.

**Actual:** _(QA fills in)_

---

#### Test 9: Android Keyboard Interaction

**Platform:** Android physical device or emulator

**Steps:**

1. Song Lookup overlay open
2. Tap search field (keyboard appears)
3. Type text
4. Observe field layout and keyboard interaction

**Expected:**

- Same as Test 7 (iOS keyboard interaction)
- No Android-specific rendering issues

**Actual:** _(QA fills in)_

---

#### Test 10: Overflow Banner Removed (Web)

**Platform:** Web (Chrome, deployed or local)

**Steps:**

1. Run `flutter run -d chrome` or open deployed web app
2. Open any setlist
3. Click "+" to add song
4. Observe search field

**Expected:** No overflow banner. Field renders cleanly.

**Actual:** _(QA fills in)_

---

#### Test 11: Web Click-to-Focus

**Platform:** Web (Chrome)

**Steps:**

1. Song Lookup overlay open
2. Click inside search field
3. Type text
4. Observe focus state and search functionality

**Expected:**

- Field gains focus on click (cursor appears)
- Typing triggers debounced search
- No visual artifacts or focus ring issues

**Actual:** _(QA fills in)_

---

## QA Regression Areas

### Primary Validation (Must Test)

1. **Overflow banner removed (all platforms)** — macOS ✅ confirmed by Tony (device screenshot), iOS/Android/Web pending QA
2. **Search field visual integrity** — Background, border, icons, hint text, natural height (not too tall/short)
3. **Clear button behavior** — X icon appears on text entry, clears text on tap
4. **Search debouncing unchanged** — 250ms delay, results update correctly
5. **Internal/catalog search** — Results render, tapping adds song to setlist
6. **External search** — iTunes/MusicBrainz results render, grouped by match type, enrichment review triggered on tap

### Platform-Specific Testing (All Must Pass)

| Platform | Test                 | Expected        | Status          |
| -------- | -------------------- | --------------- | --------------- |
| macOS    | Overflow removed     | No banner       | _(QA fills in)_ |
| macOS    | Visual integrity     | Correct layout  | _(QA fills in)_ |
| macOS    | Search functionality | Works correctly | _(QA fills in)_ |
| iOS      | Overflow removed     | No banner       | _(QA fills in)_ |
| iOS      | Keyboard interaction | No layout shift | _(QA fills in)_ |
| iOS      | Search functionality | Works correctly | _(QA fills in)_ |
| Android  | Overflow removed     | No banner       | _(QA fills in)_ |
| Android  | Keyboard interaction | No layout shift | _(QA fills in)_ |
| Android  | Search functionality | Works correctly | _(QA fills in)_ |
| Web      | Overflow removed     | No banner       | _(QA fills in)_ |
| Web      | Click-to-focus       | Works correctly | _(QA fills in)_ |
| Web      | Search functionality | Works correctly | _(QA fills in)_ |

### Secondary Validation (Spot-Check)

1. **Song Lookup from Catalog setlist** — Open Catalog, tap "+", search field renders correctly
2. **Song Lookup from non-Catalog setlist** — Open any other setlist, tap "+", search field renders correctly
3. **Search with no results** — Type nonsense text, "No results" state renders correctly
4. **Search with external error** — Force external search error (disconnect network mid-search), error banner renders correctly

### Out-of-Scope (No Testing Required)

- Bulk Add Songs overlay (different file, different search field)
- Setlist reordering (unrelated to Song Lookup)
- Song details editing (unrelated to Song Lookup)
- BPM/Key/Tuning inline editing (unrelated to Song Lookup search field)
- Notification delivery (unrelated to setlists)

## Rollout / Migration Strategy

**Not applicable** — No database migration, no edge function deploy, no config changes.

**Deploy process:**

1. Merge to `main`
2. Deploy web: `./tools/deploy_web.sh`
3. Mobile release: Follow standard release process (build, sign, upload to App Store / Play Store)

**Rollback:** Standard git revert if visual regression detected.

## Out of Scope

1. **Other overflow issues in Song Lookup overlay** — Only the search field overflow is addressed. If QA finds other layout issues elsewhere in the overlay, those are separate bugs.
2. **Search field height standardization** — The field now sizes naturally (likely 44-46px). If product wants a specific fixed height, that requires a separate design decision and should be filed as a new feature request.
3. **Forui theme customization** — Text color, font size, and icon colors are controlled by Forui theme (`context.colors.textPrimary`, `context.colors.textMuted`). Any theme adjustments are out of scope.
4. **Other files with similar patterns** — The Architect noted 8 other files using the same unverified 16px-margin toggle pattern in prior work (`bug/song-lookup-keyboard-scroll-blocked-v2`, ARCHITECT_PLAN.md lines 178). Those are **latent risks** but require individual device testing to confirm the bug exists in each context. This ticket addresses **only the Song Lookup overlay** where the bug has been device-confirmed.
5. **AppTextField API improvements** — The current direct prop API (`hintText`, `prefixIcon`, `suffixIcon`) is sufficient. Any future API changes (e.g., restoring full `decoration` support) are out of scope.

---

**End of ARCHITECT_PLAN.md**
