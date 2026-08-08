# Architect Plan — UI Facade Setlists High Risk Retrofit (Cycle 3c-ii: Add-to-Setlist Subflow)

## Feature Slug

`feature/ui-facade-setlists-high-risk-3c-ii`

## Problem Summary

This is **Cycle 3c-ii** of the UI facade migration (Piece 3), the second of three sub-cycles covering the remaining high-risk setlists files not yet retrofitted. Cycles 3a (gigs+events, merged `18ff085`), 3b (setlists low/medium-risk, merged `8539dfe`), and 3c-i (setlists top-level screens, merged PR #131 to `56f087b`) are complete. Cycle 3c-iii will handle overlays/sheets (6 files, 6,263 lines), and Cycle 3d will handle `setlist_detail_screen.dart` (3,716 lines) as a standalone cycle.

This cycle covers the **add-to-setlist subflow** — the 4 screens responsible for adding songs, pauses, set breaks, original songs, and bulk entries to setlists. These are specialized form/input screens with complex state management, custom validation, and conditional rendering.

**Goal:** Replace raw Material widgets with facade wrapper equivalents in the 4 add-to-setlist subflow screens, maintaining zero visual/behavioral change.

## Root Cause

**Not applicable.** This is a planned technical debt remediation feature, not a bug.

**Confidence:** HIGH — Fresh scope verification confirmed 4 files with Material widget call sites via grep and `wc -l` against `origin/main` commit `56f087b`.

## Reference Docs Consulted

Not applicable (this is a UI facade retrofit following established patterns from Cycles 1/2a/2b/3a/3b/3c-i).

Relevant context:

- Wrapper implementations in `lib/components/ui/`
- Lessons from Cycle 3c-i: verify file scope via fresh grep, check wrapper source before claiming gaps, close gaps additively when found (strokeWidth, onEditingComplete, nullable title were all added in 3c-i)
- Known wrapper state verified directly against `origin/main` commit `56f087b` before this prompt

## Existing System Analysis

### Scope Verification (Fresh Assessment)

**Total in this cycle:** 4 files, 3,104 lines, verified via `wc -l` on 2026-08-08 against commit `56f087b`

**Files in scope:**

1. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` — **944 lines** (HIGH RISK)
   - Bulk song entry with manual table + CSV parsing
   - Material widgets: `TextField` (direct + `_TableTextField` helper component), `CircularProgressIndicator`
   - Complex: multi-row form state, CSV parsing, duplicate detection, validation

2. `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart` — **689 lines** (HIGH RISK)
   - Original song creation (not in Catalog)
   - Material widgets: `TextField`, `CircularProgressIndicator`
   - Moderate complexity: form state with title/artist validation

3. `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart` — **935 lines** (HIGH RISK)
   - Pause/intermission entry with optional duration and notes
   - Material widgets: `TextField`, `CircularProgressIndicator`, `ElevatedButton` with custom `backgroundColor` (`_accent` = amber via `context.colors.warning`)
   - Complex: conditional field visibility, custom accent color theming throughout UI (borders, icons, checkboxes, button)

4. `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart` — **536 lines** (HIGH RISK)
   - Set break entry with optional duration and notes
   - Material widgets: `TextField`, `CircularProgressIndicator`, `ElevatedButton` with custom `backgroundColor` (`_accent` = rose via `context.colors.primaryDim`)
   - Moderate complexity: conditional field visibility, custom accent color theming throughout UI (borders, icons, checkboxes, button)

### Material Widget Usage Patterns

Verified via grep for `TextField|TextFormField|ElevatedButton|CircularProgressIndicator` across all 4 files:

| Widget Type                 | Count | Replacement                                                     |
| --------------------------- | ----- | --------------------------------------------------------------- |
| `TextField`                 | 6     | `AppTextField` (direct instances + `_TableTextField` component) |
| `CircularProgressIndicator` | 6     | `AppProgressIndicator()`                                        |
| `ElevatedButton`            | 2     | `AppButton(variant: secondary, backgroundColor: <color>)` [1]   |

**Total:** ~14 Material widget call sites across 4 files

**[1] Known wrapper gap requiring additive fix:**

- `pause_screen.dart` line 709 and `set_break_screen.dart` line 358 both use `ElevatedButton.styleFrom(...)` with 6 custom style properties:
  - `backgroundColor: _accent` — per-screen semantic color (amber for pause, rose for set break)
  - `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Spacing.buttonRadius))` — 8px corners (theme uses 12px)
  - `elevation: 0` — flat button (theme has no elevation override, Material default is 2.0)
  - `disabledBackgroundColor: _accent.withValues(alpha: 0.25)` or `0.4` — translucent accent tint (theme has no disabled color, reverts to Material grey)
  - `disabledForegroundColor: Colors.white.withValues(alpha: 0.4)` — translucent white text (pause_screen only, theme has no disabled foreground color)
  - `padding: EdgeInsets.symmetric(horizontal: 28)` — custom horizontal padding (pause_screen only, theme has no padding override)
- `_accent` is a per-screen semantic color:
  - `pause_screen.dart`: `_accent => context.colors.warning` (amber, line 127)
  - `set_break_screen.dart`: `_accent => context.colors.primaryDim` (rose, line 88)
- This is **intentional visual color-coding** — pauses and set breaks have distinct accent colors used consistently throughout the entire UI (borders, icons, checkboxes, buttons), not just incidental styling
- `AppButton` currently has none of these 6 style properties as passthrough parameters
- **Theme verification:** `ElevatedButtonThemeData` in `lib/app/theme/app_theme.dart` (~line 380-391) sets `minimumSize` and 12px borderRadius, but does NOT set elevation, disabled colors, or padding — dropping these properties changes visual output
- **Decision:** Add all 6 optional passthrough parameters to `AppButton` as small additive change, following precedent from Cycle 3c-i which closed wrapper gaps (strokeWidth, onEditingComplete, nullable title) rather than documenting boundary exceptions. This maintains pixel-identical output.

### Facade Wrapper API Coverage (Current State on `origin/main` commit `56f087b`)

**✅ Available wrappers:**

- `AppTextField` — supports `controller`, `focusNode`, `decoration`, `hintText`, `labelText`, `prefixIcon`, `suffixIcon`, `obscureText`, `keyboardType`, `textCapitalization`, `textInputAction`, `style`, `onChanged`, `enabled`, `inputFormatters`, `autocorrect`, `autofillHints`, `onSubmitted`, `autofocus`, `maxLines`, `maxLength`, `minLines`, `textAlign`, `onEditingComplete` (added in 3c-i)
- `AppProgressIndicator` — supports type (circular/linear), `color`, `value`, `strokeWidth` (added in 3c-i)
- `AppButton` — variants: `primary` (FilledButton), `secondary` (ElevatedButton), `text` (TextButton), `outlined` (OutlinedButton), `destructive`; supports `isLoading`, `icon`, `fullWidth`, `onPressed`, `disabled` states
  - **Missing:** 6 style passthrough properties for custom button styling

**❌ Known wrapper gap requiring fix in this cycle:**

- `AppButton` lacks optional style passthrough parameters for the 2 custom-styled ElevatedButton call sites
- Required for 2 call sites: `pause_screen.dart` line 709, `set_break_screen.dart` line 358
- **Solution:** Add 6 optional parameters to `AppButton` constructor:
  1. `Color? backgroundColor` — custom background color (applies to primary/secondary variants)
  2. `BorderRadius? borderRadius` — custom corner radius, constructs RoundedRectangleBorder internally (applies to primary/secondary variants)
  3. `double? elevation` — custom elevation (applies to secondary variant only, primary is always flat)
  4. `Color? disabledBackgroundColor` — custom disabled background color (applies to primary/secondary variants)
  5. `Color? disabledForegroundColor` — custom disabled text/icon color (applies to primary/secondary variants)
  6. `EdgeInsetsGeometry? padding` — custom padding override (applies to all variants)
- Each parameter is nullable with null default = no style override = theme default behavior preserved
- Pass to `.styleFrom()` calls for `primary` (FilledButton) and `secondary` (ElevatedButton) variants only
- Do NOT apply to `text`, `outlined`, or `destructive` variants (destructive already has fixed backgroundColor/foregroundColor)

**✅ No other missing wrappers** — all Material widgets in scope have facade equivalents with this one additive fix

### Other Material Widget Usage (Not in Scope)

- **Custom helper components:** `_TableTextField` (bulk_entry_screen.dart line 890+) is a private helper widget wrapping `TextField` — this helper should be updated to use `AppTextField` internally
- **Third-party/animation widgets:** None identified in these files

## Proposed Solution

### Approach

1. **Close the `AppButton` wrapper gap:** Add 6 optional style passthrough parameters to `lib/components/ui/app_button.dart` (backgroundColor, borderRadius, elevation, disabledBackgroundColor, disabledForegroundColor, padding)
2. **Mechanical replacement** of Material widget instantiations with facade wrapper equivalents in all 4 files, following the exact pattern established in Cycles 1/2a/2b/3a/3b/3c-i:
   - Replace `TextField` → `AppTextField`
   - Replace `CircularProgressIndicator` → `AppProgressIndicator()`
   - Replace `ElevatedButton` → `AppButton(variant: AppButtonVariant.secondary)` with all original style properties passed as wrapper parameters
3. **Update helper component:** `_TableTextField` should wrap `AppTextField` instead of raw `TextField`

### Non-Goals

- Do not modify business logic, validation, state management, or data flow
- Do not introduce new abstractions or refactor opportunistically
- Do not modify any files outside the 5 files listed in "Files to Modify" (4 screens + 1 wrapper)
- Do not change accent color values or conditional visibility logic

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

| File                                                                     | What Changes                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_button.dart`                                      | Add 6 optional style passthrough parameters: `backgroundColor`, `borderRadius`, `elevation`, `disabledBackgroundColor`, `disabledForegroundColor`, `padding`. Pass to `.styleFrom()` for `primary`/`secondary` variants. Null defaults preserve existing behavior (no style override = theme default).                                                                                                                      |
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`    | Replace `TextField` → `AppTextField`, `CircularProgressIndicator` → `AppProgressIndicator()`. Update `_TableTextField` helper to wrap `AppTextField` instead of raw `TextField`.                                                                                                                                                                                                                                            |
| `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart` | Replace `TextField` → `AppTextField`, `CircularProgressIndicator` → `AppProgressIndicator()`.                                                                                                                                                                                                                                                                                                                               |
| `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`         | Replace `TextField` → `AppTextField`, `CircularProgressIndicator` → `AppProgressIndicator()`, `ElevatedButton` → `AppButton(variant: secondary, backgroundColor: _accent, borderRadius: BorderRadius.circular(Spacing.buttonRadius), elevation: 0, disabledBackgroundColor: _accent.withValues(alpha: 0.25), disabledForegroundColor: Colors.white.withValues(alpha: 0.4), padding: EdgeInsets.symmetric(horizontal: 28))`. |
| `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart`     | Replace `TextField` → `AppTextField`, `CircularProgressIndicator` → `AppProgressIndicator()`, `ElevatedButton` → `AppButton(variant: secondary, backgroundColor: _accent, borderRadius: BorderRadius.circular(Spacing.buttonRadius), elevation: 0, disabledBackgroundColor: _accent.withValues(alpha: 0.4))`. Note: no disabledForegroundColor or padding in this file (different from pause_screen).                       |

**Total:** 5 files (1 wrapper enhancement + 4 screen retrofits)

## Files Off-Limits

| File                                                                               | Reason                                                                                             |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                                    | Initialization order must not change (GUARDRAILS.md Section 1)                                     |
| `lib/features/setlists/setlist_detail_screen.dart`                                 | Reserved for solo Cycle 3d (3,716 lines)                                                           |
| `lib/features/setlists/widgets/*.dart` (other widgets)                             | Not in scope for this cycle — overlays/sheets covered in 3c-iii, top-level screens covered in 3c-i |
| `lib/components/ui/*.dart` (other wrappers)                                        | Do not modify wrappers other than `app_button.dart` — no gaps found in other wrappers              |
| All files outside `lib/features/setlists/` and `lib/components/ui/app_button.dart` | Out of scope                                                                                       |

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

- **File size:** All 4 files are substantial (536-944 lines each, total 3,104 lines), exceeding GUARDRAILS.md Section 8 target of 500 lines per file
- **Wrapper modification:** Adding `backgroundColor` parameter to `AppButton` affects a shared component used across the entire app — requires regression testing beyond just setlists
- **Complex state management:** `bulk_entry_screen.dart` has multi-row form state with CSV parsing and duplicate detection; `pause_screen.dart` and `set_break_screen.dart` have conditional field visibility based on checkboxes
- **Custom accent theming:** Two files use dynamic `_accent` color throughout the UI (not just buttons) — must verify color propagation is preserved
- **Visual consistency:** All Material → facade replacements must maintain identical styling across 4 platforms (iOS, Android, Web, macOS)
- **Helper component update:** `_TableTextField` change could affect bulk entry table rendering

**Mitigations:**

1. Engineer must verify `AppButton` enhancement with zero behavior change for existing usage (null default, no prop inference)
2. Engineer must visually compare before/after on all platforms (at minimum: web + iOS or macOS)
3. QA must test full add-to-setlist workflows (bulk entry, original song, pause, set break) end-to-end on multiple platforms
4. QA must specifically verify accent color theming in pause/set break screens (borders, icons, checkboxes, button all match)
5. QA must test bulk entry CSV parsing and table rendering to confirm no regression from `_TableTextField` change
6. `flutter analyze` must pass with 0 errors before Engineer handoff

## Engineer Task Breakdown

Execute in strict order. Each task must be completed and verified before proceeding to the next.

### Task 1: Verify Workspace State

```bash
git branch --show-current  # must be on feature/ui-facade-setlists-high-risk-3c-ii
git status --short         # must be clean
flutter analyze            # must be 0 errors
```

### Task 2: Close the AppButton Wrapper Gap

**File:** `lib/components/ui/app_button.dart`

Add 6 optional style passthrough parameters to enable custom button styling while preserving theme defaults for existing usage.

1. **Add parameters to constructor** (after `fullWidth`):

   ```dart
   final Color? backgroundColor;
   final BorderRadius? borderRadius;
   final double? elevation;
   final Color? disabledBackgroundColor;
   final Color? disabledForegroundColor;
   final EdgeInsetsGeometry? padding;
   ```

2. **Update constructor signature** to accept all 6 parameters with null defaults

3. **Update `primary` variant (FilledButton)** — applies backgroundColor, borderRadius, disabledBackgroundColor, disabledForegroundColor, padding:

   ```dart
   case AppButtonVariant.primary:
     button = FilledButton(
       onPressed: effectiveOnPressed,
       style: (backgroundColor != null ||
               borderRadius != null ||
               disabledBackgroundColor != null ||
               disabledForegroundColor != null ||
               padding != null)
           ? FilledButton.styleFrom(
               backgroundColor: backgroundColor,
               shape: borderRadius != null
                   ? RoundedRectangleBorder(borderRadius: borderRadius!)
                   : null,
               disabledBackgroundColor: disabledBackgroundColor,
               disabledForegroundColor: disabledForegroundColor,
               padding: padding,
             )
           : null,
       child: content,
     );
   ```

4. **Update `secondary` variant (ElevatedButton)** — applies all 6 properties:

   ```dart
   case AppButtonVariant.secondary:
     button = ElevatedButton(
       onPressed: effectiveOnPressed,
       style: (backgroundColor != null ||
               borderRadius != null ||
               elevation != null ||
               disabledBackgroundColor != null ||
               disabledForegroundColor != null ||
               padding != null)
           ? ElevatedButton.styleFrom(
               backgroundColor: backgroundColor,
               shape: borderRadius != null
                   ? RoundedRectangleBorder(borderRadius: borderRadius!)
                   : null,
               elevation: elevation,
               disabledBackgroundColor: disabledBackgroundColor,
               disabledForegroundColor: disabledForegroundColor,
               padding: padding,
             )
           : null,
       child: content,
     );
   ```

5. **Do NOT modify `text`, `outlined`, or `destructive` variants** — they have no custom styling needs in this cycle

6. **Run `flutter analyze`** — must be 0 errors

7. **Visual spot check on web:** Navigate to any existing AppButton usage (e.g., login screen, dashboard) — confirm no visual regression

**Critical verification:** Existing AppButton call sites with no style parameters must render identically (all null defaults = no style override = theme default). The `.styleFrom()` call is only constructed when at least one style parameter is non-null.

**Design note:** Passing `null` to `.styleFrom()` properties uses Material's default behavior (which respects theme). Only non-null values override the theme.

### Task 3: Add Facade Imports to All 4 Screen Files

For each of the 4 files, add the facade wrapper imports at the top of the file (if not already present):

```dart
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';
import 'package:bandroadie/components/ui/app_button.dart';
```

Only import wrappers that are actually used in the file. Remove unused imports after replacement.

### Task 4: Replace Material Widgets in `set_break_screen.dart` (536 lines — smallest file)

Start with the smallest file to validate the pattern:

1. Replace `TextField` → `AppTextField` (2 instances: lines ~410, ~562)
   - Preserve all props: `controller`, `decoration`, `maxLines`, `minLines`, `textCapitalization`, `keyboardType`, `onChanged`, etc.

2. Replace `CircularProgressIndicator` → `AppProgressIndicator()` (1 instance: line ~373 inside ElevatedButton child)
   - Preserve props: `strokeWidth: 2.5`, `color: Colors.white`

3. Replace `ElevatedButton` → `AppButton` (1 instance: line ~358)
   - **Original ElevatedButton code:**
     ```dart
     ElevatedButton(
       onPressed: _isSubmitting ? null : _handleSubmit,
       style: ElevatedButton.styleFrom(
         backgroundColor: _accent,
         disabledBackgroundColor: _accent.withValues(alpha: 0.4),
         shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(Spacing.buttonRadius),
         ),
         elevation: 0,
       ),
       child: _isSubmitting
           ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(...))
           : Text('Add Set Break' or 'Save Set Break', ...),
     )
     ```
   - **Replacement AppButton code:**
     ```dart
     AppButton(
       label: _isEditing ? 'Save Set Break' : 'Add Set Break',
       onPressed: _handleSubmit,
       variant: AppButtonVariant.secondary,
       isLoading: _isSubmitting,
       fullWidth: true,
       backgroundColor: _accent,
       borderRadius: BorderRadius.circular(Spacing.buttonRadius),
       elevation: 0,
       disabledBackgroundColor: _accent.withValues(alpha: 0.4),
     )
     ```
   - **Prop mapping:**
     - `onPressed: _isSubmitting ? null : _handleSubmit` → `onPressed: _handleSubmit, isLoading: _isSubmitting` (AppButton disables when loading)
     - `child: _isSubmitting ? CircularProgressIndicator(...) : Text(...)` → `label: <text>, isLoading: _isSubmitting` (AppButton handles loading spinner internally)
     - `style.backgroundColor: _accent` → `backgroundColor: _accent`
     - `style.shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Spacing.buttonRadius))` → `borderRadius: BorderRadius.circular(Spacing.buttonRadius)`
     - `style.elevation: 0` → `elevation: 0`
     - `style.disabledBackgroundColor: _accent.withValues(alpha: 0.4)` → `disabledBackgroundColor: _accent.withValues(alpha: 0.4)`
   - **Note:** This file does NOT use `disabledForegroundColor` or `padding` (unlike pause_screen.dart)
   - Keep the surrounding `SizedBox(width: double.infinity, height: 52)` wrapper (fullWidth only handles width, not height)

4. Remove unused Material imports (keep `import 'package:flutter/material.dart';` if needed for other Material widgets like Colors, EdgeInsets, etc.)

5. Run `flutter analyze` — must be 0 errors

6. Visual check on web: navigate to add set break screen, confirm:
   - Accent color is **rose** (primaryDim)
   - Button has 8px corner radius (not theme's 12px)
   - Button is flat (no elevation shadow)
   - Disabled state shows translucent rose background (not Material grey)
   - Loading state shows white spinner
   - All other accent theming (borders, icons, checkboxes) unchanged

### Task 5: Replace Material Widgets in `original_song_screen.dart` (689 lines)

1. Replace `TextField` → `AppTextField` (1 instance: line ~627)
   - Preserve all props: `controller`, `decoration`, `maxLines`, `minLines`, `textCapitalization`, `keyboardType`, `onChanged`, etc.
2. Replace `CircularProgressIndicator` → `AppProgressIndicator()` (1 instance: line ~344)
   - Preserve props: `strokeWidth`, `color`
3. Remove unused Material imports
4. Run `flutter analyze` — must be 0 errors
5. Visual check on web: add original song to setlist, confirm form fields render correctly, loading state works

### Task 6: Replace Material Widgets in `pause_screen.dart` (935 lines)

1. Replace `TextField` → `AppTextField` (2 instances: lines ~410, ~562)
   - Preserve all props: `controller`, `decoration`, `maxLines`, `minLines`, `textCapitalization`, `keyboardType`, `onChanged`, etc.

2. Replace `CircularProgressIndicator` → `AppProgressIndicator()` (1 instance: line ~728 inside ElevatedButton child)
   - Preserve props: `strokeWidth: 2.5`, `color: Colors.white`

3. Replace `ElevatedButton` → `AppButton` (1 instance: line ~709)
   - **Original ElevatedButton code:**
     ```dart
     ElevatedButton(
       onPressed: (_hasContent && !_isSubmitting) ? _handleSubmit : null,
       style: ElevatedButton.styleFrom(
         backgroundColor: _accent,
         foregroundColor: Colors.white,
         disabledBackgroundColor: _accent.withValues(alpha: 0.25),
         disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
         shape: RoundedRectangleBorder(
           borderRadius: BorderRadius.circular(Spacing.buttonRadius),
         ),
         elevation: 0,
         padding: const EdgeInsets.symmetric(horizontal: 28),
       ),
       child: _isSubmitting
           ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(...))
           : Text('Add Pause' or 'Save Pause', ...),
     )
     ```
   - **Replacement AppButton code:**
     ```dart
     AppButton(
       label: _isEditing ? 'Save Pause' : 'Add Pause',
       onPressed: _hasContent ? _handleSubmit : null,
       variant: AppButtonVariant.secondary,
       isLoading: _isSubmitting,
       fullWidth: true,
       backgroundColor: _accent,
       borderRadius: BorderRadius.circular(Spacing.buttonRadius),
       elevation: 0,
       disabledBackgroundColor: _accent.withValues(alpha: 0.25),
       disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
       padding: const EdgeInsets.symmetric(horizontal: 28),
     )
     ```
   - **Prop mapping:**
     - `onPressed: (_hasContent && !_isSubmitting) ? _handleSubmit : null` → `onPressed: _hasContent ? _handleSubmit : null, isLoading: _isSubmitting` (AppButton disables when loading OR when onPressed is null)
     - `child: _isSubmitting ? CircularProgressIndicator(...) : Text(...)` → `label: <text>, isLoading: _isSubmitting` (AppButton handles loading spinner internally)
     - `style.backgroundColor: _accent` → `backgroundColor: _accent`
     - `style.foregroundColor: Colors.white` → (no prop needed, AppButton secondary variant defaults to white foreground)
     - `style.disabledBackgroundColor: _accent.withValues(alpha: 0.25)` → `disabledBackgroundColor: _accent.withValues(alpha: 0.25)`
     - `style.disabledForegroundColor: Colors.white.withValues(alpha: 0.4)` → `disabledForegroundColor: Colors.white.withValues(alpha: 0.4)`
     - `style.shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Spacing.buttonRadius))` → `borderRadius: BorderRadius.circular(Spacing.buttonRadius)`
     - `style.elevation: 0` → `elevation: 0`
     - `style.padding: EdgeInsets.symmetric(horizontal: 28)` → `padding: const EdgeInsets.symmetric(horizontal: 28)`
   - **Note:** This file uses ALL 6 custom style properties (unlike set_break_screen.dart which omits disabledForegroundColor and padding)
   - Keep the surrounding `SizedBox(width: double.infinity, height: 48)` wrapper (fullWidth only handles width, not height)

4. Remove unused Material imports (keep `import 'package:flutter/material.dart';` if needed for other Material widgets like Colors, EdgeInsets, etc.)

5. Run `flutter analyze` — must be 0 errors

6. Visual check on web: add pause to setlist, confirm:
   - Accent color is **amber** (warning color)
   - Button has 8px corner radius (not theme's 12px)
   - Button is flat (no elevation shadow)
   - Disabled state shows translucent amber background AND translucent white text (not Material grey)
   - Loading state shows white spinner
   - Button has custom horizontal padding (28px, not theme default)
   - Conditional fields (duration, notes) toggle correctly
   - All other accent theming (borders, icons, checkboxes) unchanged

### Task 7: Replace Material Widgets in `bulk_entry_screen.dart` (944 lines — largest, most complex)

1. Replace `TextField` → `AppTextField` (1 direct instance: line ~436)
   - Preserve all props: `controller`, `decoration`, `maxLines`, `minLines`, `textCapitalization`, `keyboardType`, `onChanged`, etc.
2. Update `_TableTextField` helper component (line ~896):
   - Replace `return TextField(...)` with `return AppTextField(...)`
   - Preserve all props passed to TextField
   - This affects the table rows in the bulk entry form
3. Replace `CircularProgressIndicator` → `AppProgressIndicator()` (2 instances: lines ~500, ~851)
   - Preserve props: `strokeWidth`, `color`
4. Remove unused Material imports
5. Run `flutter analyze` — must be 0 errors
6. Visual check on web:
   - Add songs via bulk entry (manual table mode)
   - Verify table text fields render correctly
   - Paste CSV data and parse
   - Verify loading states during parsing and submission
   - Confirm duplicate detection and validation messages display correctly

### Task 8: Cross-Platform Visual Verification

1. Run on web: `flutter run -d chrome`
   - Navigate through all 4 modified screens (bulk entry, original song, pause, set break)
   - Verify loading states, buttons, text fields, accent colors render identically to before
   - Specifically test pause (amber accent) and set break (rose accent) to confirm color theming
2. Run on iOS or macOS: `flutter run -d macos` (or `flutter run -d ios` if iPhone available)
   - Repeat visual verification on native platform
   - Confirm no styling regressions (especially button alignment, text field borders, accent colors)

### Task 9: Final Validation

```bash
flutter analyze             # must be 0 errors
git diff --stat             # confirm only 5 files modified
git diff lib/components/ui/app_button.dart  # review wrapper enhancement
git diff lib/features/setlists/widgets/add_to_setlist/  # review all 4 screen changes
```

Expected changes:

- `app_button.dart`: 6 style passthrough parameters added (backgroundColor, borderRadius, elevation, disabledBackgroundColor, disabledForegroundColor, padding), primary/secondary variants updated with conditional `.styleFrom()` calls
- Import statements updated (facade wrappers added) in all 4 screens
- Material widget instantiations replaced with facade equivalents
- `ElevatedButton` in pause_screen.dart and set_break_screen.dart replaced with `AppButton` passing all 6 (pause) or 4 (set break) original style properties
- No changes to business logic, validation, or state management
- No changes to widget tree structure or callback signatures
- No changes to accent color values or conditional visibility logic

### Task 10: Write ENGINEER_REPORT.md

Document:

1. **Completion Status** — all tasks complete
2. **Files Modified** — list all 5 with line change counts from `git diff --stat`
3. **Wrapper Enhancement** — document 6 style parameters added to `AppButton` with rationale and usage examples (backgroundColor, borderRadius, elevation, disabledBackgroundColor, disabledForegroundColor, padding)
4. **Material Widgets Replaced** — table with counts per file (e.g., "2 TextField → AppTextField, 1 ElevatedButton → AppButton with 6 style props")
5. **Verification Summary** — platforms tested (web + iOS/macOS), zero analyze errors, accent color theming verified, custom styling (8px radius, flat elevation, translucent disabled states, custom padding) verified pixel-identical
6. **Known Issues** — any unexpected findings or deviations from plan
7. **QA Handoff Notes** — specific screens/flows to test, emphasize pause/set break accent color verification AND custom style property verification (corner radius, elevation, disabled colors, padding)

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

**Test 2: AppButton Enhancement (No Regression for Existing Usage)**

```bash
# Verify no style parameters are passed in existing call sites (spot check)
grep -n "AppButton(" lib/features/auth/login_screen.dart lib/app/dashboard_screen.dart | head -20
# Expected: No backgroundColor, borderRadius, elevation, disabledBackgroundColor, disabledForegroundColor, or padding arguments present (confirm null defaults work)
```

Manual verification:

1. `flutter run -d chrome`
2. Navigate to login screen, dashboard, or any screen with existing AppButton usage
3. Confirm buttons render identically to before (no color/style changes)
4. Confirm button loading states still work

**Test 3: AppButton Style Passthroughs Work Correctly**

```bash
# Verify new style parameters are passed in pause_screen and set_break_screen
grep -A 10 "AppButton(" lib/features/setlists/widgets/add_to_setlist/pause_screen.dart | grep -E "backgroundColor|borderRadius|elevation|disabledBackgroundColor|disabledForegroundColor|padding"
# Expected: All 6 style parameters present in pause_screen.dart AppButton call

grep -A 10 "AppButton(" lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart | grep -E "backgroundColor|borderRadius|elevation|disabledBackgroundColor"
# Expected: 4 style parameters present in set_break_screen.dart AppButton call (no disabledForegroundColor or padding)
```

**Test 4: Imports Correct**

```bash
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/widgets/add_to_setlist/pause_screen.dart
grep -n "import 'package:bandroadie/components/ui/" lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart
# Expected: Facade imports present in all 4 files
```

**Test 5: Material Widgets Replaced (Spot Check)**

```bash
# Verify no raw TextField in modified files
grep -n "TextField(" lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart lib/features/setlists/widgets/add_to_setlist/pause_screen.dart lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart
# Expected: 0 matches (all should be AppTextField, including _TableTextField)

# Verify AppTextField is used
grep -n "AppTextField(" lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart
# Expected: Multiple matches

# Verify no raw ElevatedButton in pause/set break screens
grep -n "ElevatedButton(" lib/features/setlists/widgets/add_to_setlist/pause_screen.dart lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart
# Expected: 0 matches (should be AppButton with style parameters)

# Verify AppButton with style parameters is used
grep -n "AppButton(" lib/features/setlists/widgets/add_to_setlist/pause_screen.dart lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart
# Expected: 1 match per file with backgroundColor, borderRadius, elevation, disabledBackgroundColor
```

**Test 6: Visual Regression (Web) — Bulk Entry**

1. `flutter run -d chrome`
2. Navigate to a setlist
3. Tap "Add Songs"
4. Select "Bulk Entry"
5. Enter songs in manual table mode (verify `_TableTextField` renders correctly)
6. Paste CSV data and parse (verify loading spinner)
7. Submit bulk entry (verify loading state)
8. Confirm: no visual differences from before retrofit

**Test 6: Visual Regression (Web) — Original Song**

1. `flutter run -d chrome`
2. Navigate to a setlist
3. Tap "Add Songs"
4. Select "Original Song"
5. Enter title and artist (verify text fields render correctly)
6. Submit (verify loading state)
7. Confirm: no visual differences from before retrofit

**Test 7: Visual Regression (Web) — Pause (Amber Accent + Custom Styling)**

1. `flutter run -d chrome`
2. Navigate to a setlist
3. Tap "Add Pause"
4. Verify accent color is **amber** (warning color):
   - Border/outline around form
   - Icons
   - Checkboxes
   - Submit button background
5. **Verify custom button styling (pixel-identical to original ElevatedButton):**
   - Corner radius is **8px** (not theme's 12px) — inspect button border
   - Button is **flat** (elevation: 0, no shadow) — check for absence of shadow
   - Disabled state (when no content entered):
     - Background is **translucent amber** (not Material grey) — `_accent.withValues(alpha: 0.25)`
     - Text is **translucent white** (not Material grey) — `Colors.white.withValues(alpha: 0.4)`
   - Button has **custom horizontal padding** (28px, not theme default) — inspect button width/padding
6. Toggle "Show duration" checkbox (verify conditional field appears)
7. Toggle "Save for reuse" checkbox
8. Enter notes (verify text field renders correctly)
9. Submit (verify loading state in button shows white spinner, button disabled)
10. Confirm: accent color theming AND custom styling preserved, pixel-identical to before retrofit

**Test 8: Visual Regression (Web) — Set Break (Rose Accent + Custom Styling)**

1. `flutter run -d chrome`
2. Navigate to a setlist
3. Tap "Add Set Break"
4. Verify accent color is **rose** (primaryDim color):
   - Border/outline around form
   - Icons
   - Checkboxes
   - Submit button background
5. **Verify custom button styling (pixel-identical to original ElevatedButton):**
   - Corner radius is **8px** (not theme's 12px) — inspect button border
   - Button is **flat** (elevation: 0, no shadow) — check for absence of shadow
   - Disabled state (when loading):
     - Background is **translucent rose** (not Material grey) — `_accent.withValues(alpha: 0.4)`
   - **Note:** This button does NOT have custom disabledForegroundColor or padding (unlike pause button)
6. Toggle "Show duration" checkbox (verify conditional field appears)
7. Toggle "Save for reuse" checkbox
8. Enter notes (verify text field renders correctly)
9. Submit (verify loading state in button shows white spinner, button disabled)
10. Confirm: accent color theming AND custom styling preserved, pixel-identical to before retrofit

**Test 9: Visual Regression (iOS or macOS)**

1. `flutter run -d macos` (or `flutter run -d ios`)
2. Repeat Tests 6-8 on native platform
3. Confirm: no visual differences, button alignment correct, text fields render properly, accent colors match (amber for pause, rose for set break)
4. **Specifically verify custom button styling on native:**
   - 8px corner radius (not 12px)
   - Flat buttons (no elevation shadow)
   - Translucent accent-tinted disabled states (not Material grey)
   - Custom padding on pause button (28px horizontal)

## QA Regression Areas

QA must validate the following areas across **web, iOS, and Android** (minimum):

### Primary Test Areas

1. **Bulk Entry Screen**
   - Navigate to a setlist → "Add Songs" → "Bulk Entry"
   - Manual table mode:
     - Enter songs in table rows (verify `_TableTextField` renders correctly)
     - Verify text field borders, focus states, cursor behavior
   - CSV mode:
     - Paste CSV data (verify text area renders correctly)
     - Parse CSV (verify loading spinner during parse)
     - Verify parsed song list displays with duplicate detection warnings
   - Submit bulk entry (verify loading state)
   - Verify songs added to setlist correctly

2. **Original Song Screen**
   - Navigate to a setlist → "Add Songs" → "Original Song"
   - Enter title (required field validation)
   - Enter artist (optional field)
   - Verify text fields render with correct styling (borders, focus states)
   - Submit (verify loading state)
   - Verify original song added to setlist correctly

3. **Pause Screen (Amber Accent Theming + Custom Styling)**
   - Navigate to a setlist → "Add Pause"
   - **Critical:** Verify accent color is **amber** throughout UI:
     - Border/outline around form container
     - Icons (add icon, checkbox icons)
     - Checkboxes (checked state)
     - Submit button background color
   - **Critical:** Verify custom button styling (pixel-identical to original):
     - Corner radius: **8px** (not theme's 12px)
     - Flat button: **no elevation shadow**
     - Disabled state (no content entered):
       - Background: **translucent amber** (`_accent.withValues(alpha: 0.25)`)
       - Text: **translucent white** (`Colors.white.withValues(alpha: 0.4)`)
     - Padding: **28px horizontal** (wider than theme default)
   - Toggle "Show duration" checkbox:
     - Verify duration field appears/disappears smoothly
     - Enter duration in duration field (verify text field renders correctly)
   - Toggle "Save for reuse" checkbox (verify state updates)
   - Enter notes in multiline text field (verify text field renders correctly)
   - Submit with loading state:
     - Verify button shows loading spinner (white color, correct size)
     - Verify button is disabled during loading
     - Verify success feedback after submission
   - Edit existing pause:
     - Verify form populates with existing values
     - Verify "Save Pause" button label (not "Add Pause")

4. **Set Break Screen (Rose Accent Theming + Custom Styling)**
   - Navigate to a setlist → "Add Set Break"
   - **Critical:** Verify accent color is **rose** throughout UI:
     - Border/outline around form container
     - Icons (add icon, checkbox icons)
     - Checkboxes (checked state)
     - Submit button background color
   - **Critical:** Verify custom button styling (pixel-identical to original):
     - Corner radius: **8px** (not theme's 12px)
     - Flat button: **no elevation shadow**
     - Disabled state (loading):
       - Background: **translucent rose** (`_accent.withValues(alpha: 0.4)`)
     - **Note:** No custom disabledForegroundColor or padding (unlike pause screen)
   - Toggle "Show duration" checkbox:
     - Verify duration field appears/disappears smoothly
     - Enter duration in duration field (verify text field renders correctly)
   - Toggle "Save for reuse" checkbox (verify state updates)
   - Enter notes in multiline text field (verify text field renders correctly)
   - Submit with loading state:
     - Verify button shows loading spinner (white color, correct size)
     - Verify button is disabled during loading
     - Verify success feedback after submission
   - Edit existing set break:
     - Verify form populates with existing values
     - Verify "Save Set Break" button label (not "Add Set Break")

### AppButton Enhancement Regression Testing

Since `AppButton` is a shared component used across the entire app, QA must spot-check existing AppButton usage in unrelated features to confirm no regression:

1. **Login Screen** — verify "Send Magic Link" button renders correctly
2. **Dashboard** — verify any action buttons render correctly
3. **Settings** — verify save/cancel buttons render correctly
4. **Gigs/Events** — verify create/edit/delete buttons render correctly

**Expected:** All existing AppButton call sites render identically to before (null defaults for all 6 style parameters = no style override = theme default)

### Cross-Platform Consistency

- **Web:** All tests above
- **iOS:** All tests above, confirm native Material Design components render correctly with facade wrappers
- **Android:** All tests above, confirm native Material Design components render correctly with facade wrappers
- **macOS (optional but recommended):** Subset of tests to confirm desktop rendering

### Accent Color Theming & Custom Styling Validation (Critical)

The most critical visual validation in this cycle is the **accent color theming AND custom button styling** in pause and set break screens:

**Accent Color Theming:**

- **Pause screen must be amber** (warning color)
- **Set break screen must be rose** (primaryDim color)
- Accent color must appear in: borders, icons, checkboxes, submit button background
- Accent color must persist across all interactions (toggle checkboxes, enter text, submit)

**Custom Button Styling (must be pixel-identical to original ElevatedButton):**

- **Both screens:**
  - Corner radius: **8px** (not theme's 12px) — verify by inspecting button border
  - Elevation: **0** (flat, no shadow) — verify by checking for absence of shadow/elevation
  - Disabled background: **translucent accent tint** (not Material grey) — pause uses alpha 0.25, set break uses alpha 0.4
- **Pause screen only:**
  - Disabled foreground: **translucent white** (alpha 0.4) — not Material grey
  - Padding: **28px horizontal** (not theme default) — verify button content padding
- **Set break screen:**
  - No custom disabledForegroundColor (uses default)
  - No custom padding (uses theme minimumSize)

**If accent colors are wrong or missing, OR if custom styling (radius, elevation, disabled colors, padding) differs from original ElevatedButton, this is a CRITICAL failure.**

### Negative Tests

- Bulk entry with malformed CSV (verify error handling)
- Original song with empty title (verify validation)
- Pause/set break with no content (verify button disabled state)
- Rapid toggling of checkboxes in pause/set break (verify no race conditions)
- Submit with slow network (verify loading indicators appear correctly)

## Rollout / Migration Strategy

**Not applicable.** This is a client-side UI change with no backend deployment, database migrations, or staged rollout required. Changes take effect immediately upon code merge and user app restart.

## Out of Scope

**Explicitly excluded from this cycle:**

1. **Cycle 3c-i files (Top-level screens, already merged in PR #131):**
   - `lib/features/setlists/setlists_screen.dart`
   - `lib/features/setlists/new_setlist_screen.dart`
   - `lib/features/setlists/setlists_tab_content.dart`
   - `lib/features/setlists/create_setlist_screen.dart`
   - `lib/features/setlists/setlist_pdf_preview_screen.dart`

2. **Cycle 3c-iii files (Overlays/sheets, 6 files, next cycle):**
   - `lib/features/setlists/widgets/bulk_add_songs_overlay.dart`
   - `lib/features/setlists/widgets/song_lookup_overlay.dart`
   - `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
   - `lib/features/setlists/widgets/song_enrichment_review_sheet.dart`
   - `lib/features/setlists/widgets/print_options_bottom_sheet.dart`
   - `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart`

3. **Cycle 3d file (Solo, 1 file):**
   - `lib/features/setlists/setlist_detail_screen.dart` (3,716 lines)

4. **Other wrapper components:**
   - Do not modify `AppTextField`, `AppProgressIndicator`, or other wrappers — no gaps found beyond `AppButton`

5. **Business logic, state management, validation:**
   - No changes to form validation logic
   - No changes to CSV parsing or duplicate detection
   - No changes to accent color values or conditional visibility logic
   - No changes to submission flows or data transformation

6. **Any refactoring, cleanup, or optimization:**
   - No controller refactoring
   - No state management refactoring
   - No performance optimization
   - This is a purely mechanical Material → facade wrapper substitution + one additive wrapper enhancement

---

**Architect Sign-Off:** Plan complete. Engineer may proceed with implementation following the task breakdown exactly as specified.

**Revision Note (2026-08-08):** Original plan incorrectly claimed "AppButton handles these via theme/variant" for `shape`, `elevation`, `disabledBackgroundColor`, `disabledForegroundColor`, and `padding`. Manager verification against `ElevatedButtonThemeData` (~line 380-391 in `lib/app/theme/app_theme.dart`) revealed:

1. Theme uses 12px borderRadius; call sites use 8px (`Spacing.buttonRadius`)
2. Theme sets no elevation; dropping `elevation: 0` reintroduces Material shadow
3. Theme sets no disabled colors; dropping reverts to Material grey
4. Theme sets no padding; dropping loses custom 28px horizontal padding

**Decision: Option A (extend AppButton with full style passthrough).** Rationale:

- Follows Cycle 3c-i precedent: close gaps additively (strokeWidth, onEditingComplete, nullable title) rather than document exceptions
- AppButton already customizes style (destructive variant proves feasibility)
- Only 2 call sites, but high-visibility (pause/set break submission buttons)
- The 6 properties (backgroundColor, borderRadius, elevation, disabledBackgroundColor, disabledForegroundColor, padding) map directly to Material button `.styleFrom()` parameters with clear passthrough semantics
- Maintains pixel-identical output: 8px corners, flat buttons, translucent accent-tinted disabled states, custom padding
- Avoids creating a boundary exception precedent for buttons (reserve exceptions for structural gaps like AppDialog)

**Implementation:** Add 6 optional nullable parameters to `AppButton`, pass to `.styleFrom()` for `primary`/`secondary` variants only when non-null. Null defaults preserve existing behavior (no style override = theme default). Conditional `.styleFrom()` construction only when at least one parameter is non-null.
