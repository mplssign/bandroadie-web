# Architect Plan — UI Facade Setlists Low/Medium Risk Retrofit

## Feature Slug

`feature/ui-facade-setlists-low-medium-risk`

## Problem Summary

The setlists domain (`lib/features/setlists/`) contains 27 files with raw Material widget call sites out of 64 total files. This is Cycle 3b of the UI facade migration (Piece 3), following Cycle 3a (gigs + events, merged as PR #129 / commit `18ff085`).

This cycle retrofits only the LOW and MEDIUM-risk subset: small utility dialogs, pickers, and helper widgets — specifically the 11 files with <700 lines that have minimal business logic complexity and no cross-feature dependencies. The HIGH-risk files (large screens, overlays, and the 3,716-line `setlist_detail_screen.dart`) are explicitly deferred to Cycles 3c and 3d per the established risk-ascending pattern proven across Cycles 1/2a/2b/3a.

**Goal:** Replace raw Material widgets with facade wrapper equivalents in the LOW/MEDIUM-risk subset, maintaining zero visual/behavioral change.

## Root Cause

**Not applicable.** This is a planned technical debt remediation feature, not a bug.

**Confidence:** HIGH — Fresh grep confirmed 27 files with Material call sites; line count analysis identified 11 LOW/MEDIUM-risk files totaling ~42 call sites.

## Reference Docs Consulted

Not applicable (this is a UI facade retrofit, not a notifications domain feature per ARCHITECT.md Phase 4 scope).

Relevant reference:

- Feature input lessons from Cycle 3a (attribute call sites to actual file, not parent; verify wrapper API support before claiming gaps)
- Current facade wrapper implementations in `lib/components/ui/`

## Existing System Analysis

### Setlists Domain File Inventory (Fresh Assessment)

**Total:** 64 Dart files  
**With Material imports:** 42 files  
**With Material widget call sites:** 27 files (confirmed via grep for `TextField|TextButton|showModalBottomSheet|AlertDialog|CircularProgressIndicator`, etc.)

### Risk Classification (Line Count + Complexity)

**LOW RISK — 6 files (<300 lines, simple dialogs/pickers):**

1. `widgets/back_only_app_bar.dart` — 98 lines, 1 call site (`CircularProgressIndicator`)
2. `widgets/key_picker_bottom_sheet.dart` — 192 lines, 3 call sites (`showModalBottomSheet`, `ListTile`, `TextButton`)
3. `widgets/duration_input_dialog.dart` — 205 lines, 5 call sites (`AlertDialog`, `TextField`, `TextButton` ×3)
4. `widgets/bpm_input_dialog.dart` — 219 lines, 5 call sites (`AlertDialog`, `TextField`, `TextButton` ×3)
5. `widgets/song_notes_drawer.dart` — 261 lines, 5 call sites (`showModalBottomSheet`, `TextField`, `FilledButton` ×2, `TextButton`, `Divider`)
6. `widgets/set_break_creator.dart` — 295 lines, 1 call site (`ElevatedButton`)

**MEDIUM RISK — 5 files (300-700 lines, moderate complexity):** 7. `widgets/masked_duration_input.dart` — 415 lines, 1 call site (`TextField`) + custom `TextInputFormatter` (business logic) 8. `widgets/reorderable_song_card.dart` — 524 lines, 1 call site (`CircularProgressIndicator`) + drag/drop via `ReorderableDragStartListener` 9. `widgets/pause_creator.dart` — 567 lines, 3 call sites (`showModalBottomSheet`, `TextField` ×2, `ElevatedButton`) 10. `widgets/custom_tuning_modal.dart` — 581 lines, 6 call sites (`showModalBottomSheet`, `TextField` ×2, `OutlinedButton`, `ElevatedButton`, `CircularProgressIndicator`) 11. `widgets/setlist_picker_bottom_sheet.dart` — 687 lines, 5 call sites (`showModalBottomSheet`, `TextField`, `IconButton`, `OutlinedButton`, `FilledButton`, `Divider`)

**Total in scope:** 11 files, ~42 Material widget call sites

**HIGH RISK (DEFERRED to Cycles 3c/3d):**

- Top-level screens: `setlists_screen.dart` (947 lines), `new_setlist_screen.dart` (1,480 lines), `setlists_tab_content.dart` (621 lines), `create_setlist_screen.dart` (53 lines), `setlist_pdf_preview_screen.dart` (144 lines)
- Large overlays/sheets: `bulk_add_songs_overlay.dart` (895 lines), `song_lookup_overlay.dart` (1,163 lines), `song_details_bottom_sheet.dart` (1,649 lines), `song_enrichment_review_sheet.dart` (501 lines), `print_options_bottom_sheet.dart` (958 lines)
- Tuning picker: `tuning_picker_bottom_sheet.dart` (1,097 lines) ← incorrectly suggested as MEDIUM in feature input; fresh assessment shows HIGH risk
- Add-to-setlist subdirectory: all 7 files under `widgets/add_to_setlist/` (complex multi-screen flows)
- **CYCLE 3d (solo):** `setlist_detail_screen.dart` (3,716 lines) — the single riskiest file in the entire app

### Facade Wrapper API Coverage (Verified)

**✅ Available wrappers:**

- `AppProgressIndicator` (wraps `CircularProgressIndicator`/`LinearProgressIndicator`)
- `AppBottomSheet.show()` / `showAppBottomSheet()` — supports `backgroundColor`, `shape`, `isScrollControlled`
- `AppTextField` — supports `maxLength`, `minLines` (added in Cycle 3a per feature input)
- `AppButton` — variants: `primary` (FilledButton), `secondary` (ElevatedButton), `text` (TextButton), `outlined` (OutlinedButton), `destructive`
- `AppIconButton` (wraps `IconButton`)
- `AppDialog` / `showAppDialog()` — **KNOWN GAP:** no `backgroundColor`/`shape`/custom `TextStyle` support

**❌ Missing wrappers (boundary exceptions):**

- `ListTile` — no `AppListTile` wrapper exists; must use raw Material
- `Divider` — no `AppDivider` wrapper exists; must use raw Material

### Material Widget Usage Patterns in Scope

| Widget Type                 | Count | Replacement                                                    |
| --------------------------- | ----- | -------------------------------------------------------------- |
| `CircularProgressIndicator` | 3     | `AppProgressIndicator()`                                       |
| `showModalBottomSheet`      | 5     | `showAppBottomSheet()`                                         |
| `TextField`                 | 11    | `AppTextField`                                                 |
| `AlertDialog`               | 2     | `AppDialog` (boundary: custom `backgroundColor` not supported) |
| `TextButton`                | 7     | `AppButton(variant: AppButtonVariant.text)`                    |
| `FilledButton`              | 3     | `AppButton(variant: AppButtonVariant.primary)`                 |
| `ElevatedButton`            | 2     | `AppButton(variant: AppButtonVariant.secondary)`               |
| `OutlinedButton`            | 2     | `AppButton(variant: AppButtonVariant.outlined)`                |
| `IconButton`                | 1     | `AppIconButton`                                                |
| `ListTile`                  | 1     | BOUNDARY: Keep raw `ListTile` (no wrapper)                     |
| `Divider`                   | 2     | BOUNDARY: Keep raw `Divider` (no wrapper)                      |

**Total:** ~39 call sites replaceable, 3 boundary exceptions (raw Material retained)

## Proposed Solution

### Approach

1. Replace Material widget instantiations with facade wrappers per the mapping above
2. Preserve all custom `TextInputFormatter` logic (business logic, not styling)
3. Preserve `ReorderableDragStartListener` and gesture detectors (not Material widgets)
4. Document boundary exceptions as tracked gaps (not blockers)
5. Maintain exact visual/behavioral parity — no opportunistic refactoring

### Boundary Exceptions (Document, Don't Block)

**Exception 1: `AlertDialog` backgroundColor**

- **Files affected:** `bpm_input_dialog.dart`, `duration_input_dialog.dart`
- **Issue:** Both dialogs set `AlertDialog(backgroundColor: context.colors.surface)` but `AppDialog` has no `backgroundColor` parameter
- **Resolution:** Use `showDialog` with raw `AlertDialog` for these 2 files, wrap in try-catch for safety. Document as tracked gap in ENGINEER_REPORT.md with reference to Cycle 3a precedent (gig/event dialogs hit the same issue)
- **Non-blocking:** Dialogs still function correctly; this is a known cosmetic limitation pending future facade enhancement

**Exception 2: `showModalBottomSheet` transparent background**

- **Files affected:** `set_break_creator.dart`, `pause_creator.dart`, `custom_tuning_modal.dart`, `setlist_picker_bottom_sheet.dart`
- **Issue:** These sheets use `backgroundColor: Colors.transparent` to achieve custom glass/dimmed effects
- **Resolution:** `showAppBottomSheet()` supports `backgroundColor` parameter — pass `Colors.transparent` explicitly. Verify no visual regression.
- **Non-blocking:** Facade supports this use case

**Exception 3: `ListTile` and `Divider` (no wrappers)**

- **Files affected:** `key_picker_bottom_sheet.dart` (ListTile), `song_notes_drawer.dart` (Divider), `setlist_picker_bottom_sheet.dart` (Divider)
- **Issue:** No `AppListTile` or `AppDivider` wrappers exist
- **Resolution:** Keep raw Material widgets. These are low-churn, low-risk widgets with stable APIs.
- **Non-blocking:** Acceptable boundary per Cycle 3a precedent (similar exceptions documented and approved)

### Change Strategy

- Modify exactly 11 files (the in-scope LOW/MEDIUM-risk files)
- Estimated ~36 net call site replacements (42 total minus 3 boundary exceptions that stay raw + potential consolidation)
- Add facade imports: `import 'package:bandroadie/components/ui/<wrapper>.dart';`
- Remove unused Material imports where fully replaced (keep Material import if boundary exceptions remain)
- No new abstractions, no new files, no database changes

## Database Impact

**Not applicable.** This is a pure Flutter UI retrofit with zero database interaction changes.

## Flutter Architecture Changes

### State Management

**Not affected.** Riverpod providers, controllers, and state classes remain unchanged. Facade wrappers delegate to Material widgets with identical behavior.

### Widget Tree Structure

**Not affected.** Facade wrappers are drop-in replacements; widget tree structure and build methods remain unchanged.

### Imports

**Modified:** Each of the 11 files will add 1–4 facade import statements and may remove the Material import if fully replaced (keep if boundary exceptions require raw widgets).

Example:

```dart
// Before
import 'package:flutter/material.dart';

// After (full replacement)
import 'package:flutter/material.dart'; // Keep for Colors, BuildContext extensions, etc.
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:bandroadie/components/ui/app_dialog.dart';
```

## Files to Create

**None.** All facade wrappers already exist in `lib/components/ui/`.

## Files to Modify

| File                                                             | Changes                                                                                                                                                                                                                                                                                                                     | Call Sites             |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| `lib/features/setlists/widgets/back_only_app_bar.dart`           | Replace `CircularProgressIndicator` with `AppProgressIndicator`                                                                                                                                                                                                                                                             | 1                      |
| `lib/features/setlists/widgets/key_picker_bottom_sheet.dart`     | Replace `showModalBottomSheet` with `showAppBottomSheet`, `TextButton` with `AppButton.text`; KEEP raw `ListTile` (boundary)                                                                                                                                                                                                | 2 replaced, 1 boundary |
| `lib/features/setlists/widgets/bpm_input_dialog.dart`            | Replace `TextField` with `AppTextField`, `TextButton` with `AppButton.text`; KEEP raw `AlertDialog` (boundary: backgroundColor)                                                                                                                                                                                             | 4 replaced, 1 boundary |
| `lib/features/setlists/widgets/duration_input_dialog.dart`       | Replace `TextField` with `AppTextField`, `TextButton` with `AppButton.text`; KEEP raw `AlertDialog` (boundary: backgroundColor)                                                                                                                                                                                             | 4 replaced, 1 boundary |
| `lib/features/setlists/widgets/song_notes_drawer.dart`           | Replace `showModalBottomSheet` with `showAppBottomSheet`, `TextField` with `AppTextField`, `FilledButton` with `AppButton.primary`, `TextButton` with `AppButton.text`; KEEP raw `Divider` (boundary)                                                                                                                       | 5 replaced, 1 boundary |
| `lib/features/setlists/widgets/set_break_creator.dart`           | Replace `showModalBottomSheet` with `showAppBottomSheet(backgroundColor: Colors.transparent)`, `ElevatedButton` with `AppButton.secondary`                                                                                                                                                                                  | 2                      |
| `lib/features/setlists/widgets/masked_duration_input.dart`       | Replace `TextField` with `AppTextField`; PRESERVE custom `TextInputFormatter` logic                                                                                                                                                                                                                                         | 1                      |
| `lib/features/setlists/widgets/reorderable_song_card.dart`       | Replace `CircularProgressIndicator` with `AppProgressIndicator`; PRESERVE `ReorderableDragStartListener`                                                                                                                                                                                                                    | 1                      |
| `lib/features/setlists/widgets/pause_creator.dart`               | Replace `showModalBottomSheet` with `showAppBottomSheet(backgroundColor: Colors.transparent)`, `TextField` (×2) with `AppTextField`, `ElevatedButton` with `AppButton.secondary`                                                                                                                                            | 4                      |
| `lib/features/setlists/widgets/custom_tuning_modal.dart`         | Replace `showModalBottomSheet` with `showAppBottomSheet(backgroundColor: Colors.transparent)`, `TextField` (×2) with `AppTextField`, `OutlinedButton` with `AppButton.outlined`, `ElevatedButton` with `AppButton.secondary`, `CircularProgressIndicator` with `AppProgressIndicator`; PRESERVE custom `TextInputFormatter` | 6                      |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` | Replace `showModalBottomSheet` with `showAppBottomSheet(backgroundColor: Colors.transparent)`, `TextField` with `AppTextField`, `IconButton` with `AppIconButton`, `OutlinedButton` with `AppButton.outlined`, `FilledButton` with `AppButton.primary`; KEEP raw `Divider` (boundary)                                       | 5 replaced, 1 boundary |

**Total:** 11 files modified, ~36 call sites replaced, 6 boundary exceptions documented

## Files Off-Limits

| File                                                    | Reason                                                       |
| ------------------------------------------------------- | ------------------------------------------------------------ |
| `lib/main.dart`                                         | Initialization order must not change                         |
| `lib/app/theme/**`                                      | Theme definitions are stable; no facade changes needed       |
| `lib/components/ui/**`                                  | Facade wrappers themselves are off-limits (no modifications) |
| `lib/features/setlists/setlist_detail_screen.dart`      | 3,716 lines — deferred to Cycle 3d (solo)                    |
| `lib/features/setlists/tuning_picker_bottom_sheet.dart` | 1,097 lines — HIGH risk, deferred to Cycle 3c                |
| All HIGH-risk setlists files (9 screens/overlays)       | Deferred to Cycle 3c per risk-ascending pattern              |
| All `widgets/add_to_setlist/*.dart` (7 files)           | Multi-screen flows, deferred to Cycle 3c                     |
| Any file outside `lib/features/setlists/widgets/`       | Out of scope for this cycle                                  |

## System Impact Map

| System                                 | Impact                                                                                               |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Gigs                                   | **Unaffected** — no cross-feature calls                                                              |
| Rehearsals                             | **Unaffected** — no cross-feature calls                                                              |
| Setlists / Catalog                     | **Affected (isolated)** — only the 11 in-scope widget files; no repository/controller changes        |
| Members / RBAC                         | **Unaffected**                                                                                       |
| Auth / Session                         | **Unaffected**                                                                                       |
| Routing                                | **Unaffected**                                                                                       |
| Notifications                          | **Unaffected**                                                                                       |
| Platform (iOS / Android / Web / macOS) | **Unaffected** — facade wrappers delegate to Material widgets with identical cross-platform behavior |

## Regression Risk

**Overall Risk:** **LOW**

**Rationale:**

1. **Isolated scope:** Only 11 utility widgets in a single feature domain (setlists); no cross-feature dependencies
2. **No state/repository changes:** Pure widget-layer substitution with facade wrappers that delegate to identical Material widgets
3. **Zero behavioral change:** Facade wrappers are 1:1 Material delegates; no business logic modified
4. **Proven pattern:** Cycles 1/2a/2b/3a followed this exact approach with zero production regressions
5. **Small diff surface:** ~36 call site replacements across 11 files (average 3.3 per file)
6. **No init/routing/auth touched:** All high-risk systems untouched
7. **Boundary exceptions documented:** 6 known raw Material retentions are intentional, not oversights

**Risk factors (mitigated):**

- Custom `TextInputFormatter` logic in `masked_duration_input.dart` and `custom_tuning_modal.dart` — mitigation: preserve exactly, no refactoring
- Drag/drop in `reorderable_song_card.dart` — mitigation: only replace `CircularProgressIndicator`, leave `ReorderableDragStartListener` untouched
- Transparent backgrounds in 4 bottom sheets — mitigation: verify `showAppBottomSheet(backgroundColor: Colors.transparent)` renders identically

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Verify Facade Wrapper APIs

1. Read `lib/components/ui/app_progress_indicator.dart` — confirm usage: `AppProgressIndicator()` (no constructor params needed for default circular)
2. Read `lib/components/ui/app_bottom_sheet.dart` — confirm `showAppBottomSheet()` signature supports `backgroundColor`, `shape`, `isScrollControlled`
3. Read `lib/components/ui/app_text_field.dart` — confirm `AppTextField` supports `decoration`, `inputFormatters`, `maxLines`, `minLines`, `maxLength`
4. Read `lib/components/ui/app_button.dart` — confirm `AppButton` supports `variant` enum with `primary`, `secondary`, `text`, `outlined`
5. Read `lib/components/ui/app_icon_button.dart` — confirm `AppIconButton` signature
6. Document any API gaps not already covered in the boundary exceptions above

**Deliverable:** Brief verification note in ENGINEER_REPORT.md under "Facade API Verification" section

### Task 2: Replace Material Widgets — LOW Risk Files (Batch 1)

Modify these 6 files in parallel (independent, no shared state):

**2a. `widgets/back_only_app_bar.dart`**

- Add import: `import 'package:bandroadie/components/ui/app_progress_indicator.dart';`
- Replace: `CircularProgressIndicator(...)` → `AppProgressIndicator()`
- Verify: Loading spinner still renders in top-right corner of app bar

**2b. `widgets/key_picker_bottom_sheet.dart`**

- Add import: `import 'package:bandroadie/components/ui/app_bottom_sheet.dart';` and `import 'package:bandroadie/components/ui/app_button.dart';`
- Replace: `showModalBottomSheet(...)` → `showAppBottomSheet(...)`
- Replace: `TextButton(...)` → `AppButton(variant: AppButtonVariant.text, ...)`
- KEEP: Raw `ListTile` (boundary exception)
- Verify: Bottom sheet slides up, keys selectable, cancel button works

**2c. `widgets/bpm_input_dialog.dart`**

- Add import: `import 'package:bandroadie/components/ui/app_text_field.dart';` and `import 'package:bandroadie/components/ui/app_button.dart';`
- Replace: `TextField(...)` → `AppTextField(decoration: InputDecoration(...))`
- Replace: `TextButton(...)` (×3 Cancel/Clear/Save) → `AppButton(variant: AppButtonVariant.text, ...)`
- KEEP: Raw `AlertDialog(backgroundColor: context.colors.surface, ...)` — boundary exception; use `showDialog` directly
- Verify: Dialog opens, BPM input validates (20-300), Save/Clear/Cancel work

**2d. `widgets/duration_input_dialog.dart`**

- Add import: `import 'package:bandroadie/components/ui/app_text_field.dart';` and `import 'package:bandroadie/components/ui/app_button.dart';`
- Replace: `TextField(...)` → `AppTextField(decoration: InputDecoration(...), inputFormatters: [_DurationFormatter()])`
- Replace: `TextButton(...)` (×3 Cancel/Clear/Save) → `AppButton(variant: AppButtonVariant.text, ...)`
- KEEP: Raw `AlertDialog(backgroundColor: context.colors.surface, ...)` — boundary exception
- PRESERVE: `_DurationFormatter` class unchanged
- Verify: Dialog opens, MM:SS formatting works, Save/Clear/Cancel work

**2e. `widgets/song_notes_drawer.dart`**

- Add imports: `import 'package:bandroadie/components/ui/app_bottom_sheet.dart';`, `import 'package:bandroadie/components/ui/app_text_field.dart';`, `import 'package:bandroadie/components/ui/app_button.dart';`
- Replace: `showModalBottomSheet(...)` → `showAppBottomSheet(...)`
- Replace: `TextField(...)` → `AppTextField(...)`
- Replace: `FilledButton(...)` (×2 Save/Edit) → `AppButton(variant: AppButtonVariant.primary, ...)`
- Replace: `TextButton(...)` (Cancel) → `AppButton(variant: AppButtonVariant.text, ...)`
- KEEP: Raw `Divider(...)` (boundary exception)
- Verify: Drawer opens, view/edit mode toggle, Save/Cancel work, keyboard dismisses correctly

**2f. `widgets/set_break_creator.dart`**

- Add imports: `import 'package:bandroadie/components/ui/app_bottom_sheet.dart';`, `import 'package:bandroadie/components/ui/app_button.dart';`
- Replace: `showModalBottomSheet(backgroundColor: Colors.transparent, ...)` → `showAppBottomSheet(backgroundColor: Colors.transparent, ...)`
- Replace: `ElevatedButton(...)` → `AppButton(variant: AppButtonVariant.secondary, ...)`
- Verify: Sheet animates up with transparent background, +/− buttons work, Add Set Break works

**Deliverable:** 6 files modified, ~20 call sites replaced

### Task 3: Replace Material Widgets — MEDIUM Risk Files (Batch 2)

Modify these 5 files sequentially (due to higher complexity):

**3a. `widgets/masked_duration_input.dart`**

- Add import: `import 'package:bandroadie/components/ui/app_text_field.dart';`
- Replace: `TextField(...)` → `AppTextField(...)`
- PRESERVE: `_DurationInputFormatter` class and all masking logic UNCHANGED
- PRESERVE: `KeyboardListener`, `GestureDetector`, `AbsorbPointer` — these are low-level event handlers, not Material widgets
- Verify: MM:SS masked input still works (digits shift left, backspace works), cursor stays at end

**3b. `widgets/reorderable_song_card.dart`**

- Add import: `import 'package:bandroadie/components/ui/app_progress_indicator.dart';`
- Replace: `CircularProgressIndicator(...)` → `AppProgressIndicator()`
- PRESERVE: `ReorderableDragStartListener`, `GestureDetector`, `AnimatedBuilder` — not Material widgets
- Verify: Saving indicator appears during tuning edit, drag handle still works

**3c. `widgets/pause_creator.dart`**

- Add imports: `import 'package:bandroadie/components/ui/app_bottom_sheet.dart';`, `import 'package:bandroadie/components/ui/app_text_field.dart';`, `import 'package:bandroadie/components/ui/app_button.dart';`
- Replace: `showModalBottomSheet(backgroundColor: Colors.transparent, ...)` → `showAppBottomSheet(backgroundColor: Colors.transparent, ...)`
- Replace: `TextField(...)` (×2 custom purpose, minutes/seconds) → `AppTextField(...)`
- Replace: `ElevatedButton(...)` → `AppButton(variant: AppButtonVariant.secondary, ...)`
- PRESERVE: `_MaxValueFormatter` class, `_PurposeChip` widget, animations
- Verify: Sheet animates up, purpose chips toggle, custom purpose input works, duration fields validate, Add Pause works

**3d. `widgets/custom_tuning_modal.dart`**

- Add imports: `import 'package:bandroadie/components/ui/app_bottom_sheet.dart';`, `import 'package:bandroadie/components/ui/app_text_field.dart';`, `import 'package:bandroadie/components/ui/app_button.dart';`, `import 'package:bandroadie/components/ui/app_progress_indicator.dart';`
- Replace: `showModalBottomSheet(backgroundColor: Colors.transparent, ...)` → `showAppBottomSheet(backgroundColor: Colors.transparent, ...)`
- Replace: `TextField(...)` (×2 strings, name) → `AppTextField(...)`
- Replace: `OutlinedButton(...)` (Cancel) → `AppButton(variant: AppButtonVariant.outlined, ...)`
- Replace: `ElevatedButton(...)` (Save) → `AppButton(variant: AppButtonVariant.secondary, ...)`
- Replace: `CircularProgressIndicator(...)` → `AppProgressIndicator()`
- PRESERVE: `_StringsInputFormatter` class and all uppercase/space-collapsing logic UNCHANGED
- Verify: Modal animates up, strings input validates (A-G + # + b), name input validates, Save/Cancel work, loading spinner shows during save

**3e. `widgets/setlist_picker_bottom_sheet.dart`**

- Add imports: `import 'package:bandroadie/components/ui/app_bottom_sheet.dart';`, `import 'package:bandroadie/components/ui/app_text_field.dart';`, `import 'package:bandroadie/components/ui/app_button.dart';`, `import 'package:bandroadie/components/ui/app_icon_button.dart';`
- Replace: `showModalBottomSheet(backgroundColor: Colors.transparent, ...)` → `showAppBottomSheet(backgroundColor: Colors.transparent, ...)`
- Replace: `TextField(...)` → `AppTextField(...)`
- Replace: `IconButton(...)` (close) → `AppIconButton(...)`
- Replace: `OutlinedButton(...)` (Cancel in create form) → `AppButton(variant: AppButtonVariant.outlined, ...)`
- Replace: `FilledButton(...)` (Create & Add) → `AppButton(variant: AppButtonVariant.primary, ...)`
- KEEP: Raw `Divider(...)` (boundary exception)
- KEEP: `Material` + `InkWell` for `_SetlistOptionTile` ripple effect (not a Material widget call site, it's a Material widget composition for ripple)
- Verify: Sheet animates up, setlist list renders, create new form works, Move/Copy toggle works, keyboard dismisses correctly

**Deliverable:** 5 files modified, ~16 call sites replaced

### Task 4: Clean Up Imports

For each of the 11 modified files:

1. Remove unused Material imports ONLY if ALL Material widgets replaced AND no boundary exceptions remain
2. Keep Material import if:
   - Boundary exceptions exist (raw `AlertDialog`, `ListTile`, `Divider`, `Material+InkWell`)
   - Using `Colors`, `BuildContext` extensions, `TextInputFormatter`, or other Material non-widget APIs
3. Run `flutter analyze` — must show 0 errors

**Deliverable:** Clean import statements, 0 analyzer errors

### Task 5: Verification Testing (Manual)

Test each modified widget in the running app:

**LOW risk files:**

1. **back_only_app_bar.dart**: Navigate to any setlist detail screen → trigger a save operation → verify loading spinner renders
2. **key_picker_bottom_sheet.dart**: Edit a song's key → verify bottom sheet opens, keys selectable, cancel works
3. **bpm_input_dialog.dart**: Tap a song's BPM → verify dialog opens, validation works, Save/Clear/Cancel work
4. **duration_input_dialog.dart**: Tap a song's duration → verify dialog opens, MM:SS formatting works, Save/Clear/Cancel work
5. **song_notes_drawer.dart**: Long-press a song → tap Notes → verify drawer opens, view/edit toggle works, Save/Cancel work
6. **set_break_creator.dart**: In setlist detail → tap + → Add Set Break → verify sheet animates, +/− buttons work, Add works

**MEDIUM risk files:** 7. **masked_duration_input.dart**: (Used in pause_creator/set_break_creator duration fields) → verify MM:SS masking still works 8. **reorderable_song_card.dart**: In setlist detail → verify loading spinner during tuning edit, drag handle works 9. **pause_creator.dart**: In setlist detail → tap + → Add Pause → verify purpose chips toggle, custom purpose input works, duration fields work, Add Pause works 10. **custom_tuning_modal.dart**: Edit song tuning → tap "Add Custom" → verify strings input validates, name input validates, Save/Cancel work 11. **setlist_picker_bottom_sheet.dart**: In Catalog → select songs → Add To Setlist → verify sheet opens, list renders, create new works, Move/Copy toggle works

**Acceptance criteria:**

- All 11 widgets render identically to pre-retrofit
- No visual regressions (colors, spacing, borders, animations)
- No behavioral regressions (validation, keyboard handling, navigation)
- No console errors or analyzer warnings

**Deliverable:** Verification checklist completed, no regressions found

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable.** This is a pure Flutter UI retrofit with zero database changes. No SQL tests required.

### Tier 2 — Post-deployment

**Not applicable.** No database migrations or edge functions involved. Flutter analyze and manual testing are the verification gates.

### Flutter-Specific Verification

**Static Analysis:**

```bash
flutter analyze
```

**Expected:** 0 errors, 0 warnings related to the 11 modified files

**Manual Smoke Test (per Task 5 checklist):**

- Execute each of the 11 widget verification steps in a running app (web or macOS for fast iteration)
- Confirm zero visual/behavioral regressions
- Confirm boundary exceptions render correctly (raw `AlertDialog`, `ListTile`, `Divider`)

## QA Regression Areas

QA must explicitly test:

**Core setlists functionality (unaffected by this change but validate stability):**

1. Catalog browsing and song selection
2. Setlist creation and editing
3. Bulk song entry and parsing
4. Reorder songs within a setlist (drag/drop)
5. Song metadata inline editing (BPM, Duration, Tuning, Key, Notes)
6. Print preview and PDF generation
7. Song lookup and enrichment flows

**Specific to this retrofit (the 11 modified widgets):**

1. **back_only_app_bar.dart**: Loading spinner visibility during saves
2. **key_picker_bottom_sheet.dart**: Key selection modal (Major/Minor sections, None option)
3. **bpm_input_dialog.dart**: BPM input validation (20-300 range), Save/Clear/Cancel
4. **duration_input_dialog.dart**: MM:SS input formatting, Save/Clear/Cancel
5. **song_notes_drawer.dart**: View/edit mode toggle, Save disabled when unchanged, Cancel in both modes
6. **set_break_creator.dart**: Set Break duration stepper (+/− buttons, 5-60 minutes), Add Set Break
7. **masked_duration_input.dart**: MM:SS masked input (digit shifting, backspace, cursor at end) — test in pause creator
8. **reorderable_song_card.dart**: Loading spinner during tuning edit, drag handle restricted to grip icon
9. **pause_creator.dart**: Purpose chips (predefined + custom), duration optional, Add Pause
10. **custom_tuning_modal.dart**: Strings input validation (A-G + # + b), name validation, Save/Cancel
11. **setlist_picker_bottom_sheet.dart**: Setlist list, Create New flow, Move/Copy toggle (when source setlist provided)

**Cross-platform validation:**

- Test on at least 2 platforms: Web + (iOS OR macOS)
- Verify keyboard handling on mobile (iOS) vs desktop (macOS/Web)
- Verify touch targets on mobile vs mouse interactions on desktop

**Boundary exception validation:**

- Confirm dialogs with custom `backgroundColor` still render (bpm_input_dialog, duration_input_dialog) even though using raw `AlertDialog`
- Confirm bottom sheets with transparent backgrounds render correctly (set_break_creator, pause_creator, custom_tuning_modal, setlist_picker_bottom_sheet)
- Confirm `ListTile` and `Divider` render identically (no visual change from raw Material)

## Rollout / Migration Strategy

**Not applicable.** This is a pure Flutter code change with zero data migration. Deploy follows standard web deployment:

```bash
flutter build web --release
cd build/web && vercel --prod
```

Post-deploy smoke test:

- Open production site in incognito
- Navigate to Setlists → Catalog → select a song
- Test 2–3 of the modified widgets (e.g., edit BPM, add to setlist, create set break)
- Verify no console errors

## Out of Scope

**Explicitly excluded from this cycle:**

1. All HIGH-risk setlists files (16 files):
   - Top-level screens: `setlists_screen.dart`, `new_setlist_screen.dart`, `setlists_tab_content.dart`, `create_setlist_screen.dart`, `setlist_pdf_preview_screen.dart`
   - Large overlays/sheets: `bulk_add_songs_overlay.dart`, `song_lookup_overlay.dart`, `song_details_bottom_sheet.dart`, `song_enrichment_review_sheet.dart`, `print_options_bottom_sheet.dart`, `tuning_picker_bottom_sheet.dart`
   - Add-to-setlist subdirectory: all 7 files under `widgets/add_to_setlist/`
2. `setlist_detail_screen.dart` (3,716 lines) — Cycle 3d solo

3. Any file outside the setlists domain

4. Any refactoring, renaming, or opportunistic cleanup

5. Any behavioral changes or new features

6. Any database schema or RLS policy changes

7. Any new facade wrapper development (use existing wrappers only)

8. Any Material Theme configuration changes

9. Any dependency upgrades

10. Any changes to initialization order, routing, or auth flows

---

**Engineer Start Condition:** This plan approved, branch `feature/ui-facade-setlists-low-medium-risk` created off `main` at commit `18ff085`

**Engineer Completion Criteria:**

- All 11 files modified per task breakdown
- ~36 call sites replaced, 6 boundary exceptions documented
- `flutter analyze` → 0 errors
- Task 5 verification checklist completed with zero regressions
- ENGINEER_REPORT.md created with task completion log and boundary exception documentation
