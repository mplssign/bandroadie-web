# ARCHITECT_PLAN — A-Z Search Field Decoration Bug

## Feature Slug

`bug/az-search-field-decoration-bug`

## Problem Summary

The `AzSearchField` widget, used by Venues and Contacts A-Z list views, passes `decoration: InputDecoration(...)` and `style: TextStyle(...)` directly to `AppTextField`. However, `AppTextField`'s `build()` method does not read these properties — it only wires top-level `hintText`, `prefixIcon`, `suffixIcon`, and `labelText` into Forui's `FTextField`. All properties nested inside `decoration` (hint text, hint style, prefix search icon, suffix clear button, fill color, border styles, focused border) and the `style` text styling are silently discarded. This renders the search field as a bare, undecorated Forui text field with no placeholder, no icons, and no visual styling.

**Affected Components:**

- `lib/features/contacts/widgets/az_search_field.dart` (the buggy widget)
- Used by: `lib/features/contacts/widgets/venues_view.dart` (line 397)
- Used by: `lib/features/contacts/widgets/contacts_view.dart` (line 381)
- NOT used by: `lib/features/contacts/widgets/band_members_view.dart` (confirmed via grep and code inspection — Band Members is a flat, unsearchable list with no search field)

**Bug Class:** This is the same unsupported-prop bug class fixed in PR #155 (`bug/song-lookup-field-overflow`, merged 2026-08-15, commit `2d39703` on `origin/main`), which removed `decoration` and `style` from `song_lookup_overlay.dart` and switched to `AppTextField`'s supported direct props.

**Platform Scope:** Not yet device-confirmed. Same prop-drop mechanism as PR #155 (confirmed on macOS desktop) — flagging for cross-platform confirmation since this widget spans multiple screens.

## Root Cause

**Confidence Level:** `HIGH` (confirmed by direct code inspection)

`AzSearchField` instantiates `AppTextField` and passes:

```dart
AppTextField(
  controller: controller,
  decoration: InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(...),
    prefixIcon: Icon(AppIcons.search, ...),
    suffixIcon: currentQuery.isNotEmpty ? AppIconButton(...) : null,
    filled: true,
    fillColor: context.colors.surface,
    border: OutlineInputBorder(...),
    enabledBorder: OutlineInputBorder(...),
    focusedBorder: OutlineInputBorder(...),
  ),
  style: TextStyle(
    color: context.colors.textPrimary,
    fontSize: AppFontSizes.body,
  ),
  onChanged: onChanged,
)
```

**The problem:** `AppTextField` accepts `decoration` and `style` as constructor parameters (lines 18, 31 in `lib/components/ui/app_text_field.dart`), but its `build()` method (lines 100-150) never reads them. Instead, it only uses:

- `hintText` (line 136)
- `labelText` (line 135, wrapped in `Text`)
- `prefixIcon`, `suffixIcon` (lines 158-161, wired via `prefixBuilder`/`suffixBuilder` pattern)

Everything nested inside `decoration` is ignored. The `style` prop is also ignored (Forui uses theme-based styling).

**Root Cause:** `AzSearchField` uses the Material `InputDecoration` API, which was valid before the Forui migration but is now silently discarded. The widget was created after the Forui UI facade consolidation (`feature/forui-card-consolidation` per git history) but was not updated to use `AppTextField`'s supported direct props.

## Reference Docs Consulted

- `lib/components/ui/README.md` — Documents the 15 Forui-styled UI facade wrappers, explicitly lists `decoration` and `style` as "Props Not Supported in Forui" for `AppTextField`/`AppTextFormField`, and confirms that `prefixIcon`, `suffixIcon`, and `hintText` are the supported direct props.
- `docs/features/song-lookup-field-overflow/ARCHITECT_PLAN.md` (PR #155, commit `2d39703` on `origin/main`) — Establishes the pattern for this exact bug class: remove `decoration` and `style`, switch to direct props (`hintText`, `prefixIcon`, `suffixIcon`).

No other reference docs exist in `docs/reference/` for the UI facade or search field patterns.

## Existing System Analysis

### Current Behavior and Data Flow

**AzSearchField instantiation (Venues):**

1. `venues_view.dart` line 397 calls `_buildSearchBar()`
2. `_buildSearchBar()` instantiates `AzSearchField` with:
   - `controller: _searchController`
   - `hintText: 'Search venues, names, cities'`
   - `currentQuery: venuesState.searchQuery` (from provider)
   - `onChanged: (value) => ref.read(venuesProvider.notifier).setSearchQuery(value)`
   - `onClear: () => { _searchController.clear(); setSearchQuery('') }`
3. `AzSearchField` passes all of the above plus `decoration: InputDecoration(...)` and `style: TextStyle(...)` to `AppTextField`
4. `AppTextField.build()` ignores `decoration` and `style`, resulting in a bare `FTextField` with no hint, no icons, no styling

**AzSearchField instantiation (Contacts):**

1. `contacts_view.dart` line 381 calls `_buildSearchBar()`
2. Identical pattern to Venues, with `hintText: 'Search contacts'`

**What renders today:**

- A bare Forui text field with default styling
- No placeholder text
- No search icon on the left
- No clear button on the right (even when text is entered)
- No filled background color
- No border or focus ring

**Expected rendering (after fix):**

- Hint text: "Search venues, names, cities" or "Search contacts" (depending on view)
- Search icon (magnifying glass) on the left, explicitly sized (22px), color `context.colors.textSecondary`
- Clear button (X icon, explicitly sized 20px) on the right when `currentQuery.isNotEmpty`, wrapped in `GestureDetector` for tap handling
- Filled background, border, and focus ring (via Forui theme, not custom decoration)

## Proposed Solution

**Minimal fix:** Remove `decoration` and `style` props from `AppTextField` call in `AzSearchField.build()`. Replace with direct props: `hintText`, `prefixIcon`, `suffixIcon`.

**Single file change:** `lib/features/contacts/widgets/az_search_field.dart`

**Pattern:** Follow PR #155 exactly (confirmed working via `song_lookup_overlay.dart` lines 518-531):

1. Remove `decoration: InputDecoration(...)` entirely
2. Remove `style: TextStyle(...)` entirely
3. Add `hintText` as a direct prop (value already passed via constructor param)
4. Add `prefixIcon` as a direct prop: `Icon(AppIcons.search, size: 22, color: context.colors.textSecondary)`
   - **CRITICAL:** Include explicit `size: 22` to match PR #155 and ensure correct alignment
5. Add `suffixIcon` as a direct prop: `currentQuery.isNotEmpty ? GestureDetector(onTap: onClear, child: Icon(AppIcons.close, size: 20, color: context.colors.textSecondary)) : null`
   - **CRITICAL:** Use `GestureDetector` wrapping a plain `Icon`, NOT `AppIconButton`
   - `AppIconButton` wraps `FButton.icon` which renders with button chrome/padding (confirmed defect in macOS/iOS testing)
   - Include explicit `size: 20` for the close icon
6. Preserve all other props: `controller`, `onChanged`

**Styling notes:**

- Background fill, border radius, border colors, and focus ring are NOT added as direct props — these are styling concerns not supported by Forui `FTextField`. Forui handles these via theme.
- Text color and font size from the removed `style` prop are handled by Forui theme — no direct prop replacement needed.
- Icon sizing MUST be explicit (`size: 22` for prefix, `size: 20` for suffix) to match PR #155 and ensure correct alignment across platforms.

**Why not `AppIconButton`?**

The initial implementation attempt used `AppIconButton` for the suffix clear icon, which caused real defects in device testing:
- **macOS:** Clear button rendered inside distinct boxed button chrome, visually misaligned with the field. Search icon also misaligned.
- **iOS:** Search icon misaligned; clear button did not render at all (likely due to themed button sizing exceeding available space in narrower field width).

**Root cause:** `AppIconButton` wraps `FButton.icon`, and its docstring (lines 9-10 in `lib/components/ui/app_icon_button.dart`) explicitly states `color` and `size` props are "currently ignored... Icon buttons use theme default styling." This renders it unsuitable for inline text field icons, which require explicit sizing and no button chrome.

**Correct pattern:** PR #155 uses `GestureDetector` (or `InkWell`) wrapping a plain, explicitly-sized `Icon` for both prefix and suffix. This is the only pattern that works correctly across platforms for text field icons.

## Database Impact

**Not applicable** — No database schema, RLS policies, RPC functions, or edge functions are affected. This is a pure Flutter UI widget change.

## Flutter Architecture Changes

**State Management:** Not affected. Controllers (`_searchController`), providers (`venuesProvider`, `contactsProvider`), and search query state all unchanged.

**Widget Tree:** Not affected. `AzSearchField` remains a `StatelessWidget` with the same constructor API. Call sites in `venues_view.dart` and `contacts_view.dart` are unchanged.

**Affected Components:**

- `AzSearchField` widget — internal implementation only (constructor API unchanged)

**Unaffected Components:**

- `AppTextField` wrapper — no changes needed (already supports all required props)
- `venues_view.dart` — call site unchanged
- `contacts_view.dart` — call site unchanged
- `band_members_view.dart` — does not use `AzSearchField`, unaffected

## Files to Create

**None**

## Files to Modify

| File                                                 | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/az_search_field.dart` | **Method:** `build()` (lines 31-89)<br/>**Changes:**<br/>1. Remove `decoration: InputDecoration(...)` block (lines 34-74)<br/>2. Remove `style: TextStyle(...)` block (lines 75-78)<br/>3. Add direct props to `AppTextField`: `hintText`, `prefixIcon`, `suffixIcon`<br/>4. Preserve existing behavioral props: `controller`, `onChanged`<br/>5. Extract icon widgets from old `decoration.prefixIcon` and `decoration.suffixIcon`:<br/>   - `prefixIcon`: plain `Icon` with explicit `size: 22`<br/>   - `suffixIcon`: `GestureDetector(onTap: onClear, child: Icon(..., size: 20))` — **NOT `AppIconButton`** (failed device testing)<br/>**Lines modified:** ~40 lines (mostly deletions, 3 new prop lines + GestureDetector wrapper)<br/>**API impact:** None — `AzSearchField` constructor and external API unchanged |

## Files Off-Limits

| File                                                   | Reason                                                                                          |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_text_field.dart`                | Already supports all required props (`hintText`, `prefixIcon`, `suffixIcon`), no changes needed |
| `lib/features/contacts/widgets/venues_view.dart`       | Call site unchanged — `AzSearchField` API is unchanged                                          |
| `lib/features/contacts/widgets/contacts_view.dart`     | Call site unchanged — `AzSearchField` API is unchanged                                          |
| `lib/features/contacts/widgets/band_members_view.dart` | Does not use `AzSearchField`, unaffected by this fix                                            |
| `lib/main.dart`                                        | Initialization order must not change (GUARDRAILS.md §1)                                         |

**Migration policy:** Not required (no database changes)

**Edge function deploy:** Not required (no backend changes)

**New dependencies:** Not allowed (no new packages)

**New files:** None

## System Impact Map

| System                                 | Impact                                                                                                                                                                                                                         |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Gigs                                   | **unaffected** — AzSearchField is contacts-domain only                                                                                                                                                                         |
| Rehearsals                             | **unaffected** — AzSearchField is contacts-domain only                                                                                                                                                                         |
| Setlists / Catalog                     | **unaffected** — AzSearchField is contacts-domain only                                                                                                                                                                         |
| Members / RBAC                         | **unaffected** — No permission logic touched                                                                                                                                                                                   |
| Auth / Session                         | **unaffected** — No auth flow touched                                                                                                                                                                                          |
| Routing                                | **unaffected** — No navigation changes                                                                                                                                                                                         |
| Notifications                          | **unaffected** — No notification logic                                                                                                                                                                                         |
| Contacts (Venues, Contacts views)      | **affected** — Visual fix to search field rendering in Venues and Contacts A-Z list views                                                                                                                                      |
| Platform (iOS / Android / Web / macOS) | **affected (unknown scope)** — Bug mechanism (AppTextField prop drop) is platform-independent. Same issue as PR #155 (confirmed on macOS). **QA must test all platforms** to confirm the fix renders correctly cross-platform. |

## Regression Risk

**Level:** `LOW`

**Rationale:**

1. **Single widget change** — Only `AzSearchField` modified, 1 file touched
2. **No behavioral change** — Search logic, debouncing, state management, callbacks all unchanged
3. **No API change** — `AzSearchField` constructor unchanged, call sites unchanged
4. **Well-documented pattern** — Direct props API is already used correctly in 100+ other locations (per `README.md` and PR #155)
5. **No cross-feature impact** — `AzSearchField` is isolated to Venues and Contacts views, does not affect gigs, rehearsals, members, setlists, auth, or routing
6. **No database/backend risk** — Pure UI change
7. **Forui migration precedent** — This is the same bug class as PR #155, which was merged successfully with zero regressions

**Risk Factors (mitigated):**

- **Platform-specific rendering differences:** Bug mechanism is platform-independent (Forui `FTextField` behavior is consistent across platforms). However, **QA must test iOS, Android, Web, and macOS** to confirm the fix renders correctly on all platforms and that the search icon, hint text, and clear button all appear as expected.
- **Icon sizing/alignment:** Explicit `size:` parameters (22px prefix, 20px suffix) are now required to match PR #155 and ensure correct cross-platform alignment.

## AppIconButton Limitation — Known Issue

**Finding from device testing:** `AppIconButton` (`lib/components/ui/app_icon_button.dart`) is unsuitable for inline text field icons because:

1. Its docstring (lines 9-10) explicitly states `color` and `size` props are "currently ignored... Icon buttons use theme default styling"
2. It wraps `FButton.icon`, which renders with button chrome (padding, background, border) — visually inconsistent with plain icons in text fields
3. On iOS narrow fields, the themed button sizing can exceed available space, causing the icon to not render at all

**Correct pattern for text field icons:** Use `GestureDetector` (or `InkWell`) wrapping a plain, explicitly-sized `Icon`. This is the pattern used in PR #155 (`song_lookup_overlay.dart`) and is the only approach that works reliably across platforms.

**Potential broader issue:** Other call sites using `AppIconButton` inside or adjacent to text fields may have the same limitation (ignored color/size, unwanted button chrome). This fix does NOT audit or fix those call sites — they are out of scope. However, the Manager should consider whether a separate audit is warranted to identify and flag other instances of this pattern for future fixes.

**Files potentially affected (not audited, not fixed here):**
- Any widget using `AppIconButton` as a `suffixIcon` or `prefixIcon` in `AppTextField` or `AppTextFormField`
- Any widget placing `AppIconButton` adjacent to text input fields where inline icon styling is expected

## Engineer Task Breakdown

Execute in order. Do not skip.

### Task 1: Read Forui `FTextField` and `AppTextField` Documentation

- **Goal:** Understand `FTextField`'s layout model and `AppTextField`'s supported props
- **Actions:**
  1. Read `lib/components/ui/app_text_field.dart` in full (163 lines)
  2. Read `lib/components/ui/README.md` — AppTextField section
  3. Read `docs/features/song-lookup-field-overflow/ARCHITECT_PLAN.md` (PR #155 reference)
- **Verification:** Confirm `prefixIcon`, `suffixIcon`, `hintText` are direct props; `decoration` and `style` are not supported

### Task 2: Locate and Isolate `AzSearchField.build()`

- **File:** `lib/features/contacts/widgets/az_search_field.dart`
- **Lines:** 31-89 (59 lines total)
- **Action:** Read method in full, identify all `AppTextField` props
- **Verification:** Confirm line 34 starts `decoration: InputDecoration(`, line 75 starts `style: TextStyle(`, line 79 has `onChanged: onChanged`

### Task 3: Convert to Direct Props — REVISED AFTER DEVICE TESTING FAILURE

- **File:** `lib/features/contacts/widgets/az_search_field.dart`
- **Lines:** 31-89
- **Actions:**
  1. Remove `decoration: InputDecoration(...)` block (lines 34-74)
  2. Remove `style: TextStyle(...)` block (lines 75-78)
  3. Add `hintText: hintText,` to `AppTextField` (pass through constructor param)
  4. Add `prefixIcon: Icon(AppIcons.search, size: 22, color: context.colors.textSecondary),` to `AppTextField`
     - **CRITICAL:** Must include `size: 22` (matches PR #155)
  5. Add `suffixIcon` using the PR #155 pattern (GestureDetector + Icon, NOT AppIconButton):
     ```dart
     suffixIcon: currentQuery.isNotEmpty
         ? GestureDetector(
             onTap: onClear,
             child: Icon(
               AppIcons.close,
               size: 20,
               color: context.colors.textSecondary,
             ),
           )
         : null,
     ```
  6. Preserve all other props: `controller`, `onChanged`
- **Verification:**
  - `AppTextField` has exactly 5 props: `controller`, `hintText`, `prefixIcon`, `suffixIcon`, `onChanged`
  - No `style` prop
  - No `decoration` prop
  - `prefixIcon` is a plain `Icon` widget with explicit `size: 22`
  - `suffixIcon` is a `GestureDetector` wrapping a plain `Icon` with explicit `size: 20` (NOT `AppIconButton`)
  - Suffix icon logic unchanged: `currentQuery.isNotEmpty` gate, `onClear` callback via `GestureDetector.onTap`

### Task 4: Run `flutter analyze`

- **Command:** `flutter analyze`
- **Verification:** 0 errors, 0 warnings in `az_search_field.dart`

### Task 5: Visual Spot-Check (macOS Desktop) — CRITICAL RETEST

**NOTE:** This task must be re-executed after the Task 3 revision (GestureDetector + Icon pattern). The initial implementation using `AppIconButton` failed device testing.

- **Platform:** macOS
- **Steps:**
  1. Run app: `flutter run -d macos`
  2. Open Contacts tab
  3. Switch to Venues segment
  4. Observe search field at top of list
  5. Type text in search field
  6. Observe clear button appearance and behavior
  7. Switch to Contacts segment
  8. Repeat observations
- **Verification:**
  - Search icon (magnifying glass) visible on left in both views, **properly aligned** (not misaligned as in initial failed implementation)
  - **No distinct button chrome/box around clear icon** (was present with AppIconButton)
  - Hint text visible when field is empty: "Search venues, names, cities" (Venues) and "Search contacts" (Contacts)
  - Clear icon (X) appears on right when text is entered in both views, **inline with the field** (not in separate button box)
  - Clear icon **tappable via GestureDetector** (tap clears text and removes icon)
  - Field background, border, and rounded corners rendered correctly via Forui theme
  - Typing triggers search query update (existing behavior unchanged)

### Task 6: Visual Spot-Check (iOS Physical Device) — CRITICAL RETEST

**NOTE:** This is a new mandatory task. The initial implementation using `AppIconButton` caused the clear button to not render at all on iOS.

- **Platform:** iOS physical device (iPhone)
- **Steps:**
  1. Build and deploy: `flutter run -d <device-id>`
  2. Open Contacts tab → Venues segment
  3. Tap search field (keyboard appears)
  4. Type text in search field
  5. Observe clear button appearance and behavior
  6. Switch to Contacts segment
  7. Repeat observations
- **Verification:**
  - Search icon visible on left, **properly aligned** (not misaligned as in initial failed implementation)
  - **Clear icon (X) now renders** (was completely missing with AppIconButton due to button sizing exceeding available space)
  - Clear icon is **tappable** (GestureDetector works on iOS)
  - Clear icon properly aligned inline with field (no button chrome)
  - Keyboard interaction does not obscure field or cause layout issues

### Task 7: Generate Engineer Report

- **File:** `docs/features/az-search-field-decoration-bug/ENGINEER_REPORT.md`
- **Include:**
  - Summary of changes (lines modified, props removed/added)
  - **Note on initial implementation failure:** Document that `AppIconButton` was attempted first and failed device testing (macOS misalignment, iOS no render), and that GestureDetector + Icon pattern from PR #155 was the correct solution
  - Task completion checklist (7 tasks above)
  - `flutter analyze` output (confirm 0 errors)
  - Screenshots or descriptions of visual verification on **both macOS and iOS**
  - Git diff snippet showing exact changes
- **Verification:** Report is complete and accurate

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable** — No database migrations, RPC functions, or edge functions in this change. All verification is post-implementation in-app visual testing.

### Tier 2 — Post-deployment

**Not applicable** — No database deployment required. All verification is in-app visual testing (see QA Regression Areas below).

## QA Regression Areas

QA must test the following areas to confirm the fix and guard against regressions:

### Primary Verification (All Platforms)

**Test 1: Search Field Visual Integrity (Venues — macOS)**

**Platform:** macOS desktop build

**Steps:**

1. Run `flutter run -d macos`
2. Open Contacts tab
3. Switch to Venues segment
4. Observe search field at top of list

**Expected:**

- Search icon (magnifying glass) visible on left, muted color
- Hint text "Search venues, names, cities" visible when field is empty, muted color
- Field has background fill, border, rounded corners (Forui theme styling)
- Field height is natural (approximately 44-48px, not fixed)
- No visual distortion, clipping, or missing elements

**Actual:** _(QA fills in)_

---

**Test 2: Clear Button Appears on Text Entry (Venues — macOS)**

**Platform:** macOS desktop build

**Steps:**

1. Venues view open (from Test 1)
2. Click in search field
3. Type any text (e.g., "test")
4. Observe right side of field

**Expected:**

- Clear icon (X) appears on right when text is entered
- Tapping X clears text, removes clear icon, and resets search results to show all venues
- Search results update as text is typed (existing debounced behavior)

**Actual:** _(QA fills in)_

---

**Test 3: Search Functionality Unchanged (Venues — macOS)**

**Platform:** macOS desktop build

**Steps:**

1. Venues view open
2. Type a venue name, city, or person name that exists (e.g., partial match)
3. Observe search results

**Expected:**

- Results filter to show matching venues
- A-Z section headers update based on filtered results
- Index column updates to show only letters with matches (existing behavior)
- Tapping a result opens Venue Detail Screen (existing behavior)

**Actual:** _(QA fills in)_

---

**Test 4: Search Field Visual Integrity (Contacts — macOS)**

**Platform:** macOS desktop build

**Steps:**

1. Contacts tab open
2. Switch to Contacts segment
3. Observe search field at top of list

**Expected:**

- Same visual rendering as Venues (Test 1)
- Hint text "Search contacts" visible when field is empty

**Actual:** _(QA fills in)_

---

**Test 5: Clear Button and Search (Contacts — macOS)**

**Platform:** macOS desktop build

**Steps:**

1. Contacts view open (from Test 4)
2. Type a contact name that exists
3. Observe search results and clear button

**Expected:**

- Same behavior as Venues (Tests 2 and 3)
- Results filter to show matching contacts
- Clear button appears and functions correctly

**Actual:** _(QA fills in)_

---

### Cross-Platform Verification

**Test 6: Search Field Visual Integrity (Venues — iOS)**

**Platform:** iOS physical device (iPhone)

**Steps:**

1. Build and deploy to iPhone: `flutter run -d <device-id>`
2. Open Contacts tab → Venues segment
3. Observe search field

**Expected:** Same rendering as macOS Test 1 (search icon, hint text, styling)

**Actual:** _(QA fills in)_

---

**Test 7: iOS Keyboard Interaction (Venues)**

**Platform:** iOS physical device

**Steps:**

1. Venues view open
2. Tap search field (keyboard appears)
3. Type text
4. Tap clear button

**Expected:**

- Keyboard does not obscure search field or A-Z index column
- Typing and clear button behavior match macOS (Tests 2-3)
- No layout shift or visual distortion

**Actual:** _(QA fills in)_

---

**Test 8: Search Field Visual Integrity (Contacts — iOS)**

**Platform:** iOS physical device

**Steps:**

1. Contacts tab → Contacts segment
2. Observe search field

**Expected:** Same rendering as macOS Test 4 (hint text "Search contacts")

**Actual:** _(QA fills in)_

---

**Test 9: Search Field Visual Integrity (Venues — Android)**

**Platform:** Android physical device or emulator

**Steps:**

1. Build and deploy: `flutter run -d <device-id>`
2. Open Contacts tab → Venues segment
3. Observe search field

**Expected:** Same rendering as macOS Test 1

**Actual:** _(QA fills in)_

---

**Test 10: Android Keyboard Interaction (Venues)**

**Platform:** Android physical device or emulator

**Steps:**

1. Venues view open
2. Tap search field (keyboard appears)
3. Type text
4. Tap clear button

**Expected:** Same behavior as iOS Test 7 (keyboard, typing, clear button)

**Actual:** _(QA fills in)_

---

**Test 11: Search Field Visual Integrity (Contacts — Android)**

**Platform:** Android physical device or emulator

**Steps:**

1. Contacts tab → Contacts segment
2. Observe search field

**Expected:** Same rendering as macOS Test 4

**Actual:** _(QA fills in)_

---

**Test 12: Search Field Visual Integrity (Venues — Web)**

**Platform:** Web (Chrome, deployed or local)

**Steps:**

1. Run `flutter run -d chrome` or open deployed web app
2. Open Contacts tab → Venues segment
3. Observe search field

**Expected:** Same rendering as macOS Test 1

**Actual:** _(QA fills in)_

---

**Test 13: Web Click-to-Focus and Typing (Venues)**

**Platform:** Web (Chrome)

**Steps:**

1. Venues view open
2. Click in search field
3. Type text using physical keyboard
4. Click clear button

**Expected:** Same behavior as macOS Tests 2-3 (click-to-focus, typing, clear button)

**Actual:** _(QA fills in)_

---

**Test 14: Search Field Visual Integrity (Contacts — Web)**

**Platform:** Web (Chrome)

**Steps:**

1. Contacts tab → Contacts segment
2. Observe search field

**Expected:** Same rendering as macOS Test 4

**Actual:** _(QA fills in)_

---

### Regression Guards

**Test 15: Band Members View Unchanged**

**Platform:** macOS (or any platform)

**Steps:**

1. Contacts tab → Band segment
2. Observe list view

**Expected:**

- No search field rendered (Band Members is a flat, unsearchable list)
- Member cards render correctly
- Reorder functionality works (if enabled)
- Add/Invite button visible

**Actual:** _(QA fills in)_

---

**Test 16: Venues A-Z Index Column Unchanged**

**Platform:** macOS (or any platform)

**Steps:**

1. Venues view open
2. Tap a letter in the A-Z index column on the right
3. Observe list scroll

**Expected:**

- List scrolls to the tapped letter's section
- A-Z index column rendering and tap behavior unchanged (existing feature)

**Actual:** _(QA fills in)_

---

**Test 17: Contacts A-Z Index Column Unchanged**

**Platform:** macOS (or any platform)

**Steps:**

1. Contacts view open
2. Tap a letter in the A-Z index column on the right
3. Observe list scroll

**Expected:**

- Same behavior as Test 16 (scroll to letter section)

**Actual:** _(QA fills in)_

---

## Rollout / Migration Strategy

**Not applicable** — No database migration, no edge function deploy, no feature flag. This is a pure Flutter client change.

**Deployment:** Standard web deploy via `./tools/deploy_web.sh` after QA approval. Native builds (iOS, Android) will pick up the fix in the next release build.

## Out of Scope

Explicitly **not** included in this fix:

1. **AppIconButton audit** — The fix uses `GestureDetector` + `Icon` pattern for `AzSearchField` only. Other call sites using `AppIconButton` inside or adjacent to text fields are not audited or fixed. This is flagged as a potential broader issue in the "AppIconButton Limitation — Known Issue" section above, but any audit or fixes are out of scope for this bug.

2. **Forui theme customization** — The fix relies on Forui's default theme for background fill, border, border radius, and focus ring. If the search field's visual styling needs to differ from the Forui theme defaults, that requires a Forui theme update or a custom `FTextField` builder, both of which are out of scope for this bug fix.

3. **Band Members search** — Band Members view intentionally does not have a search field (confirmed by reading `band_members_view.dart` and related architecture docs). Adding search to Band Members is a separate feature request, not a bug fix.

4. **Other search fields in the app** — This fix targets only `AzSearchField`. Other search fields (e.g., Song Lookup overlay, already fixed in PR #155) are out of scope.

5. **A-Z grouping or index column behavior** — This fix does not touch `az_list_helpers.dart`, `az_section_header.dart`, or `az_index_column.dart`. All A-Z grouping, sectioning, and index column logic is unchanged.

---

**End of ARCHITECT_PLAN.md**
