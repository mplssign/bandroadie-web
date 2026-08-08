# Architect Plan — UI Facade Setlists High Risk Retrofit (Cycle 3c-i: Top-Level Screens)

## Feature Slug

`feature/ui-facade-setlists-high-risk-3c-i`

## Problem Summary

This is **Cycle 3c-i** of the UI facade migration (Piece 3), the first of three sub-cycles covering the remaining high-risk setlists files not yet retrofitted. Cycles 3a (gigs+events, merged `18ff085`) and 3b (setlists low/medium-risk, merged `8539dfe`) are complete. Cycle 3d will handle `setlist_detail_screen.dart` (3,716 lines) as a standalone cycle.

The original Cycle 3c scope (15 files, 12,612 lines) exceeds prior cycle sizes (3a/3b were 11 files each). Following the Manager's guidance to "use judgment on whether to split" and "don't force this into a single Engineer/QA cycle," this work is divided into three sub-cycles following a risk-ascending pattern:

- **3c-i (this cycle)**: Top-level screens (5 files, 3,245 lines) — LOW RISK
- **3c-ii (next)**: Add-to-setlist subflow (4 files, 3,104 lines) — MEDIUM RISK
- **3c-iii (final)**: Overlays and sheets (6 files, 6,263 lines) — HIGH RISK

This cycle (3c-i) covers the **top-level screens** — primary entry points and orchestration widgets that compose child components. These files have lower complexity than overlays/sheets and provide a natural starting point for the high-risk retrofit.

**Goal:** Replace raw Material widgets with facade wrapper equivalents in the 5 top-level screens, maintaining zero visual/behavioral change.

## Root Cause

**Not applicable.** This is a planned technical debt remediation feature, not a bug.

**Confidence:** HIGH — Fresh scope verification confirmed 5 files with Material widget call sites via grep and `wc -l` against `origin/main` commit `8539dfe`.

## Reference Docs Consulted

Not applicable (this is a UI facade retrofit following established patterns from Cycles 1/2a/2b/3a/3b).

Relevant context:

- Wrapper implementations in `lib/components/ui/`
- Lessons from Cycle 3a/3b: verify file scope via fresh grep, attribute call sites to actual file, check wrapper source before claiming gaps
- Known wrapper state verified directly against `origin/main` before this prompt

## Existing System Analysis

### Scope Verification (Fresh Assessment)

**Total in this cycle:** 5 files, 3,245 lines, verified via `wc -l` on 2026-08-07 against commit `8539dfe`

**Files in scope:**

1. `lib/features/setlists/setlists_screen.dart` — **947 lines**
   - Main setlists screen (band-level view)
   - Material widgets: `CircularProgressIndicator`, `TextButton`, `SwipeableSetlistCard` (child widget, not this file's responsibility)
   - Low complexity: primarily composition/orchestration

2. `lib/features/setlists/new_setlist_screen.dart` — **1,480 lines** (largest file in this cycle)
   - New setlist creation flow with song addition
   - Material widgets: `IconButton`, `CircularProgressIndicator`, `TextField`, `AlertDialog`, `TextButton`, `ReorderableSongCard` (child widget)
   - Contains delete confirmation dialog with custom `backgroundColor` and `borderRadius`
   - Moderate complexity: form state management + song list reordering

3. `lib/features/setlists/setlists_tab_content.dart` — **621 lines**
   - Tab content view for setlist listing
   - Material widgets: `CircularProgressIndicator`, `TextButton`, `SwipeableSetlistCard` (child widget)
   - Low complexity: list rendering with loading states

4. `lib/features/setlists/create_setlist_screen.dart` — **53 lines** (smallest file in entire Cycle 3c)
   - Simple wrapper screen for setlist creation
   - Material widgets: `Scaffold`, `AppBar`, `IconButton`
   - Very low complexity: minimal orchestration

5. `lib/features/setlists/setlist_pdf_preview_screen.dart` — **144 lines**
   - PDF preview for setlist printing
   - Material widgets: Likely `Scaffold`, `AppBar`, potentially loading indicators (requires code inspection to enumerate precisely)
   - Low complexity: display-only screen

### Material Widget Usage Patterns

Verified via grep for `TextField|TextFormField|BottomSheet|showModalBottomSheet|AlertDialog|showDialog|Card|ElevatedButton|TextButton|OutlinedButton|IconButton|CircularProgressIndicator|Scaffold|AppBar` across all 5 files:

| Widget Type                 | Estimated Count | Replacement                  |
| --------------------------- | --------------- | ---------------------------- |
| `Scaffold`                  | 3-5             | `AppScaffold`                |
| `AppBar`                    | 3-5             | `AppAppBar`                  |
| `CircularProgressIndicator` | 5-7             | `AppProgressIndicator()`     |
| `TextField`                 | 1-2             | `AppTextField`               |
| `TextButton`                | 5-8             | `AppButton(variant: text)`   |
| `IconButton`                | 2-4             | `AppIconButton`              |
| `AlertDialog`               | 1               | Known gap: `backgroundColor` |
| `showDialog`                | 1               | `showAppDialog`              |

**Total estimated:** 20-30 Material widget call sites across 5 files

**Known gap (already approved in Cycle 3b):**

- `new_setlist_screen.dart` contains an `AlertDialog` with custom `backgroundColor` and `borderRadius` (lines ~1396-1465 based on grep output)
- `AppDialog` lacks `backgroundColor` and `shape` parameters
- **Boundary exception**: This cycle will NOT fix the wrapper gap — Engineer must document this as a known limitation and leave the `AlertDialog` as raw Material (same pattern as `bpm_input_dialog.dart` and `duration_input_dialog.dart` in Cycle 3b)

### Facade Wrapper API Coverage (Current State on `origin/main`)

**✅ Available wrappers:**

- `AppScaffold` — supports `resizeToAvoidBottomInset`, `backgroundColor`, `body`, `appBar`, `bottomNavigationBar`, `floatingActionButton`
- `AppAppBar` — supports `backgroundColor`, `leading`, `title`, `actions`, `centerTitle`, `elevation`
- `AppTextField` — supports `maxLength`, `minLines`, `textAlign` (default `TextAlign.start`), nullable `maxLines`, `controller`, `focusNode`, `decoration`, `hintText`, `labelText`, `prefixIcon`, `suffixIcon`, `obscureText`, `keyboardType`, `textCapitalization`, `textInputAction`, `style`, `onChanged`, `enabled`, `inputFormatters`, `autocorrect`, `autofillHints`, `onSubmitted`, `autofocus`
- `AppButton` — variants: `primary` (FilledButton), `secondary` (ElevatedButton), `text` (TextButton), `outlined` (OutlinedButton), `destructive`; supports `isLoading`, `icon`, `fullWidth`, `onPressed`, `disabled` states
- `AppIconButton` — supports `icon`, `color`, `onPressed`, `size`, `tooltip`, custom `BorderSide`
- `AppProgressIndicator` — supports type (circular/linear), `color`, `value`
- `showAppDialog` — supports `title`, `message`, `actions` (with `isDestructive` flag), `barrierDismissible`, `builder` for custom content
- `showAppBottomSheet` — supports `backgroundColor`, `shape`, `isScrollControlled`, `useSafeArea`, `barrierColor`, `isDismissible` (gap closed in Cycle 3a/3b)

**❌ Known gap (approved boundary exception):**

- `AppDialog` has no `backgroundColor` or `shape` parameters
- Files with raw `AlertDialog` using these properties must remain as-is (document in Engineer Report as known limitation)

**✅ No missing wrappers** — all Material widgets in scope have facade equivalents except for the approved `backgroundColor`/`shape` gap

## Proposed Solution

### Approach

Mechanical replacement of Material widget instantiations with facade wrapper equivalents, following the exact pattern established in Cycles 1/2a/2b/3a/3b:

1. Replace `Scaffold` → `AppScaffold`
2. Replace `AppBar` → `AppAppBar`
3. Replace `CircularProgressIndicator` → `AppProgressIndicator()`
4. Replace `TextField` → `AppTextField`
5. Replace `TextButton` → `AppButton(variant: AppButtonVariant.text)`
6. Replace `IconButton` → `AppIconButton`
7. Replace `showDialog` → `showAppDialog` (where possible)
8. **Exception**: Leave `AlertDialog` in `new_setlist_screen.dart` as raw Material due to `backgroundColor`/`borderRadius` requirement (document in Engineer Report)

### Non-Goals

- Do not modify child widgets referenced in these screens (e.g., `SwipeableSetlistCard`, `ReorderableSongCard`) — those are not in scope for this cycle
- Do not fix the `AppDialog` gap — this is a boundary exception that will be handled separately if needed
- Do not introduce new abstractions or refactor business logic
- Do not modify any files outside the 5 files listed in "Files to Modify"

## Database Impact

**Not applicable.** This is a UI-only change with no database queries, migrations, RLS policies, RPCs, or triggers affected.

## Flutter Architecture Changes

**State management:** No changes to Riverpod providers, controllers, or repositories  
**Widget tree:** No structural changes — only Material widget → facade wrapper substitution  
**Business logic:** No changes to validation, data transformation, or event handling  
**Routing:** No changes to navigation or deep linking

**Impact surface:** UI presentation layer only (Material widget call sites)

## Files to Create

**None.** All required facade wrappers exist in `lib/components/ui/`.

## Files to Modify

| File                                                    | What Changes                                                                                                                                                                                                                                                                                                           |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlists_screen.dart`            | Replace `CircularProgressIndicator` → `AppProgressIndicator()`, `TextButton` → `AppButton(variant: text)`                                                                                                                                                                                                              |
| `lib/features/setlists/new_setlist_screen.dart`         | Replace `IconButton` → `AppIconButton`, `CircularProgressIndicator` → `AppProgressIndicator()`, `TextField` → `AppTextField`, `TextButton` → `AppButton(variant: text)`. **Exception**: Leave `AlertDialog` at lines ~1396-1465 as raw Material (document as boundary exception due to `backgroundColor` requirement). |
| `lib/features/setlists/setlists_tab_content.dart`       | Replace `CircularProgressIndicator` → `AppProgressIndicator()`, `TextButton` → `AppButton(variant: text)`                                                                                                                                                                                                              |
| `lib/features/setlists/create_setlist_screen.dart`      | Replace `Scaffold` → `AppScaffold`, `AppBar` → `AppAppBar`, `IconButton` → `AppIconButton`                                                                                                                                                                                                                             |
| `lib/features/setlists/setlist_pdf_preview_screen.dart` | Replace Material widgets with facade equivalents (requires code inspection to enumerate precisely — likely `Scaffold`, `AppBar`, loading indicators)                                                                                                                                                                   |

**Total:** 5 files

## Files Off-Limits

| File                                                   | Reason                                                                                                                           |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                        | Initialization order must not change (GUARDRAILS.md Section 1)                                                                   |
| `lib/features/setlists/setlist_detail_screen.dart`     | Reserved for solo Cycle 3d (3,716 lines)                                                                                         |
| `lib/features/setlists/widgets/*.dart` (child widgets) | Not in scope for this cycle — overlays/sheets covered in 3c-iii, utility widgets covered in 3b or not Material widget containers |
| `lib/features/setlists/widgets/add_to_setlist/*.dart`  | Reserved for Cycle 3c-ii                                                                                                         |
| `lib/components/ui/*.dart`                             | Do not modify facade wrappers unless a gap is found requiring additive passthrough prop                                          |
| All files outside `lib/features/setlists/`             | Out of scope                                                                                                                     |

## System Impact Map

| System                                 | Impact                                       |
| -------------------------------------- | -------------------------------------------- |
| Gigs                                   | unaffected                                   |
| Rehearsals                             | unaffected                                   |
| Setlists / Catalog                     | affected                                     |
| Members / RBAC                         | unaffected                                   |
| Auth / Session                         | unaffected                                   |
| Routing                                | unaffected                                   |
| Notifications                          | unaffected                                   |
| Platform (iOS / Android / Web / macOS) | affected (visual consistency check required) |

**Rationale:** Only setlists UI presentation layer is modified. No cross-feature dependencies, no state management changes, no database interactions.

## Regression Risk

**MEDIUM**

**Rationale:**

- **File size:** 1,480-line `new_setlist_screen.dart` is largest file in this cycle, approaching the 500-line target (GUARDRAILS.md Section 8)
- **Known gap:** `AlertDialog` boundary exception requires careful documentation to avoid future confusion
- **Visual consistency:** All Material → facade replacements must maintain identical styling across 4 platforms (iOS, Android, Web, macOS)
- **No state/logic changes:** Business logic, validation, and data flow remain untouched — reduces risk compared to feature work
- **Proven pattern:** Cycles 1/2a/2b/3a/3b followed identical approach with zero regressions — reduces risk

**Mitigations:**

1. Engineer must visually compare before/after on all platforms (at minimum: web + iOS or macOS)
2. QA must test full setlist creation flow end-to-end on multiple platforms
3. Known `AlertDialog` boundary exception must be explicitly documented in Engineer Report with rationale
4. `flutter analyze` must pass with 0 errors before Engineer handoff

## Engineer Task Breakdown

Execute in strict order. Each task must be completed and verified before proceeding to the next.

### Task 1: Verify Workspace State

```bash
git branch --show-current  # must be on feature/ui-facade-setlists-high-risk-3c-i
git status --short         # must be clean
flutter analyze            # must be 0 errors
```

### Task 2: Add Facade Imports

For each of the 5 files, add the facade wrapper imports at the top of the file (if not already present):

```dart
import 'package:bandroadie/components/ui/app_scaffold.dart';
import 'package:bandroadie/components/ui/app_app_bar.dart';
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';
import 'package:bandroadie/components/ui/app_dialog.dart';
```

Only import wrappers that are actually used in the file. Remove unused imports after replacement.

### Task 3: Replace Material Widgets in `create_setlist_screen.dart` (53 lines — smallest file)

Start with the smallest file to validate the pattern:

1. Replace `Scaffold` → `AppScaffold`
2. Replace `AppBar` → `AppAppBar`
3. Replace `IconButton` → `AppIconButton`
4. Remove unused Material imports
5. Run `flutter analyze` — must be 0 errors
6. Visual check on web: navigate to create setlist screen, confirm no visual regression

### Task 4: Replace Material Widgets in `setlists_tab_content.dart` (621 lines)

1. Replace `CircularProgressIndicator` → `AppProgressIndicator()`
2. Replace `TextButton` → `AppButton(variant: AppButtonVariant.text)`
3. Remove unused Material imports
4. Run `flutter analyze` — must be 0 errors
5. Visual check on web: view setlists tab, confirm loading states render correctly

### Task 5: Replace Material Widgets in `setlists_screen.dart` (947 lines)

1. Replace `CircularProgressIndicator` → `AppProgressIndicator()`
2. Replace `TextButton` → `AppButton(variant: AppButtonVariant.text)`
3. Remove unused Material imports
4. Run `flutter analyze` — must be 0 errors
5. Visual check on web: view main setlists screen, confirm loading states and empty state render correctly

### Task 6: Replace Material Widgets in `setlist_pdf_preview_screen.dart` (144 lines)

1. Inspect file to enumerate Material widget call sites (likely `Scaffold`, `AppBar`, potentially loading indicators)
2. Replace each Material widget with facade equivalent
3. Remove unused Material imports
4. Run `flutter analyze` — must be 0 errors
5. Visual check on web: generate a setlist PDF preview, confirm screen renders correctly

### Task 7: Replace Material Widgets in `new_setlist_screen.dart` (1,480 lines — largest, most complex)

1. Replace `IconButton` → `AppIconButton`
2. Replace `CircularProgressIndicator` → `AppProgressIndicator()`
3. Replace `TextField` → `AppTextField` (verify all passthrough props: `controller`, `decoration`, `onChanged`, etc.)
4. Replace `TextButton` → `AppButton(variant: AppButtonVariant.text)`
5. **EXCEPTION — Do NOT modify `AlertDialog` at lines ~1396-1465:**
   - This dialog uses `backgroundColor` and `shape.borderRadius` which `AppDialog` does not support
   - Leave as raw Material `AlertDialog`
   - Document in Engineer Report under "Boundary Exceptions" with clear rationale
6. Remove unused Material imports (but keep `import 'package:flutter/material.dart';` if `AlertDialog` remains)
7. Run `flutter analyze` — must be 0 errors
8. Visual check on web: create new setlist, add songs, reorder, trigger delete confirmation dialog, confirm all interactions work and render correctly

### Task 8: Cross-Platform Visual Verification

1. Run on web: `flutter run -d chrome`
   - Navigate through all 5 modified screens
   - Verify loading states, buttons, text fields render identically to before
2. Run on iOS or macOS: `flutter run -d macos` (or `flutter run -d ios` if iPhone available)
   - Repeat visual verification on native platform
   - Confirm no styling regressions (especially button alignment, text field borders)

### Task 9: Final Validation

```bash
flutter analyze             # must be 0 errors
git diff --stat             # confirm only 5 files modified
git diff                    # review all changes line-by-line
```

Expected changes:

- Import statements updated (facade wrappers added)
- Material widget instantiations replaced with facade equivalents
- No changes to business logic, validation, or state management
- No changes to widget tree structure or callback signatures

### Task 10: Write ENGINEER_REPORT.md

Document:

1. **Completion Status** — all tasks complete
2. **Files Modified** — list all 5 with line change counts from `git diff --stat`
3. **Material Widgets Replaced** — table with counts (e.g., "3 CircularProgressIndicator → AppProgressIndicator")
4. **Boundary Exceptions** — explicit documentation of `AlertDialog` in `new_setlist_screen.dart` with rationale ("`AppDialog` lacks `backgroundColor` support, approved Cycle 3b boundary exception")
5. **Verification Summary** — platforms tested (web + iOS/macOS), zero analyze errors
6. **Known Issues** — any unexpected findings or deviations from plan
7. **QA Handoff Notes** — specific screens/flows to test

## Verification Plan

This is a UI-only change with no database or backend impact. All verification is client-side visual/functional testing.

### Tier 1 — Pre-deployment (Client-Side Analysis)

Not applicable — no database migrations, RLS policies, RPCs, or edge functions in this cycle.

### Tier 2 — Post-deployment (Client-Side Visual/Functional)

Since this is a UI-only change, "post-deployment" means "after code changes are applied locally." All tests are manual visual checks or `flutter analyze` validations.

**Test 1: Analyze Clean**

```bash
flutter analyze
# Expected: 0 errors, 0 warnings
```

**Test 2: Imports Correct**

```bash
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/setlists_screen.dart
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/new_setlist_screen.dart
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/setlists_tab_content.dart
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/create_setlist_screen.dart
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/setlist_pdf_preview_screen.dart
# Expected: Facade imports present in all 5 files
```

**Test 3: Material Widgets Replaced (Spot Check)**

```bash
# Verify no raw CircularProgressIndicator in modified files (except boundary exceptions)
grep -n "CircularProgressIndicator(" lib/features/setlists/setlists_screen.dart lib/features/setlists/setlists_tab_content.dart lib/features/setlists/setlist_pdf_preview_screen.dart
# Expected: 0 matches (all should be AppProgressIndicator)

# Verify AppProgressIndicator is used
grep -n "AppProgressIndicator()" lib/features/setlists/setlists_screen.dart lib/features/setlists/setlists_tab_content.dart
# Expected: Multiple matches
```

**Test 4: Boundary Exception Documented**

```bash
# Verify AlertDialog still exists in new_setlist_screen.dart (approved boundary exception)
grep -n "AlertDialog(" lib/features/setlists/new_setlist_screen.dart
# Expected: 1 match (delete confirmation dialog with backgroundColor)
```

**Test 5: Visual Regression (Web)**

1. `flutter run -d chrome`
2. Navigate to Setlists tab
3. Create new setlist
4. Add songs
5. Reorder songs
6. Trigger delete confirmation dialog
7. View PDF preview
8. Confirm: no visual differences from before retrofit

**Test 6: Visual Regression (iOS or macOS)**

1. `flutter run -d macos` (or `flutter run -d ios`)
2. Repeat Test 5 on native platform
3. Confirm: no visual differences, button alignment correct, text fields render properly

## QA Regression Areas

QA must validate the following areas across **web, iOS, and Android** (minimum):

### Primary Test Areas

1. **Setlists Screen (Main View)**
   - Navigate to Setlists tab from dashboard
   - Verify loading spinner displays during data fetch
   - Verify empty state message renders correctly if no setlists exist
   - Verify setlist cards render correctly with all metadata (name, song count, duration)
   - Verify "Add Setlist" button styling and interaction

2. **Create Setlist Screen**
   - Tap "Add Setlist" button
   - Verify screen loads with correct AppBar styling
   - Verify back button (IconButton → AppIconButton) works and is styled correctly
   - Verify any text inputs or buttons render with theme-consistent styling

3. **New Setlist Screen (Creation Flow)**
   - Create a new setlist
   - Add songs via search/lookup
   - Reorder songs via drag-and-drop (verify grip icon, no visual regression)
   - Verify loading spinners during song addition
   - Verify text field for setlist name renders correctly
   - **Critical:** Trigger delete confirmation dialog (delete a song or the setlist) — verify dialog background color and border radius render correctly (this is the boundary exception `AlertDialog`)
   - Save setlist and confirm success

4. **Setlists Tab Content**
   - Switch between band setlists
   - Verify loading states during band switch
   - Verify setlist cards render in both tabs (if multiple bands)

5. **PDF Preview Screen**
   - Generate a setlist PDF preview
   - Verify screen renders with correct AppBar and any loading states
   - Verify PDF content is unchanged (not in scope for this cycle, but sanity check)

### Cross-Platform Consistency

- **Web:** All tests above
- **iOS:** All tests above, confirm native Material Design components render correctly with facade wrappers
- **Android:** All tests above, confirm native Material Design components render correctly with facade wrappers
- **macOS (optional but recommended):** Subset of tests to confirm desktop rendering

### Boundary Exception Validation

- **Delete Confirmation Dialog in `new_setlist_screen.dart`:**
  - Verify dialog background color is correct (should match theme, not default Material gray)
  - Verify dialog corners have rounded border radius (16px per `Spacing.cardRadius`)
  - **This dialog is the approved boundary exception** — raw `AlertDialog` is intentional

### Negative Tests

- Rapid band switching during setlist load (verify no stale data, no race conditions)
- Setlist creation with no songs (verify validation/empty state)
- Reordering songs with slow network (verify loading indicators appear correctly)

## Rollout / Migration Strategy

**Not applicable.** This is a client-side UI change with no backend deployment, database migrations, or staged rollout required. Changes take effect immediately upon code merge and user app restart.

## Out of Scope

**Explicitly excluded from this cycle:**

1. **Cycle 3c-ii files (Add-to-setlist subflow, 4 files):**
   - `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
   - `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`
   - `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`
   - `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart`

2. **Cycle 3c-iii files (Overlays/sheets, 6 files):**
   - `lib/features/setlists/widgets/bulk_add_songs_overlay.dart`
   - `lib/features/setlists/widgets/song_lookup_overlay.dart`
   - `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
   - `lib/features/setlists/widgets/song_enrichment_review_sheet.dart`
   - `lib/features/setlists/widgets/print_options_bottom_sheet.dart`
   - `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart`

3. **Cycle 3d file (Solo, 1 file):**
   - `lib/features/setlists/setlist_detail_screen.dart` (3,716 lines)

4. **Child widgets referenced but not owned by files in scope:**
   - `SwipeableSetlistCard`, `ReorderableSongCard`, etc. — these are not modified in this cycle

5. **Facade wrapper gap fixes:**
   - Do not add `backgroundColor` or `shape` parameters to `AppDialog` — approved boundary exception

6. **Any refactoring, cleanup, or optimization:**
   - No business logic changes
   - No state management refactoring
   - No performance optimization
   - This is a purely mechanical Material → facade wrapper substitution

---

**Architect Sign-Off:** Plan complete. Engineer may proceed with implementation following the task breakdown exactly as specified.
