# Architect Plan — UI Facade Setlists High Risk Retrofit (Cycle 3c-iii: Overlays/Sheets)

## Feature Slug

`feature/ui-facade-setlists-high-risk-3c-iii`

## Problem Summary

This is **Cycle 3c-iii** of the UI facade migration (Piece 3), the third and final sub-cycle covering the remaining high-risk setlists files not yet retrofitted. Cycles 3a (gigs+events, merged `18ff085`), 3b (setlists low/medium-risk, merged `8539dfe`), 3c-i (setlists top-level screens, PR #131, merged `56f087b`), and 3c-ii (add-to-setlist subflow, PR #132, merged `7d38f41`) are complete. Cycle 3d will handle `setlist_detail_screen.dart` (3,716 lines) as a standalone cycle.

This cycle covers **6 overlay/sheet files** — full-screen modals (overlays) and bottom sheets used throughout the setlists feature for song lookup, bulk add, details editing, enrichment review, print options, and tuning selection.

**Goal:** Replace raw Material widgets with facade wrapper equivalents in the 6 overlay/sheet files, maintaining zero visual/behavioral change.

## Root Cause

**Not applicable.** This is a planned technical debt remediation feature, not a bug.

**Confidence:** HIGH — Fresh scope verification confirmed 6 files totaling 6,263 lines with Material widget call sites via grep and `wc -l` against `origin/main` commit `7d38f41`.

## Reference Docs Consulted

Not applicable (this is a UI facade retrofit following established patterns from Cycles 1/2a/2b/3a/3b/3c-i/3c-ii).

Relevant context:

- Wrapper implementations in `lib/components/ui/`
- Lessons from Cycle 3c-ii: verify file scope via fresh grep, check wrapper source before claiming gaps, close gaps additively when found (backgroundColor, borderRadius, elevation, disabledBackgroundColor, disabledForegroundColor, padding were all added in 3c-ii)
- Known wrapper state verified directly against `origin/main` commit `7d38f41` before this prompt

## Existing System Analysis

### Scope Verification (Fresh Assessment)

**Total in this cycle:** 6 files, 6,263 lines, verified via `wc -l` on 2026-08-08 against commit `7d38f41`

**Files in scope:**

1. `lib/features/setlists/widgets/bulk_add_songs_overlay.dart` — **895 lines** (HIGH RISK)
   - Full-screen overlay for bulk-pasting songs from spreadsheet
   - Material widgets: `TextField`, `CircularProgressIndicator`
   - Complex: Live parsing preview, validation status, row limits, keyboard toolbar

2. `lib/features/setlists/widgets/song_lookup_overlay.dart` — **1,163 lines** (HIGH RISK)
   - Full-screen overlay for searching and adding songs (catalog + external)
   - Material widgets: `TextField`, `CircularProgressIndicator`
   - Complex: Debounced search, external API integration, section headers, skeleton loaders

3. `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — **1,649 lines** (HIGH RISK)
   - Bottom sheet for viewing/editing song metadata
   - Material widgets: `TextField`, `FilledButton`, `TextButton`, `AlertDialog`
   - Complex: Inline editing, enrichment integration, YouTube links, lyrics editor, notes drawer

4. `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` — **501 lines** (MEDIUM RISK)
   - Bottom sheet for reviewing external song metadata before adding to catalog
   - Material widgets: `FilledButton`, `TextButton`, `AlertDialog`
   - Moderate complexity: Background enrichment fetch, conditional field display

5. `lib/features/setlists/widgets/print_options_bottom_sheet.dart` — **958 lines** (HIGH RISK)
   - Bottom sheet for configuring PDF print layout
   - Material widgets: `TextField`, `OutlinedButton`, `FilledButton`, `IconButton`, `Switch.adaptive`, `CircularProgressIndicator`, `AlertDialog`
   - Complex: Saved layouts, font size sliders, toggle options, paper size selector

6. `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` — **1,097 lines** (HIGH RISK)
   - Bottom sheet for selecting guitar tuning with capo frets
   - Material widgets: `FilledButton`, `TextButton`, `AlertDialog`
   - Complex: Grouped tuning sections, custom tunings CRUD, capo fret horizontal selector

### Material Widget Usage Patterns

Verified via grep for `TextField|CircularProgressIndicator|FilledButton|TextButton|OutlinedButton|IconButton|AlertDialog|Switch\.adaptive` across all 6 files:

| File                              | TextField | CircularProgress | FilledButton | TextButton | OutlinedButton | IconButton | Switch.adaptive | AlertDialog | Total  |
| --------------------------------- | --------- | ---------------- | ------------ | ---------- | -------------- | ---------- | --------------- | ----------- | ------ |
| bulk_add_songs_overlay.dart       | 1         | 1                | 0            | 0          | 0              | 0          | 0               | 0           | 2      |
| song_lookup_overlay.dart          | 1         | 1                | 0            | 0          | 0              | 0          | 0               | 0           | 2      |
| song_details_bottom_sheet.dart    | 4         | 0                | 4            | 5          | 0              | 0          | 0               | 2           | 15     |
| song_enrichment_review_sheet.dart | 0         | 0                | 2            | 2          | 0              | 0          | 0               | 1           | 5      |
| print_options_bottom_sheet.dart   | 1         | 1                | 1            | 0          | 3              | 1          | 2               | 1           | 10     |
| tuning_picker_bottom_sheet.dart   | 0         | 0                | 1            | 3          | 0              | 0          | 0               | 1           | 5      |
| **TOTAL**                         | **7**     | **3**            | **8**        | **10**     | **3**          | **1**      | **2**           | **5**       | **39** |

**Widget replacement plan:**

| Widget Type                 | Count | Replacement                      | Notes                                         |
| --------------------------- | ----- | -------------------------------- | --------------------------------------------- |
| `TextField`                 | 7     | `AppTextField`                   | Direct 1:1 replacement                        |
| `CircularProgressIndicator` | 3     | `AppProgressIndicator()`         | Direct 1:1 replacement                        |
| `FilledButton`              | 8     | `AppButton(variant: primary)`    | All use `.styleFrom(...)` for custom styling  |
| `TextButton`                | 10    | `AppButton(variant: text)`       | Most use `.styleFrom(...)` for custom styling |
| `OutlinedButton`            | 3     | `AppButton(variant: outlined)`   | All use `.styleFrom(...)` for custom styling  |
| `IconButton`                | 1     | `AppIconButton`                  | Direct 1:1 replacement                        |
| `Switch.adaptive`           | 2     | **WRAPPER GAP** — requires fix   | See below                                     |
| `AlertDialog`               | 5     | **NOT WRAPPED** — custom content | See below                                     |

**Total widgets requiring replacement:** 34 (excluding AlertDialog instances)

### Known Wrapper Gaps Requiring Fix

#### Gap 1: AppSwitch does not support `.adaptive` variant

**Issue:** `print_options_bottom_sheet.dart` uses `Switch.adaptive(...)` (2 instances, lines 665 & 736) which automatically selects `CupertinoSwitch` on iOS/macOS and Material `Switch` on Android/Web. `AppSwitch` currently only wraps Material `Switch` and does not support the `.adaptive` constructor.

**Impact:** 2 call sites in `print_options_bottom_sheet.dart`

**Solution:** Add optional `bool useAdaptiveSwitch` parameter to `AppSwitch` (default `false` for backward compatibility). When `true`, use `Switch.adaptive` instead of `Switch`.

**Implementation:**

```dart
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.useAdaptiveSwitch = false,  // NEW
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final bool useAdaptiveSwitch;  // NEW

  @override
  Widget build(BuildContext context) {
    final switchWidget = useAdaptiveSwitch  // NEW
        ? Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: activeColor,
          )
        : Switch(
            value: value,
            onChanged: onChanged,
            thumbColor: activeColor != null
                ? WidgetStateProperty.all(activeColor)
                : null,
          );
    return switchWidget;
  }
}
```

**Verification:** Existing AppSwitch call sites (without `useAdaptiveSwitch` param) continue to use Material `Switch`. New call sites with `useAdaptiveSwitch: true` use `Switch.adaptive`.

### AlertDialog Usage Analysis (Not Wrapped)

**Rationale for NOT wrapping AlertDialog instances:**

All 5 `AlertDialog` instances in scope have **custom content layouts** that do not match the simple title/message/actions pattern supported by `AppAlertDialog`:

1. **song_details_bottom_sheet.dart** (2 instances):
   - Line 551: "Unsaved Changes" dialog — custom `Column` layout with `FilledButton` + centered `TextButton` (non-standard action arrangement)
   - Line 707: "Add Link" modal — contains `TextField` inputs for URL and title (custom content)

2. **song_enrichment_review_sheet.dart** (1 instance):
   - Line 191: "Unsaved Changes" dialog — same custom `Column` layout as song_details

3. **print_options_bottom_sheet.dart** (1 instance):
   - Line 157: "Save layout" dialog — contains `TextField` input with `StatefulBuilder` for live validation (complex custom content)

4. **tuning_picker_bottom_sheet.dart** (1 instance):
   - Line 420: "Delete Custom Tuning?" confirmation — simple title/message/actions, BUT uses custom `TextButton` styling with `foregroundColor: Colors.red` for destructive action (not supported by AppAlertDialog which only has `isDestructive` for FilledButton style)

**Decision:** Leave all `AlertDialog` instances as-is. They are intentionally custom-styled and do not fit the `AppAlertDialog` abstraction. Wrapping them would require either:

- Significantly expanding `AppAlertDialog` to support custom content builders (scope creep)
- Losing intentional visual distinctions (regression)

This aligns with the principle from GUARDRAILS.md Section 7: "Prefer localized in-place edits over new abstractions."

### Facade Wrapper API Coverage (Current State on `origin/main` commit `7d38f41`)

**✅ Available wrappers:**

- `AppTextField` — supports all required props
- `AppProgressIndicator` — supports `type`, `color`, `value`, `strokeWidth`
- `AppButton` — variants: `primary`, `secondary`, `text`, `outlined`, `destructive`; supports `backgroundColor`, `borderRadius`, `elevation`, `disabledBackgroundColor`, `disabledForegroundColor`, `padding`, `isLoading`, `icon`, `fullWidth` (all added in 3c-i/3c-ii)
- `AppIconButton` — supports `icon`, `onPressed`, `color`, `size`

**❌ Known wrapper gap requiring fix in this cycle:**

- `AppSwitch` lacks `useAdaptiveSwitch` parameter for platform-adaptive behavior

**✅ No other missing wrappers** — all Material widgets in scope (excluding custom AlertDialogs) have facade equivalents with this one additive fix

## Proposed Solution

### Approach

1. **Close the `AppSwitch` wrapper gap:** Add optional `useAdaptiveSwitch` parameter to `lib/components/ui/app_switch.dart`
2. **Mechanical replacement** of Material widget instantiations with facade wrapper equivalents in all 6 files, following the exact pattern established in Cycles 1-3c-ii:
   - Replace `TextField` → `AppTextField`
   - Replace `CircularProgressIndicator` → `AppProgressIndicator()`
   - Replace `FilledButton` → `AppButton(variant: primary)`
   - Replace `TextButton` → `AppButton(variant: text)`
   - Replace `OutlinedButton` → `AppButton(variant: outlined)`
   - Replace `IconButton` → `AppIconButton`
   - Replace `Switch.adaptive` → `AppSwitch(useAdaptiveSwitch: true)`
3. **Leave AlertDialog instances as-is** — they are intentionally custom-styled and do not fit the AppAlertDialog pattern

### Non-Goals

- Do not modify business logic, validation, state management, or data flow
- Do not introduce new abstractions or refactor opportunistically
- Do not modify any files outside the 7 files listed in "Files to Modify" (6 screens + 1 wrapper)
- Do not wrap AlertDialog instances (custom content, not simple dialogs)
- Do not change existing visual styling or behavioral patterns

## Database Impact

**Not applicable.** This is a UI-only change with no database queries, migrations, RLS policies, RPCs, or triggers affected.

## Flutter Architecture Changes

**State management:** No changes to Riverpod providers, controllers, or repositories  
**Widget tree:** No structural changes — only Material widget → facade wrapper substitution  
**Business logic:** No changes to validation, data transformation, or event handling  
**Routing:** No changes to navigation or deep linking

**Impact surface:** UI presentation layer only (Material widget call sites + one wrapper component enhancement)

## Files to Create

**None.** All required facade wrappers exist in `lib/components/ui/`.

## Files to Modify

| File                                                              | What Changes                                                                                                                                                                                                                                                                                                                                    |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_switch.dart`                               | Add optional `useAdaptiveSwitch` parameter (bool, default `false`). When `true`, use `Switch.adaptive` instead of `Switch`. Preserve all existing props.                                                                                                                                                                                        |
| `lib/features/setlists/widgets/bulk_add_songs_overlay.dart`       | Replace `TextField` → `AppTextField`, `CircularProgressIndicator` → `AppProgressIndicator()`.                                                                                                                                                                                                                                                   |
| `lib/features/setlists/widgets/song_lookup_overlay.dart`          | Replace `TextField` → `AppTextField`, `CircularProgressIndicator` → `AppProgressIndicator()`.                                                                                                                                                                                                                                                   |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`    | Replace `TextField` → `AppTextField`, `FilledButton` → `AppButton(variant: primary)`, `TextButton` → `AppButton(variant: text)`. Leave `AlertDialog` instances as-is (custom content).                                                                                                                                                          |
| `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` | Replace `FilledButton` → `AppButton(variant: primary)`, `TextButton` → `AppButton(variant: text)`. Leave `AlertDialog` instance as-is (custom content).                                                                                                                                                                                         |
| `lib/features/setlists/widgets/print_options_bottom_sheet.dart`   | Replace `TextField` → `AppTextField`, `OutlinedButton` → `AppButton(variant: outlined)`, `FilledButton` → `AppButton(variant: primary)`, `IconButton` → `AppIconButton`, `Switch.adaptive` → `AppSwitch(useAdaptiveSwitch: true)`, `CircularProgressIndicator` → `AppProgressIndicator()`. Leave `AlertDialog` instance as-is (custom content). |
| `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart`   | Replace `FilledButton` → `AppButton(variant: primary)`, `TextButton` → `AppButton(variant: text)`. Leave `AlertDialog` instance as-is (custom styling for destructive action).                                                                                                                                                                  |

**Total:** 7 files (1 wrapper enhancement + 6 screen retrofits)

## Files Off-Limits

| File                                                                                       | Reason                                                                                |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                                            | Initialization order must not change (GUARDRAILS.md Section 1)                        |
| `lib/features/setlists/setlist_detail_screen.dart`                                         | Reserved for solo Cycle 3d (3,716 lines)                                              |
| `lib/features/setlists/widgets/add_to_setlist/*.dart`                                      | Completed in Cycle 3c-ii (PR #132)                                                    |
| `lib/features/setlists/*.dart` (top-level screens)                                         | Completed in Cycle 3c-i (PR #131)                                                     |
| `lib/components/ui/*.dart` (other wrappers)                                                | Do not modify wrappers other than `app_switch.dart` — no gaps found in other wrappers |
| All files outside `lib/features/setlists/widgets/` and `lib/components/ui/app_switch.dart` | Out of scope                                                                          |

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

**HIGH**

**Rationale:**

- **File size:** All 6 files are substantial (501-1,649 lines each, total 6,263 lines), with 5 of 6 exceeding GUARDRAILS.md Section 8 target of 500 lines per file
- **Wrapper modification:** Adding `useAdaptiveSwitch` parameter to `AppSwitch` affects a shared component used across the entire app — requires regression testing beyond just setlists
- **Complex overlays:** Full-screen overlays (`bulk_add_songs_overlay.dart`, `song_lookup_overlay.dart`) have complex animation, debouncing, and keyboard management
- **Bottom sheet complexity:** Multiple sheets have conditional field visibility, custom animations, drag handles, and physics-based transitions
- **Custom button styling:** Many `FilledButton`/`TextButton`/`OutlinedButton` instances use `.styleFrom(...)` with custom colors, shapes, padding — must verify AppButton passthrough parameters preserve exact styling
- **Platform-specific behavior:** `Switch.adaptive` change affects iOS/macOS vs Android/Web rendering — must verify both Material and Cupertino styles render correctly
- **Visual consistency:** All Material → facade replacements must maintain identical styling across 4 platforms (iOS, Android, Web, macOS)

**Mitigations:**

1. Engineer must verify `AppSwitch` enhancement with zero behavior change for existing usage (false default, no prop inference)
2. Engineer must visually compare before/after on all platforms (at minimum: web + iOS or macOS)
3. Engineer must specifically test adaptive switch on both iOS/macOS (Cupertino) and Android/Web (Material)
4. QA must test full workflows: song lookup, bulk add, song details editing, enrichment review, print options, tuning selection
5. QA must test on multiple platforms to verify adaptive behavior and button styling consistency
6. `flutter analyze` must pass with 0 errors before Engineer handoff

## Engineer Task Breakdown

Execute in strict order. Each task must be completed and verified before proceeding to the next.

### Task 1: Verify Workspace State

```bash
git branch --show-current  # must be on feature/ui-facade-setlists-high-risk-3c-iii
git status --short         # must be clean
flutter analyze            # must be 0 errors
```

### Task 2: Close the AppSwitch Wrapper Gap

**File:** `lib/components/ui/app_switch.dart`

Add optional `useAdaptiveSwitch` parameter to enable platform-adaptive switch behavior while preserving Material switch for existing usage.

1. **Add parameter to constructor** (after `activeColor`):

   ```dart
   /// Whether to use Switch.adaptive (Cupertino on iOS/macOS, Material on Android/Web)
   /// Defaults to false (always use Material Switch)
   final bool useAdaptiveSwitch;
   ```

2. **Update constructor signature** to accept the parameter with `false` default

3. **Update `build` method** to conditionally use `Switch.adaptive` or `Switch`:

   ```dart
   @override
   Widget build(BuildContext context) {
     if (useAdaptiveSwitch) {
       return Switch.adaptive(
         value: value,
         onChanged: onChanged,
         activeColor: activeColor,
       );
     }

     return Switch(
       value: value,
       onChanged: onChanged,
       thumbColor: activeColor != null
           ? WidgetStateProperty.all(activeColor)
           : null,
     );
   }
   ```

4. **Run `flutter analyze`** — must be 0 errors

5. **Visual spot check on web:** Navigate to any existing AppSwitch usage (e.g., settings screens) — confirm no visual regression (Material switch still renders)

6. **Visual spot check on iOS/macOS:** Build and run on macOS (`flutter run -d macos`), navigate to settings screens — confirm Material switch still renders (no adaptive behavior yet)

**Critical verification:** Existing AppSwitch call sites (without `useAdaptiveSwitch` param) must render Material switch on all platforms (backward compatible).

### Task 3: Add Facade Imports to All 6 Screen Files

For each of the 6 files, add the facade wrapper imports at the top of the file (only import wrappers that are actually used):

```dart
import 'package:bandroadie/components/ui/app_text_field.dart';      // if TextField used
import 'package:bandroadie/components/ui/app_progress_indicator.dart';  // if CircularProgressIndicator used
import 'package:bandroadie/components/ui/app_button.dart';           // if any button used
import 'package:bandroadie/components/ui/app_icon_button.dart';      // if IconButton used (print_options only)
import 'package:bandroadie/components/ui/app_switch.dart';           // if Switch used (print_options only)
```

Remove any unused imports after replacement.

### Task 4: Replace Material Widgets in `song_enrichment_review_sheet.dart` (501 lines — smallest file)

Start with the smallest file to validate the pattern:

1. **Replace FilledButton** (2 instances: lines ~211, ~463)
   - Line 211: "Keep Editing" button in unsaved changes dialog

     ```dart
     // BEFORE
     FilledButton(
       onPressed: () => Navigator.of(context).pop(false),
       style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
       child: Text('Keep Editing', ...),
     )

     // AFTER
     AppButton(
       label: 'Keep Editing',
       onPressed: () => Navigator.of(context).pop(false),
       variant: AppButtonVariant.primary,
       backgroundColor: AppColors.primary,
     )
     ```

   - Line 463: "Save" button at bottom
     - Similar replacement, preserve all props (backgroundColor, padding, shape)

2. **Replace TextButton** (2 instances: lines ~225, ~484)
   - Line 225: "Discard" button in unsaved changes dialog
   - Line 484: "Cancel" button at bottom
   - Both are simple `TextButton` with no custom styling → `AppButton(variant: text)`

3. **Leave AlertDialog as-is** (line 191) — custom Column layout with custom button arrangement

4. Remove unused Material imports (keep `import 'package:flutter/material.dart';` if needed for other widgets)

5. Run `flutter analyze` — must be 0 errors

6. Visual check on web: trigger unsaved changes dialog and bottom action bar, confirm buttons render correctly

### Task 5: Replace Material Widgets in `bulk_add_songs_overlay.dart` (895 lines)

1. **Replace TextField** (1 instance: line 484)
   - Multi-line input area with monospace font and hint text
   - Preserve all props: `controller`, `focusNode`, `onChanged`, `textCapitalization`, `keyboardType`, `textInputAction`, `maxLines`, `minLines`, `style`, `decoration`

2. **Replace CircularProgressIndicator** (1 instance: line 872)
   - Inside loading button child with custom size/stroke
   - `CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white))` → `AppProgressIndicator(strokeWidth: 2, color: Colors.white)`

3. Remove unused Material imports

4. Run `flutter analyze` — must be 0 errors

5. Visual check on web: open bulk add overlay, paste data, verify input field and loading state

### Task 6: Replace Material Widgets in `song_lookup_overlay.dart` (1,163 lines)

1. **Replace TextField** (1 instance: line 452)
   - Search field with clear button and prefix icon
   - Preserve all props: `controller`, `focusNode`, `autofocus`, `onChanged`, `style`, `decoration` (with `hintText`, `hintStyle`, `prefixIcon`, `suffixIcon`, `border`, `contentPadding`)

2. **Replace CircularProgressIndicator** (1 instance: line 690)
   - Searching indicator with custom stroke width
   - `CircularProgressIndicator(strokeWidth: 2)` → `AppProgressIndicator(strokeWidth: 2)`

3. Remove unused Material imports

4. Run `flutter analyze` — must be 0 errors

5. Visual check on web: open song lookup overlay, type search query, verify search field and loading state

### Task 7: Replace Material Widgets in `tuning_picker_bottom_sheet.dart` (1,097 lines)

1. **Replace FilledButton** (1 instance: line 792)
   - "Save" button at bottom with conditional disabled state and custom styling
   - Preserve all props from `.styleFrom(backgroundColor, disabledBackgroundColor, padding, shape)`

2. **Replace TextButton** (3 instances: lines ~434, ~441, ~816)
   - Line 434: "Cancel" in delete confirmation dialog
   - Line 441: "Delete" in delete confirmation dialog (custom red foregroundColor)
   - Line 816: "Cancel" button at bottom
   - **Special case line 441:** `TextButton.styleFrom(foregroundColor: Colors.red)` — AppButton does not support custom foregroundColor for text variant, so either:
     - Option A: Leave this one TextButton as-is (boundary exception for destructive action in custom dialog)
     - Option B: Wrap in `Theme` to override text button color
     - **Recommendation:** Option A (leave as-is) — aligns with AlertDialog boundary decision

3. **Leave AlertDialog as-is** (line 420) — custom red destructive button styling

4. Remove unused Material imports

5. Run `flutter analyze` — must be 0 errors

6. Visual check on web: open tuning picker, select tuning, select capo, trigger delete confirmation, verify buttons render correctly

### Task 8: Replace Material Widgets in `song_details_bottom_sheet.dart` (1,649 lines — largest, most complex)

1. **Replace TextField** (4 instances: lines ~722, ~750, ~1063, ~1136, ~1439)
   - Line 722: Title field in "Add Link" dialog
   - Line 750: URL field in "Add Link" dialog
   - Line 1063: Notes field (first instance, likely in drawer sub-view)
   - Line 1136: Notes field (second instance, may be duplicate or different context)
   - Line 1439: Notes preview/edit field
   - Preserve all props: `controller`, `autofocus`, `textCapitalization`, `style`, `decoration`

2. **Replace FilledButton** (4 instances: lines ~571, ~777, ~1601)
   - Line 571: "Keep Editing" in unsaved changes dialog
   - Line 777: "Save" in "Add Link" dialog
   - Line 1601: "Save" or "Done" button at bottom (conditional label based on `_justEnriched`)
   - Preserve all props from `.styleFrom(backgroundColor, minimumSize, shape)`

3. **Replace TextButton** (5 instances: lines ~585, ~801, ~944, ~1630)
   - Line 585: "Discard" in unsaved changes dialog
   - Line 801: "Cancel" in "Add Link" dialog
   - Line 944: "Enrich Song Data" action button (TextButton.icon with custom styling)
   - Line 1630: "Cancel" or "Close" button at bottom
   - **Special case line 944:** `TextButton.icon` with custom padding and icon — use `AppButton(variant: text, icon: Icons.auto_awesome)`

4. **Leave AlertDialog instances as-is** (2 instances: lines ~551, ~707) — custom layouts

5. Remove unused Material imports

6. Run `flutter analyze` — must be 0 errors

7. Visual check on web:
   - Open song details sheet
   - Trigger unsaved changes dialog
   - Add YouTube link modal
   - Edit notes
   - Enrich song data
   - Verify all buttons, text fields, and dialogs render correctly

### Task 9: Replace Material Widgets in `print_options_bottom_sheet.dart` (958 lines — most widget variety)

1. **Replace TextField** (1 instance: line 164)
   - "Save layout" dialog input field with live validation
   - Preserve all props: `controller`, `autofocus`, `style`, `decoration` (with `hintText`, `hintStyle`, `filled`, `fillColor`, `border`, `enabledBorder`, `focusedBorder`), `onChanged`

2. **Replace OutlinedButton** (3 instances: lines ~196, ~216, ~919)
   - Line 196: "Cancel" in save layout dialog
   - Line 216: "Save" in save layout dialog (conditional disabled state)
   - Line 919: "Save layout" button at bottom
   - Preserve all props from `.styleFrom(side, shape)` and conditional disabled state

3. **Replace FilledButton** (1 instance: line 937)
   - "Preview" button at bottom
   - Preserve all props from `.styleFrom(backgroundColor, padding, shape)`

4. **Replace IconButton** (1 instance: line 330)
   - Close button in header
   - `IconButton(onPressed: ..., icon: Icon(Icons.close_rounded, ...), constraints: ...)` → `AppIconButton(icon: Icons.close_rounded, onPressed: ..., color: ..., size: ...)`

5. **Replace Switch.adaptive** (2 instances: lines ~665, ~736)
   - Both are in section toggles for print options
   - `Switch.adaptive(value: ..., onChanged: ..., activeTrackColor: AppColors.primary)` → `AppSwitch(value: ..., onChanged: ..., activeColor: AppColors.primary, useAdaptiveSwitch: true)`

6. **Replace CircularProgressIndicator** (1 instance: line 351)
   - Loading state in layout list
   - `CircularProgressIndicator(color: AppColors.primary)` → `AppProgressIndicator(color: AppColors.primary)`

7. **Leave AlertDialog as-is** (line 157) — custom content with TextField and StatefulBuilder

8. Remove unused Material imports

9. Run `flutter analyze` — must be 0 errors

10. Visual check on web:
    - Open print options sheet
    - Toggle switches (verify Material switch renders)
    - Save layout (trigger dialog with TextField)
    - Tap close button
    - Verify all buttons and inputs render correctly

11. Visual check on macOS: `flutter run -d macos`
    - Open print options sheet
    - Toggle switches (verify Cupertino switch renders on macOS due to `useAdaptiveSwitch: true`)
    - Confirm consistent behavior

### Task 10: Cross-Platform Visual Verification

1. **Web:** `flutter run -d chrome`
   - Navigate through all 6 modified screens
   - Test every Material → facade replacement call site
   - Specifically verify adaptive switches show Material switches on web

2. **iOS or macOS:** `flutter run -d macos` (or `flutter run -d ios` if iPhone available)
   - Navigate through all 6 modified screens
   - Specifically verify adaptive switches show Cupertino switches on macOS
   - Confirm no styling regressions on native platform

### Task 11: Final Validation

```bash
flutter analyze             # must be 0 errors
git diff --stat             # confirm only 7 files modified
git diff lib/components/ui/app_switch.dart  # review wrapper enhancement
git diff lib/features/setlists/widgets/  # review all 6 screen changes
```

**Expected diff:**

- 1 wrapper file modified (`app_switch.dart`)
- 6 screen files modified (bulk_add_songs_overlay, song_lookup_overlay, song_details_bottom_sheet, song_enrichment_review_sheet, print_options_bottom_sheet, tuning_picker_bottom_sheet)
- AlertDialog instances remain unchanged
- All TextField, CircularProgressIndicator, button widgets replaced with facade wrappers

---

## Verification Plan

### Tier 1 — Pre-deployment (Local Testing)

Not applicable (no Supabase changes, UI-only)

### Tier 2 — Post-implementation (UI Verification)

**Manual testing required on:**

1. Web (`flutter run -d chrome`)
2. macOS (`flutter run -d macos`)

**Test Matrix:**

| Feature                 | What to Test                                                 | Expected Outcome                                                                                      |
| ----------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| Bulk Add Songs Overlay  | Open overlay, paste spreadsheet data, submit                 | Input field, loading spinner, validation messages render correctly                                    |
| Song Lookup Overlay     | Open overlay, search songs, select result                    | Search field, loading spinner, results list render correctly                                          |
| Song Details Sheet      | Open sheet, edit fields, trigger dialogs, enrich song        | All text fields, buttons, dialogs render correctly; unsaved changes dialog works                      |
| Enrichment Review Sheet | Add external song, review metadata, save                     | Buttons and unsaved changes dialog render correctly                                                   |
| Print Options Sheet     | Open sheet, toggle options, save layout                      | Switches (adaptive on macOS, Material on web), buttons, text field, close button all render correctly |
| Tuning Picker Sheet     | Open sheet, select tuning, select capo, delete custom tuning | Buttons render correctly; delete confirmation dialog works                                            |

**Platform-specific verification:**

- **Adaptive switches (print_options_bottom_sheet):**
  - Web: Verify Material switches render
  - macOS: Verify Cupertino switches render
  - Confirm activeColor (AppColors.primary) applies correctly on both platforms

### QA Regression Areas

1. **Full overlay/sheet workflows:** Song lookup, bulk add, song details editing, enrichment review, print options, tuning selection
2. **Button styling consistency:** Verify all replaced buttons (primary/text/outlined variants) match original styling
3. **Text field behavior:** Verify all replaced TextField instances behave identically (focus, keyboard, validation)
4. **Loading states:** Verify CircularProgressIndicator replacements show correct size, color, stroke width
5. **AlertDialog preservation:** Verify all custom AlertDialog instances (unsaved changes, add link, save layout, delete tuning) render unchanged
6. **Adaptive switch behavior:** Verify Switch.adaptive replacements show correct platform-specific UI (Material on Android/Web, Cupertino on iOS/macOS)
7. **Cross-platform consistency:** Test on at least 2 platforms (web + iOS or macOS) to confirm no visual regressions

## Rollout / Migration Strategy

Standard feature branch → PR → merge workflow. No special rollout needed (UI-only change).

## Out of Scope

- `lib/features/setlists/setlist_detail_screen.dart` — reserved for solo Cycle 3d (3,716 lines)
- AlertDialog instances — intentionally left as-is (custom content, not simple dialogs)
- TextButton with custom foregroundColor in tuning picker delete dialog — boundary exception for destructive action in custom dialog
- Any files outside the 7 files listed in "Files to Modify"
- Business logic, state management, validation, data flow changes
- Opportunistic refactoring or cleanup
