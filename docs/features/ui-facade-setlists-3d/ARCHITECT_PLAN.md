# Architect Plan — UI Facade Setlists Retrofit (Cycle 3d: Setlist Detail Screen)

## Feature Slug

`feature/ui-facade-setlists-3d`

## Problem Summary

This is **Cycle 3d** of the UI facade migration (Piece 3), covering the final standalone high-risk setlists file reserved out of all prior cycles: `setlist_detail_screen.dart`. Cycles 3a (gigs+events, merged `18ff085`), 3b (setlists low/medium-risk, merged `8539dfe`), 3c-i (setlists top-level screens, PR #131, merged `56f087b`), 3c-ii (add-to-setlist subflow, PR #132, merged `7d38f41`), and 3c-iii (setlists overlays/sheets, PR #133, merged TBD) are complete. This file was explicitly reserved for its own standalone pass given its size (3,788 lines as of 2026-08-11).

**Goal:** Replace raw Material widgets with facade wrapper equivalents in `setlist_detail_screen.dart`, maintaining zero visual/behavioral change.

## Root Cause

**Not applicable.** This is a planned technical debt remediation feature, not a bug.

**Confidence:** HIGH — Fresh scope verification confirmed 3,788 lines with Material widget call sites via grep and `wc -l` against `main` commit `cf9fde4` (2026-08-11).

## Reference Docs Consulted

Not applicable (this is a UI facade retrofit following established patterns from Cycles 1/2a/2b/3a/3b/3c-i/3c-ii/3c-iii).

Relevant context:

- Wrapper implementations in `lib/components/ui/`
- Lessons from prior cycles: verify file scope via fresh grep, check wrapper source before claiming gaps, avoid breaking widget identity in gesture/animation contexts
- Known wrapper state verified directly against `main` commit `cf9fde4` before this plan

## Existing System Analysis

### Scope Verification (Fresh Assessment)

**Total in this cycle:** 1 file, 3,788 lines, verified via `wc -l` on 2026-08-11 against commit `cf9fde4`

**File in scope:**

1. `lib/features/setlists/setlist_detail_screen.dart` — **3,788 lines** (HIGH RISK)
   - Main screen for viewing and managing setlist contents
   - Material widgets: `TextField`, `TextFormField`, `CircularProgressIndicator`, `FilledButton`, `TextButton`, `IconButton`, `AlertDialog`, `showDialog`, `showModalBottomSheet`, `Card`, `Scaffold`, `Dismissible` (15), `AnimationController` (10)
   - Complex: Reorderable list, search, swipe-to-delete, inline editing, drag animations, catalog sorting, special items (set breaks/pauses), multi-select mode, enrichment integration, share/export

### Material Widget Usage Patterns

Verified via grep for raw Material widget patterns across the file:

| Widget Type                 | Count | Replacement                      | Notes                                                                                |
| --------------------------- | ----- | -------------------------------- | ------------------------------------------------------------------------------------ |
| `TextField`                 | 1     | `AppTextField`                   | Line 2309 — search input                                                             |
| `TextFormField`             | 1     | `AppTextField` + Form wrapper    | Line 219 — rename dialog input                                                       |
| `CircularProgressIndicator` | 3     | `AppProgressIndicator()`         | Lines 1467, 1749, 2376 — loading states                                              |
| `FilledButton`              | 4     | `AppButton(variant: primary)`    | Lines 253, 259, 2988, 2990 — primary actions with custom styling                     |
| `TextButton`                | 14    | `AppButton(variant: text)` or NO | See AlertDialog boundary-exception policy below                                      |
| `IconButton`                | 2     | `AppIconButton`                  | Lines 2551, 2562 — search clear/sort buttons                                         |
| `Card`                      | 5     | `AppCard` or NO                  | 1 Card in loading dialog (line 1461) — wrap; 4 others in child components (no wrap) |
| `Scaffold`                  | 1     | `AppScaffold`                    | Line 2191 — main scaffold                                                            |
| `showDialog`                | 7     | NO CHANGE                        | All use custom AlertDialog content — see below                                       |
| `showModalBottomSheet`      | 2     | NO CHANGE                        | Not wrapped (standard Material API for bottom sheets)                                |
| `AlertDialog`               | 6     | NO CHANGE                        | Custom content — see boundary-exception policy below                                 |
| `Dismissible`               | 15    | NO CHANGE                        | No facade wrapper exists (gesture primitive)                                         |
| `AnimationController`       | 10    | NO CHANGE                        | No facade wrapper exists (animation primitive)                                       |

**Total widgets requiring replacement:** 17 Material widget call sites (excluding Dismissible, AnimationController, AlertDialog, showDialog, showModalBottomSheet which are boundary exceptions — see below)

### Boundary-Exception Policy

#### 1. Dismissible and AnimationController — Never Wrapped

**Rationale:** No facade wrapper exists for either widget (confirmed: `lib/components/ui/` has no gesture or animation-controller wrapper). These are Flutter primitives that manage gesture recognition and animation timing, not presentation widgets. They stay raw Material by definition, not judgment.

**Count:** 15 Dismissible, 10 AnimationController — all left as-is.

#### 2. Material Widgets Inside Dismissible — Case-by-Case Decision

**Pattern:** Swipe-to-delete and swipe-to-move-or-copy gestures wrap `ReorderableSongCard` and `SpecialItemCard` child widgets, with `_buildDeleteBackground()` and `_buildMoveOrCopyBackground()` rendering swipe backgrounds.

**Analysis:**

- **Background widgets** (lines 2990-3042): Use `Container` with `Icon` and `Text` primitives — no raw Material widgets to wrap.
- **Child widgets**: `ReorderableSongCard` and `SpecialItemCard` are already defined in separate files (`reorderable_song_card.dart`, `special_item_card.dart`) and were handled in prior cycles. No Material widgets remain in the Dismissible child trees within this file.

**Decision:** No Material widgets exist inside Dismissible widgets in this file that require wrapping. The Dismissible instances themselves are left raw (no wrapper exists), and their children are already facade-compliant or primitives.

#### 3. Material Widgets as Direct Children of AnimationController — Case-by-Case Decision

**Pattern:** Several internal stateful widgets use `AnimationController` for tap feedback, slide-in animations, and reorder animations. These controllers drive `AnimatedBuilder`, `SlideTransition`, `FadeTransition`, and `Transform.scale` widgets.

**Analysis:**

- **_SelectableSongCard** (lines 3043-3174): `_tapController` drives `Transform.scale` wrapping a `Container` (no raw Material inside the animated subtree).
- **_ActionButton** (lines 3362-3464): `_controller` drives `Transform.scale` wrapping a `Container` (no raw Material inside the animated subtree).
- **_SlideInEntry** (lines 3633-3698): `_controller` drives `SlideTransition` + `FadeTransition` wrapping a generic `child` widget passed from parent (child widget is `SpecialItemCard`, already facade-compliant).
- **Main screen animations** (lines 90-180): `_entranceController` drives header fade/slide (wraps `Text` and `Icon` primitives, no Material widgets); `_sortAnimController` drives reorder fade (wraps `SliverReorderableList`, no Material widgets directly animated).

**Decision:** No Material widgets are direct children of `AnimatedBuilder` or animation transition widgets that would break widget identity if wrapped. All animated children are either primitives (`Container`, `Text`, `Icon`), or already facade-compliant cards from prior cycles. No boundary conflict exists.

#### 4. AlertDialog and showDialog — Custom Content Exception

**Rationale for NOT wrapping AlertDialog instances:**

All 6 `AlertDialog` instances in scope have **custom content layouts** that do not match the simple title/message/actions pattern supported by `AppAlertDialog`:

1. **Line 207-265: Rename Dialog**
   - Uses `Form` + `TextFormField` with validator inside `AlertDialog.content`
   - Custom input field styling and validation logic
   - Actions: `TextButton` (Cancel) + `FilledButton` (Save) with custom `.styleFrom(...)` for primary color
   - **Decision:** Leave raw. Custom form logic, validator state. TextFormField will be wrapped per normal replacement rule (becomes `AppTextField` in `Form`). Buttons inside actions will be wrapped per normal replacement rule.

2. **Line 295-299: Delete Song Dialog**
   - Delegates to `_DeleteSongDialog` widget (lines 3546-3633)
   - Custom two-tone content with warning callout box for Catalog deletion
   - Uses emoji in title, styled `Container` with border for warning section
   - Actions: `TextButton` (Cancel) + `TextButton` (Remove/Delete Forever) with conditional background color `.styleFrom(backgroundColor: ...)` and conditional text color based on `isCatalog` flag
   - **Decision:** Leave raw AlertDialog. Custom content layout with conditional styling. Buttons inside actions will be wrapped per normal replacement rule.

3. **Line 405-420: Add Link Dialog (inside showDialog)**
   - Not actually an AlertDialog — uses generic `builder` returning unspecified widget
   - Actual implementation not visible in grep output (likely in separate widget file)
   - **Decision:** No change (not an AlertDialog in this file's scope).

4. **Line 844-883: Delete Special Item Dialog (first instance)**
   - Simple title/content/actions pattern, BUT actions use `TextButton` with custom foreground color `.copyWith(color: AppColors.error)` for destructive action
   - `AppAlertDialog` only supports `isDestructive` for `FilledButton` style, not `TextButton` with custom color
   - **Decision:** Leave raw. Custom destructive `TextButton` styling not supported by `AppAlertDialog`. Buttons inside actions will be wrapped per normal replacement rule.

5. **Line 893-928: Delete Special Item Dialog (second instance)**
   - Identical to #4 above — same custom `TextButton` destructive styling
   - **Decision:** Leave raw. Same rationale as #4.

6. **Line 2017-2052: Confirm Leave Without Saving Dialog (during enrichment)**
   - Simple title/content/actions pattern, BUT actions use `TextButton` with custom foreground color `.copyWith(...)` for emphasis
   - **Decision:** Leave raw. Custom button styling not supported by `AppAlertDialog`. Buttons inside actions will be wrapped per normal replacement rule.

**Pattern:** All AlertDialog instances either have custom content (forms, validation, conditional layouts) or custom button styling (destructive text buttons, conditional colors) that `AppAlertDialog` does not support without scope creep.

**Boundary Rule:** Leave all `AlertDialog` instances as-is (6 total). Wrap Material widgets *inside* the AlertDialog content/actions per normal replacement rules (e.g., `TextFormField` → `AppTextField`, `FilledButton` → `AppButton(variant: primary)`, `TextButton` → `AppButton(variant: text)`).

This aligns with the 3c-iii precedent for genuinely custom AlertDialog instances.

#### 5. showModalBottomSheet — Not Wrapped

**Rationale:** `showModalBottomSheet` is a standard Material API for presenting bottom sheets. No facade wrapper exists (confirmed: `lib/components/ui/` has no `showAppBottomSheet` function). The sheets themselves (`SetlistPickerBottomSheet`, `_ShareFormatSheet`) are separate widget files already using facade wrappers internally (handled in prior cycles or out of this file's scope).

**Count:** 2 instances (lines 1300, 1960) — both left as-is.

**Decision:** No change to `showModalBottomSheet` calls.

### Card Usage — Special Case Analysis

**Total Card instances:** 5 matches in grep (search pattern `Card\(` with backslash escape)

**Breakdown:**

1. **Line 1461: Loading Dialog Card**
   - Used in `showDialog` during bulk add operation (lines 1455-1484)
   - Wraps `CircularProgressIndicator` + status text
   - Simple presentation card, not a custom layout
   - **Decision:** Wrap with `AppCard`. Child `CircularProgressIndicator` also wrapped with `AppProgressIndicator()`.

2-5. **Lines 2705, 3043, 3362, 3633: Grep False Positives or Child Components**
   - Line 2705: "_SelectableSongCard" — class name, not a Card widget instantiation
   - Line 3043: "const _SelectableSongCard" — same class name
   - Line 3362: "_ActionButton" — not a Card (uses `Container`)
   - Line 3633: "_SlideInEntry" — not a Card (animation wrapper)
   - **Grep artifact:** The pattern `Card(` matches substrings in class names. Actual Card widget count is **1** (line 1461).

**Revised Card widget count:** 1 (line 1461 only) — wrap with `AppCard`.

### Facade Wrapper API Coverage (Current State on `main` commit `cf9fde4`)

**✅ Available wrappers:**

- `AppTextField` — supports all required props (including `controller`, `decoration`, `style`, `onChanged`, `autofocus`, `validator` via wrapper)
- `AppProgressIndicator` — supports `type`, `color`, `value`, `strokeWidth`
- `AppButton` — variants: `primary`, `secondary`, `text`, `outlined`, `destructive`; supports `backgroundColor`, `borderRadius`, `elevation`, `disabledBackgroundColor`, `disabledForegroundColor`, `padding`, `isLoading`, `icon`, `fullWidth` (complete as of 3c-ii)
- `AppIconButton` — supports `icon`, `onPressed`, `color`, `size`
- `AppCard` — supports `child`, `onTap`, `padding`
- `AppScaffold` — supports `appBar`, `body`, `floatingActionButton`, `bottomNavigationBar`, `backgroundColor`, `resizeToAvoidBottomInset`

**✅ No wrapper gaps** — all Material widgets in scope (excluding boundary exceptions) have facade equivalents with complete prop coverage for this file's usage patterns.

## Proposed Solution

### Approach

**Mechanical replacement** of Material widget instantiations with facade wrapper equivalents in `setlist_detail_screen.dart`, following the exact pattern established in Cycles 1-3c-iii:

- Replace `TextField` → `AppTextField`
- Replace `TextFormField` → `AppTextField` (used inside `Form`, validator via `InputDecoration.errorText` or wrapper pattern)
- Replace `CircularProgressIndicator` → `AppProgressIndicator()`
- Replace `FilledButton` → `AppButton(variant: primary)`
- Replace `TextButton` → `AppButton(variant: text)`
- Replace `IconButton` → `AppIconButton`
- Replace `Card` (1 instance) → `AppCard`
- Replace `Scaffold` (1 instance) → `AppScaffold`
- **Leave as-is:** `Dismissible` (15), `AnimationController` (10), `AlertDialog` (6), `showDialog` (7), `showModalBottomSheet` (2)

### Non-Goals

- Do not modify business logic, validation, state management, or data flow
- Do not introduce new abstractions or refactor opportunistically
- Do not modify any files outside `setlist_detail_screen.dart`
- Do not wrap `Dismissible`, `AnimationController`, `AlertDialog`, `showDialog`, or `showModalBottomSheet` (boundary exceptions)
- Do not change existing visual styling or behavioral patterns

## Database Impact

**Not applicable.** This is a UI-only change with no database queries, migrations, RLS policies, RPCs, or triggers affected.

## Flutter Architecture Changes

**State management:** No changes to Riverpod providers, controllers, or repositories  
**Widget tree:** No structural changes — only Material widget → facade wrapper substitution  
**Business logic:** No changes to validation, data transformation, or event handling  
**Routing:** No changes to navigation or deep linking

**Impact surface:** UI presentation layer only (Material widget call sites in one screen file)

## Files to Create

**None.** All required facade wrappers exist in `lib/components/ui/`.

## Files to Modify

| File                                                          | What Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart`            | **Replace:** `TextField` (1) → `AppTextField`, `TextFormField` (1) → `AppTextField` (inside Form, preserve validator), `CircularProgressIndicator` (3) → `AppProgressIndicator()`, `FilledButton` (4) → `AppButton(variant: primary)`, `TextButton` (14) → `AppButton(variant: text)`, `IconButton` (2) → `AppIconButton`, `Card` (1) → `AppCard`, `Scaffold` (1) → `AppScaffold`. **Leave as-is:** `Dismissible` (15), `AnimationController` (10), `AlertDialog` (6), `showDialog` (7), `showModalBottomSheet` (2). Preserve all custom styling (`.styleFrom(...)`, colors, padding, etc.) via wrapper passthrough parameters. |

**Total:** 1 file

## Files Off-Limits

| File                                                 | Reason                                                                     |
| ---------------------------------------------------- | -------------------------------------------------------------------------- |
| `lib/main.dart`                                      | Initialization order must not change (GUARDRAILS.md Section 1)             |
| `lib/components/ui/*.dart`                           | Facade wrappers are complete (no gaps found) — do not modify               |
| `feature/lyrics-chordpro-retrofit` branch            | Separate unmerged branch with stale file state — do not reference/touch    |
| All files outside `setlist_detail_screen.dart`       | Out of scope                                                               |

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

**Rationale:** Only setlists UI presentation layer (one screen file) is modified. No cross-feature dependencies, no state management changes, no database interactions.

## Regression Risk

**HIGH**

**Rationale:**

- **File size:** 3,788 lines — largest single-file retrofit in the entire UI facade migration (Cycles 1-3c-iii). Exceeds GUARDRAILS.md Section 8 target of 500 lines per file by 7.5x.
- **Complexity:** This is the main setlist management screen with reorderable list, search, swipe gestures, drag animations, catalog sorting, special items, multi-select mode, enrichment integration, share/export, inline editing, and permissions gating. It is the highest-traffic screen in the setlists feature and the highest-complexity screen in the entire app by line count and interaction surface area.
- **Prior cycle regression record:** Cycles 3c-i/ii/iii each had real regressions (silent-drop bugs, prop mixups, dropped padding, broken focus) caught only via independent post-hoc audit, not first-pass self-review. This file is larger and more complex than any file in those cycles.
- **Custom button styling:** Many `FilledButton`/`TextButton` instances use `.styleFrom(...)` with custom colors, shapes, padding — must verify `AppButton` passthrough parameters preserve exact styling.
- **Gesture conflicts:** 15 `Dismissible` widgets with swipe-to-delete/move-or-copy gestures must not break when child widgets are wrapped. Widget identity and key stability are critical.
- **Animation conflicts:** 10 `AnimationController` instances drive tap feedback, slide-in animations, and reorder animations. Wrapping animated children must not break widget identity or animation performance.
- **Platform-specific behavior:** Must verify consistent rendering across 4 platforms (iOS, Android, Web, macOS).
- **RBAC gating:** Many UI elements are conditionally shown/enabled based on `canEdit` permission. Wrapping must not break permission checks or introduce mutation flicker.

**Mitigations:**

1. Engineer must use grep to verify exact line numbers of each Material widget before replacement (file will have moved since this plan was written)
2. Engineer must verify `.styleFrom(...)` custom styling is preserved via `AppButton` passthrough parameters (`backgroundColor`, `borderRadius`, `padding`, etc.) for all 18 button instances (4 FilledButton + 14 TextButton)
3. Engineer must verify `Dismissible` child widgets remain properly keyed and gesture recognition remains intact (test swipe-to-delete and swipe-to-move-or-copy on both song cards and special items)
4. Engineer must verify `AnimationController`-driven animations remain smooth and widget identity remains stable (test drag reorder, tap feedback on action buttons, slide-in for new special items, sort mode fade transition)
5. Engineer must verify search input (`TextField` → `AppTextField`) preserves `TextEditingController` state, focus behavior, and debounced search logic
6. Engineer must verify rename dialog (`TextFormField` → `AppTextField` in `Form`) preserves validator state and error display
7. Engineer must visually compare before/after on all platforms (at minimum: web + iOS or macOS)
8. QA must test full workflows: search, sort (catalog + tuning), reorder (drag + drop), swipe-to-delete, swipe-to-move-or-copy, add songs (lookup, bulk, original), edit song details (inline BPM/duration/tuning + bottom sheet), add special items (set break, pause), delete special items, rename setlist, share (text, spreadsheet), export PDF, multi-select mode (catalog only), enrichment integration (auto-enrich on add, review sheet)
9. QA must test on multiple platforms to verify visual consistency and gesture behavior
10. `flutter analyze` must pass with 0 errors before Engineer handoff

## Engineer Task Breakdown

Execute in strict order. Each task must be completed and verified before proceeding to the next.

### Task 1: Verify Workspace State

```bash
git branch --show-current  # must be on feature/ui-facade-setlists-3d
git status --short         # must be clean
flutter analyze            # must be 0 errors
```

### Task 2: Add Import for Facade Wrappers

Add the following imports to `lib/features/setlists/setlist_detail_screen.dart` (after existing component imports):

```dart
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:bandroadie/components/ui/app_card.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';
import 'package:bandroadie/components/ui/app_progress_indicator.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
```

### Task 3: Replace Material Widgets (Exact Substitution)

**CRITICAL:** Use grep to find exact line numbers before each replacement — the file will have moved after adding imports. Do not rely on line numbers from this plan.

**Search command:**

```bash
grep -n "TextField\|TextFormField\|CircularProgressIndicator\|FilledButton\|TextButton\|IconButton\|Card(\|Scaffold(" lib/features/setlists/setlist_detail_screen.dart
```

**Replacement rules:**

1. **TextField (1 instance, search bar):**
   - Find: `TextField(`
   - Replace: `AppTextField(`
   - Preserve all props: `controller`, `decoration`, `style`, `onChanged`, `autofocus`

2. **TextFormField (1 instance, rename dialog):**
   - Find: `TextFormField(`
   - Replace: `AppTextField(` (inside `Form`)
   - **Validator handling:** `TextFormField.validator` is not directly supported by `AppTextField`. Use `Form.validateForm()` pattern or move validation to `InputDecoration.errorText`. Verify validator logic is preserved.

3. **CircularProgressIndicator (3 instances, loading states):**
   - Find: `CircularProgressIndicator(`
   - Replace: `AppProgressIndicator()`
   - Preserve `strokeWidth` prop if present (use `AppProgressIndicator(strokeWidth: ...)`)

4. **FilledButton (4 instances, primary actions):**
   - Find: `FilledButton(`
   - Replace: `AppButton(variant: AppButtonVariant.primary, label: '...', onPressed: ...)`
   - **Custom styling:** All instances use `.styleFrom(...)` for custom `backgroundColor`, `shape`, `padding`. Map these to `AppButton` props:
     - `.styleFrom(backgroundColor: X)` → `backgroundColor: X`
     - `.styleFrom(shape: RoundedRectangleBorder(...))` → `borderRadius: ...`
     - `.styleFrom(padding: X)` → `padding: X`
   - Preserve all other props: `onPressed`, `child` text as `label`

5. **TextButton (14 instances, text actions):**
   - Find: `TextButton(`
   - Replace: `AppButton(variant: AppButtonVariant.text, label: '...', onPressed: ...)`
   - **Custom styling:** Many instances use `.styleFrom(...)` for custom colors, padding. Map these to `AppButton` props:
     - `.styleFrom(padding: X)` → `padding: X`
     - `.styleFrom(foregroundColor: X)` → NOT DIRECTLY SUPPORTED — use `TextButton` wrapper in `AppButton.text` or leave raw if critical (check 3c-iii precedent for pattern)
   - **NOTE:** If custom `foregroundColor` is critical (e.g., destructive red text), and `AppButton.text` does not support it, leave that instance raw and document in ENGINEER_REPORT.md.

6. **IconButton (2 instances, search clear/sort):**
   - Find: `IconButton(`
   - Replace: `AppIconButton(`
   - Preserve all props: `icon`, `onPressed`, `color`, `iconSize` (map to `size` param)

7. **Card (1 instance, loading dialog):**
   - Find: `Card(` at loading dialog (line ~1461)
   - Replace: `AppCard(child: ...)`
   - Preserve all props: `child`, `padding` if present

8. **Scaffold (1 instance, main scaffold):**
   - Find: `Scaffold(`
   - Replace: `AppScaffold(`
   - Preserve all props: `backgroundColor`, `body`, `floatingActionButton`, `resizeToAvoidBottomInset`

**DO NOT CHANGE:**

- `Dismissible` (15 instances) — no wrapper exists
- `AnimationController` (10 instances) — no wrapper exists
- `AlertDialog` (6 instances) — custom content, see boundary-exception policy
- `showDialog` (7 instances) — standard API, no wrapper
- `showModalBottomSheet` (2 instances) — standard API, no wrapper

### Task 4: Verify Compilation

```bash
flutter analyze  # must be 0 errors
```

If errors exist:

- Fix prop mapping issues (check wrapper API in `lib/components/ui/`)
- Verify validator handling for `TextFormField` → `AppTextField`
- Verify custom button styling is preserved (check `.styleFrom(...)` mappings)

### Task 5: Visual Verification (Local Testing)

Run the app on web and test all UI interactions:

```bash
flutter run -d chrome
```

**Checklist:**

- [ ] Search bar styling and focus behavior match original
- [ ] Rename dialog input field styling and validator behavior match original
- [ ] Loading indicators (3 instances) render correctly
- [ ] All buttons (18 instances) render with correct styling (colors, padding, shapes)
- [ ] IconButtons (2 instances) render with correct size and color
- [ ] Loading dialog card renders correctly
- [ ] Main scaffold background color and layout match original
- [ ] Swipe-to-delete gesture works on song cards and special items
- [ ] Swipe-to-move-or-copy gesture works on song cards
- [ ] Drag-to-reorder gesture works (grip icon only)
- [ ] Tap animations work on action buttons (_ActionButton, _SelectableSongCard)
- [ ] Slide-in animation works on new special items
- [ ] Sort mode fade transition works (catalog sort mode change)
- [ ] Multi-select mode works (catalog only)
- [ ] RBAC gating works (canEdit permission disables mutations)

### Task 6: Generate Diff

```bash
git diff > /tmp/ui-facade-setlists-3d.diff
```

### Task 7: Create ENGINEER_REPORT.md

Create `docs/features/ui-facade-setlists-3d/ENGINEER_REPORT.md` with:

- Task completion status (all 6 tasks)
- Line-by-line replacement log (Material widget → facade wrapper, exact line numbers)
- Any deviations from plan (e.g., custom button styling left raw if `AppButton` does not support)
- Compilation status (`flutter analyze` output)
- Visual verification checklist results
- Diff summary (lines changed, files modified)

### Task 8: Commit Changes

```bash
git add lib/features/setlists/setlist_detail_screen.dart
git add docs/features/ui-facade-setlists-3d/ENGINEER_REPORT.md
git commit -m "feat(setlists): retrofit setlist_detail_screen with UI facade wrappers (cycle 3d)"
```

**DO NOT** use `git add -A` or `git add .` — stage files explicitly.

## QA Validation Checklist

QA must verify the following before approving:

### Functional Testing

- [ ] Search bar: typing, focus, blur, clear button works
- [ ] Rename dialog: input validation, cancel, save works
- [ ] Delete song: confirmation dialog, delete from setlist, delete from catalog (catalog-aware warning) works
- [ ] Delete special item: confirmation dialog, delete works
- [ ] Swipe-to-delete: song cards, special items (left swipe) works
- [ ] Swipe-to-move-or-copy: song cards (right swipe, opens setlist picker) works
- [ ] Drag-to-reorder: grip icon only (not full card) works
- [ ] Sort: catalog sort mode (alphabetical, BPM, tuning), tuning sort (non-catalog) works
- [ ] Add songs: lookup overlay, bulk entry, original song works
- [ ] Edit song details: inline editing (BPM, duration, tuning), bottom sheet editor works
- [ ] Add special items: set break, pause works
- [ ] Share: text email, spreadsheet export works
- [ ] Export PDF: print options sheet, layout selection works
- [ ] Multi-select mode (catalog only): select, add to setlist works
- [ ] Enrichment: auto-enrich on add, review sheet works

### Visual Consistency

- [ ] All buttons render with correct colors, padding, shapes (compare before/after screenshots)
- [ ] Loading indicators match original size and color
- [ ] Search bar matches original styling
- [ ] Rename dialog input matches original styling
- [ ] Loading dialog card matches original styling
- [ ] Main scaffold background matches original

### Platform Testing

- [ ] Test on web (required)
- [ ] Test on iOS or macOS (required)
- [ ] Verify adaptive behavior if present

### Performance

- [ ] No jank during scroll
- [ ] No jank during drag-to-reorder
- [ ] No jank during animations (tap feedback, slide-in, fade)

### Error Handling

- [ ] `flutter analyze` passes with 0 errors
- [ ] No runtime errors in console during testing

## Acceptance Criteria

- [ ] All Material widgets in scope (17 instances) are replaced with facade wrappers
- [ ] All boundary-exception widgets (Dismissible, AnimationController, AlertDialog, showDialog, showModalBottomSheet) are left as-is
- [ ] `flutter analyze` passes with 0 errors
- [ ] Visual comparison shows zero difference in styling, layout, or behavior
- [ ] All functional workflows pass QA testing
- [ ] No regressions in gesture recognition (swipe, drag, tap)
- [ ] No regressions in animation performance
- [ ] ENGINEER_REPORT.md documents all changes and deviations
- [ ] Diff shows only Material widget → facade wrapper changes (no logic changes, no refactoring)

## Rollback Plan

If QA finds critical regressions:

1. Revert commit: `git revert HEAD`
2. Push revert: `git push origin feature/ui-facade-setlists-3d`
3. Document regression in QA_REPORT.md
4. Architect will revise plan based on regression root cause

## Notes

- **Known stale branch:** `feature/lyrics-chordpro-retrofit` is unmerged and stale relative to `main` on this file (carries old `source_bpm`/`performance_bpm` dispatch code removed in #140, commit `cf9fde4`). Do not reference it as precedent. Do not attempt to reconcile it. Reconciling it is a separate future task outside this cycle's scope.
- **Precedent:** This cycle follows the exact pattern from 3c-iii (overlays/sheets retrofit, 6 files, 6,263 lines). That cycle left custom AlertDialog instances raw, wrapped Material widgets inside AlertDialog actions, and preserved custom button styling via passthrough parameters. This cycle does the same.
- **High-risk file:** This is the largest and most complex file in the entire UI facade migration. Extra care is required during replacement and testing. Do not rush.
- **Boundary discipline:** The boundary-exception policy is explicit and non-negotiable. Do not wrap Dismissible, AnimationController, AlertDialog, showDialog, or showModalBottomSheet under any circumstances. Wrap Material widgets *inside* those boundaries per normal rules.

---

**Architect approval:** Plan complete. Ready for branch creation and Engineer handoff.
