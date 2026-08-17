# ARCHITECT_PLAN.md

**Feature Identifier:** `feature/event-date-picker-forui-migration`  
**Type:** feature  
**Branch:** `feature/event-date-picker-forui-migration`  
**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-17

---

## Problem Statement

Event creation and editing (`lib/features/events/widgets/event_editor_drawer.dart`) uses Flutter's stock Material `showDatePicker` dialog with manual theme override (`Theme(...).copyWith(colorScheme: ...)`), inconsistent with the rest of the app's Forui migration. The calendar display was successfully migrated to Forui's `FCalendar.wheel` (feature `calendar-forui-wheel-grid`, merged 2026-08-17, commit `37fc61a4`), but date _selection_ for event creation/editing still uses Material's default date picker.

**Scope:** Three date picker call sites in `event_editor_drawer.dart`:

1. Primary event date (`_showDatePicker`)
2. Recurring event until-date (`_showUntilDatePicker`)
3. Multi-date gig additional dates (`_showAdditionalDatePicker`)

**Out of Scope (explicitly):** Block-out date pickers (event_editor_drawer.dart lines ~2887/2908, add_block_out_drawer.dart), expense date pickers (gig_expense_subview.dart), financial entry date pickers (add_financial_entry_bottom_sheet.dart, gig_pay_bottom_sheet.dart). These use the identical pattern but are separate flows — candidate for follow-up feature, not this one.

---

## Root Cause Analysis

**Current State:**

`event_editor_drawer.dart` (3,153 lines) contains three date picker methods that call Material's `showDatePicker`:

```dart
Future<void> _showDatePicker() async {          // Line ~2981
  final picked = await showDatePicker(
    context: context,
    initialDate: _selectedDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primary,
            surface: context.colors.surface,
          ),
        ),
        child: child!,
      );
    },
  );
  // ... handle result
}
```

Identical pattern repeated in:

- `_showUntilDatePicker()` (line ~3127) — recurring event end date
- `_showAdditionalDatePicker(int index)` (line ~2956) — multi-date gig additional dates

Each manually overrides `colorScheme` to inject `AppColors.primary` (#F43F5E) and `context.colors.surface` to match the dark theme.

**Historical Context:**

Feature `ui-facade-gigs-setlists-retrofit` (Pattern 10, line 147) explicitly deferred this migration:

> "Date picker preservation: `showDatePicker` → keep as-is (no AppDatePicker wrapper exists, out of scope for this cycle)"

This was a valid deferral at the time — no Forui-native date picker component was integrated into the app, and the facade retrofit focused on button/text field/dialog wrappers, not date selection.

**Forui Capability:**

Forui v0.25.0 (installed, confirmed in `pubspec.yaml`) provides:

- **`FCalendar.grid`** with `FDateSelectionControl.managedSingle()` for single-date selection
- **`FCalendar.wheel`** (already used in `calendar_grid.dart` for display-only calendar)
- **`showFDialog`** (already wrapped by `lib/components/ui/app_dialog.dart`)
- **`FDateField.calendar`** (form field with popover picker — not applicable here, events use modal dialogs)

The app already uses Forui dialogs via `showAppDialog` wrapper. The calendar display uses `FCalendar.wheel` with `selectionControl: FDateSelectionControl.none()` (display-only). This feature adds _selection_ capability to the date picker flow via `FDateSelectionControl.managedSingle()`.

**Why This Needs Fixing:**

- **Inconsistency:** Calendar display is Forui (`FCalendar.wheel`), but date picking is Material (`showDatePicker`)
- **Manual theme patches:** Every `showDatePicker` call requires a custom builder to inject colors — brittle and non-standard
- **Migration completeness:** Part of the broader Forui migration — buttons, cards, switches, and calendar display are Forui; date pickers should be too

**Confidence:** HIGH (confirmed via code inspection, installed package API verified via subagent research)

---

## Proposed Solution

### Phase 1: Create Reusable App Date Picker Helper

**File:** Create `lib/components/ui/app_date_picker.dart`

**Action:** Implement `showAppDatePicker` helper function that wraps `FCalendar.grid` in a Forui dialog, providing a drop-in replacement for Material's `showDatePicker`.

**Signature:**

```dart
/// Shows an app-themed date picker dialog using Forui's FCalendar.grid.
///
/// Drop-in replacement for Material's [showDatePicker] with the same
/// parameter signature.
///
/// Returns the selected [DateTime] (normalized to midnight UTC), or null
/// if the user cancels or dismisses the dialog.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  // Implementation uses showFDialog + FCalendar.grid + FDateSelectionControl.managedSingle
}
```

**Rationale:**

- **Grid vs Wheel:** Use `FCalendar.grid` (not `.wheel`) because:
  - Desktop/web is primary event editing platform (larger screens, keyboard/mouse)
  - Grid provides month/year dropdown navigation (familiar UX, less touch-centric than wheel)
  - Dialogs favor compact grid layouts over swipeable month carousels
- **Dialog vs Bottom Sheet:** Maintain modal dialog UX (not bottom sheet) to preserve existing behavior — users expect date pickers to appear as centered dialogs
- **Managed vs Lifted State:** Use `FDateSelectionControl.managedSingle()` (calendar owns state internally) — simpler implementation, no external state management needed for one-shot date picking
- **Match existing `showAppDialog` pattern:** Follow precedent from `lib/components/ui/app_dialog.dart` which wraps `showFDialog`

**Implementation Notes:**

- Use `FCalendar.grid` with `fixedWeeks: false` (compact layout, no empty week rows)
- Set `selectionControl: FDateSelectionControl.managedSingle(initial: initialDate, toggleable: false, onChange: ...)`
  - `toggleable: false` — prevent accidental unselection by tapping selected date again (date picking should require explicit selection)
  - `onChange` callback pops dialog with selected date
- Set `start: firstDate, end: lastDate` via `FGridCalendarControl` to enforce valid date range
- No custom `dayBuilder` needed (unlike calendar display which renders event markers) — use default Forui day rendering
- Wrap `FCalendar.grid` in `FDialog` with padding/constraints similar to Material picker (approx 330-350px width)

---

### Phase 2: Migrate Event Editor Date Pickers

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Changes:**

1. **Add import:**

```dart
import '../../../components/ui/app_date_picker.dart';
```

2. **Replace `_showDatePicker()` method (line ~2981):**

**Before:**

```dart
Future<void> _showDatePicker() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _selectedDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
                surface: context.colors.surface,
              ),
        ),
        child: child!,
      );
    },
  );
  // ... handle result
}
```

**After:**

```dart
Future<void> _showDatePicker() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _selectedDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
  );
  // ... handle result (unchanged)
}
```

3. **Replace `_showUntilDatePicker()` method (line ~3127):**

**Before:**

```dart
Future<void> _showUntilDatePicker() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _untilDate ?? _selectedDate.add(const Duration(days: 30)),
    firstDate: _selectedDate,
    lastDate: _selectedDate.add(const Duration(days: 730)),
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
                surface: context.colors.surface,
              ),
        ),
        child: child!,
      );
    },
  );
  // ... handle result
}
```

**After:**

```dart
Future<void> _showUntilDatePicker() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _untilDate ?? _selectedDate.add(const Duration(days: 30)),
    firstDate: _selectedDate,
    lastDate: _selectedDate.add(const Duration(days: 730)),
  );
  // ... handle result (unchanged)
}
```

4. **Replace `_showAdditionalDatePicker(int index)` method (line ~2956):**

**Before:**

```dart
Future<void> _showAdditionalDatePicker(int index) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _additionalDates[index].date,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
    builder: (context, child) {
      return Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppColors.primary,
                surface: context.colors.surface,
                onSurface: context.colors.textPrimary,
              ),
        ),
        child: child!,
      );
    },
  );
  // ... handle result
}
```

**After:**

```dart
Future<void> _showAdditionalDatePicker(int index) async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _additionalDates[index].date,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
  );
  // ... handle result (unchanged)
}
```

**Rationale:** Each method becomes a trivial wrapper around `showAppDatePicker`, eliminating 10-15 lines of manual theme override per call site. Result-handling logic (null checks, `mounted` guards, state updates) remains unchanged — only the picker invocation is replaced.

---

## Database Impact

**Database:** not applicable (UI-only change, no schema/RLS/RPC modifications)

---

## Flutter Architecture Changes

**State Management:** no change — date selection still updates local widget state via `setState`, saved on form submission via `_handleSave()`. No new providers, notifiers, or repositories.

**Widgets:**

- **New:** `lib/components/ui/app_date_picker.dart` — reusable date picker helper (56-line target)
- **Modified:** `lib/features/events/widgets/event_editor_drawer.dart` — replace 3 date picker methods (net reduction ~30-40 lines after removing manual theme builders)

**Repositories:** no change

---

## Files to Create

| File                                     | Justification                                                                                                                                                                                                                                                   |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_date_picker.dart` | Reusable wrapper for Forui date picker dialog, follows precedent of `app_dialog.dart`, `app_bottom_sheet.dart`, `app_button.dart` in same directory. Drop-in replacement for Material `showDatePicker` ensures consistency across future date picker use cases. |

---

## Files to Modify

| File                                                   | What Changes                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | Add import for `app_date_picker.dart`. Replace 3 date picker methods: `_showDatePicker()`, `_showUntilDatePicker()`, `_showAdditionalDatePicker(int)` — each replaces `showDatePicker` call + custom theme builder with single `showAppDatePicker` call. Result-handling logic unchanged. Net reduction ~30-40 lines. |

---

## Files Off-Limits

| File                                                                       | Reason                                                                                                                                  |
| -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_form_fields.dart`                       | Renders date picker buttons (triggers callbacks), does not call `showDatePicker` directly — no changes needed                           |
| `lib/features/events/widgets/event_editor_drawer.dart` (block-out pickers) | `_selectBlockOutStartDate()`, `_selectBlockOutUntilDate()` methods explicitly out of scope (lines ~2887/2908) — separate feature domain |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`                  | 2 `showDatePicker` calls for block-out dates — explicitly out of scope                                                                  |
| `lib/features/events/widgets/gig_expense_subview.dart`                     | 2 `showDatePicker` calls for expense/reimbursement dates — explicitly out of scope                                                      |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`    | 1 `showDatePicker` call for entry date — explicitly out of scope                                                                        |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`                | 1 `showDatePicker` call for pay date — explicitly out of scope                                                                          |
| `lib/features/calendar/widgets/calendar_grid.dart`                         | Already migrated to Forui (`FCalendar.wheel`) in `calendar-forui-wheel-grid` feature — do not touch                                     |
| `lib/main.dart`                                                            | Initialization order must not change (GUARDRAILS.md section 1)                                                                          |
| Any migration, edge function, or database file                             | UI-only change, no backend impact                                                                                                       |

---

## System Impact Map

| System                                 | Impact         | Detail                                                                                 |
| -------------------------------------- | -------------- | -------------------------------------------------------------------------------------- |
| Gigs                                   | **affected**   | Date selection UI for creating/editing gigs (primary date, additional dates)           |
| Rehearsals                             | **affected**   | Date selection UI for creating/editing rehearsals (primary date, recurring until-date) |
| Setlists / Catalog                     | **unaffected** | No date picker usage in setlist flows                                                  |
| Members / RBAC                         | **unaffected** | No permission or role changes                                                          |
| Auth / Session                         | **unaffected** | No authentication or session flow changes                                              |
| Routing                                | **unaffected** | No route changes                                                                       |
| Notifications                          | **unaffected** | No notification triggers or delivery changes                                           |
| Platform (iOS / Android / Web / macOS) | **affected**   | UI change visible on all platforms — date picker dialog appearance/behavior            |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- **Isolated change:** Only touches date picker invocation in event editor — no changes to state management, form validation, submission logic, or data persistence
- **Drop-in replacement:** `showAppDatePicker` matches `showDatePicker` signature exactly (4 required params: context, initialDate, firstDate, lastDate) — result handling unchanged
- **No shared code paths:** Event date pickers are isolated from block-out, expense, and financial date pickers (all out of scope) — no cross-contamination risk
- **No auth/session/routing impact:** Pure UI change within event editing flow
- **Forui precedent:** App already uses Forui dialogs (`showAppDialog`), bottom sheets (`showAppBottomSheet`), and `FCalendar` for calendar display — this extends existing patterns

**Risk factors:**

- **File size:** `event_editor_drawer.dart` is 3,153 lines (GUARDRAILS.md section 8 target: 400 lines for feature widgets) — large file increases cognitive load, but changes are localized to 3 methods
- **Visual drift:** Forui date picker may render slightly differently than Material (cell sizes, month/year navigation) — acceptable per problem statement ("minor visual drift... acceptable")
- **First use of FCalendar.grid with selection:** `calendar_grid.dart` uses `FCalendar.wheel` with `selectionControl: .none()` (display-only). This feature introduces first usage of single-date selection — well-supported by Forui API, but new to codebase

---

## Engineer Task Breakdown

Execute in order. Stop and report blockers immediately.

### Task 1: Create app_date_picker.dart

**File:** `lib/components/ui/app_date_picker.dart`

**Action:** Implement `showAppDatePicker` helper function.

**Requirements:**

1. Import `package:flutter/material.dart` and `package:forui/forui.dart`
2. Define function signature matching Material `showDatePicker`:
   ```dart
   Future<DateTime?> showAppDatePicker({
     required BuildContext context,
     required DateTime initialDate,
     required DateTime firstDate,
     required DateTime lastDate,
   })
   ```
3. Implementation:
   - Create `FGridCalendarControl(start: firstDate, end: lastDate)` to enforce date range
   - Create `FDateSelectionControl.managedSingle(initial: initialDate, toggleable: false, onChange: (date) => Navigator.of(context).pop(date))`
   - Call `showFDialog<DateTime?>(context: context, barrierDismissible: true, builder: ...)`
   - Builder returns `FDialog(builder: (context, style) => ConstrainedBox(maxWidth: 340, child: FCalendar.grid(...)))`
   - Pass `control`, `selectionControl`, `fixedWeeks: false` to `FCalendar.grid`
4. Add dartdoc comment explaining purpose and usage
5. Verify `flutter analyze` passes (0 errors)

**Target length:** ~60 lines (including imports, comments)

**Verification:** File created, compiles cleanly, imports correct

---

### Task 2: Migrate \_showDatePicker()

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Action:** Replace Material `showDatePicker` call with `showAppDatePicker` in `_showDatePicker()` method.

**Requirements:**

1. Add import at top of file: `import '../../../components/ui/app_date_picker.dart';`
2. Locate `_showDatePicker()` method (line ~2981)
3. Replace entire `showDatePicker(...)` call (including `builder` parameter) with:
   ```dart
   final picked = await showAppDatePicker(
     context: context,
     initialDate: _selectedDate,
     firstDate: DateTime.now().subtract(const Duration(days: 365)),
     lastDate: DateTime.now().add(const Duration(days: 730)),
   );
   ```
4. **Do not change:** null check (`if (picked != null)`), `mounted` guard (if present), `setState` logic, `_selectedDays` update, `_markDirty()` call
5. Verify `flutter analyze` passes (0 errors)

**Verification:** Method simplified, theme override removed, result handling unchanged

---

### Task 3: Migrate \_showUntilDatePicker()

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Action:** Replace Material `showDatePicker` call with `showAppDatePicker` in `_showUntilDatePicker()` method.

**Requirements:**

1. Locate `_showUntilDatePicker()` method (line ~3127)
2. Replace entire `showDatePicker(...)` call (including `builder` parameter) with:
   ```dart
   final picked = await showAppDatePicker(
     context: context,
     initialDate: _untilDate ?? _selectedDate.add(const Duration(days: 30)),
     firstDate: _selectedDate,
     lastDate: _selectedDate.add(const Duration(days: 730)),
   );
   ```
3. **Do not change:** null check, `mounted` guard, `setState` logic, `_untilDate` normalization to noon (line ~3143), `_markDirty()` call
4. Verify `flutter analyze` passes (0 errors)

**Verification:** Method simplified, theme override removed, result handling unchanged

---

### Task 4: Migrate \_showAdditionalDatePicker(int index)

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Action:** Replace Material `showDatePicker` call with `showAppDatePicker` in `_showAdditionalDatePicker(int)` method.

**Requirements:**

1. Locate `_showAdditionalDatePicker(int index)` method (line ~2956)
2. Replace entire `showDatePicker(...)` call (including `builder` parameter) with:
   ```dart
   final picked = await showAppDatePicker(
     context: context,
     initialDate: _additionalDates[index].date,
     firstDate: DateTime.now().subtract(const Duration(days: 365)),
     lastDate: DateTime.now().add(const Duration(days: 730)),
   );
   ```
3. **Do not change:** null check, `mounted` guard, `_updateAdditionalDate(index, picked)` call, `HapticFeedback.selectionClick()` call
4. Verify `flutter analyze` passes (0 errors)

**Verification:** Method simplified, theme override removed, result handling unchanged

---

### Task 5: Final Verification

**Action:** Run `flutter analyze` on modified files.

**Requirements:**

1. Run `flutter analyze lib/components/ui/app_date_picker.dart lib/features/events/widgets/event_editor_drawer.dart`
2. Confirm 0 errors, 0 warnings
3. Confirm no unused imports
4. Confirm `mounted` guard exists after all `await showAppDatePicker` calls

**Verification:** Analyzer clean

---

## Verification Plan

### Tier 1 — Pre-deployment (not applicable)

N/A — no database changes, no migrations, no backend deployment required.

---

### Tier 2 — Post-deployment (Manual QA Only)

**Context:** This is a UI-only change with no database impact. All verification is manual interaction testing.

#### Test 1: Primary Event Date Picker (Gig)

**Steps:**

1. Open event editor drawer (create new gig)
2. Tap primary date field
3. **Verify:** Forui date picker dialog appears (not Material picker)
4. **Verify:** Dialog shows current month/year header with dropdown navigation
5. **Verify:** Today's date is visually highlighted
6. **Verify:** Grid layout (7 columns, weeks as rows)
7. Select a date 1 week from today
8. **Verify:** Dialog dismisses, selected date appears in field
9. **Verify:** Date format matches previous behavior (e.g., "Wed, Aug 24, 2026")
10. Save event
11. **Verify:** Event created with correct date

**Expected:** Forui dialog replaces Material dialog, date selection works identically

---

#### Test 2: Recurring Rehearsal Until-Date Picker

**Steps:**

1. Open event editor drawer (create new rehearsal)
2. Toggle "Recurring" on
3. Select "Weekly" frequency
4. Tap "Until Date" field
5. **Verify:** Forui date picker dialog appears
6. **Verify:** `firstDate` is constrained to primary date (cannot select earlier dates)
7. Select a date 2 months from primary date
8. **Verify:** Dialog dismisses, until-date appears in field
9. Save rehearsal
10. **Verify:** Recurring rehearsals generated correctly up to until-date

**Expected:** Until-date picker uses Forui dialog, date range constraint enforced

---

#### Test 3: Multi-Date Gig Additional Dates

**Steps:**

1. Open event editor drawer (create new gig)
2. Toggle "Potential Event" on
3. Tap "+ Add Date" button
4. Tap on the new additional date field
5. **Verify:** Forui date picker dialog appears
6. Select a date 3 days from primary date
7. **Verify:** Dialog dismisses, additional date appears
8. Add a second additional date (different date)
9. **Verify:** Both additional dates show correctly
10. Save gig
11. **Verify:** Gig created with primary + 2 additional dates

**Expected:** Additional date pickers use Forui dialog, multiple dates selectable

---

#### Test 4: Date Picker Cancel Behavior

**Steps:**

1. Open event editor drawer (any event type)
2. Tap date field
3. **Verify:** Dialog appears
4. Tap outside dialog (barrier dismiss)
5. **Verify:** Dialog dismisses, date unchanged (not null)
6. Tap date field again
7. **Verify:** Dialog reopens with previous initialDate
8. Press Escape key (desktop) or tap barrier (mobile)
9. **Verify:** Dialog dismisses, date unchanged

**Expected:** Cancel/dismiss preserves existing date value

---

#### Test 5: Block-Out Date Pickers Unchanged (Regression Check)

**Steps:**

1. Open event editor drawer (switch to "Block Out" tab if multi-tab, or use calendar screen's block-out creation)
2. Tap block-out start date field
3. **Verify:** Material date picker dialog appears (NOT Forui picker — out of scope)
4. Cancel dialog
5. Tap block-out end date field
6. **Verify:** Material date picker dialog appears (NOT Forui picker)

**Expected:** Block-out date pickers unchanged — still use Material `showDatePicker`

---

#### Test 6: Cross-Platform Smoke Test

**Platforms:** Web (Chrome), iOS (simulator), macOS (desktop)

**Steps (per platform):**

1. Create new gig
2. Tap primary date field
3. **Verify:** Forui date picker dialog renders correctly (no layout clipping, calendar grid visible)
4. Select a date
5. **Verify:** Selection works, dialog dismisses
6. Save event
7. **Verify:** Event created successfully

**Expected:** Date picker works identically across all platforms (iOS, Android, macOS, Web)

---

#### Test 7: Dark Mode Theme Consistency

**Steps:**

1. Confirm app is in dark mode (default for BandRoadie)
2. Open event editor
3. Tap date field
4. **Verify:** Dialog background color matches app theme (dark surface color)
5. **Verify:** Selected date uses rose accent (`#F43F5E` / `AppColors.primary`)
6. **Verify:** Text colors are readable (light on dark)
7. **Verify:** Today's date is highlighted with rose border

**Expected:** Forui date picker inherits theme correctly, rose accent applied to selected date

---

## QA Regression Areas

QA must specifically test:

### Primary Areas (Core Feature)

1. **Event date selection UX:**
   - Forui dialog appearance/behavior vs Material dialog baseline
   - Date selection interaction (tap day cell, dialog dismiss)
   - Cancel/dismiss behavior (barrier tap, Escape key)
   - Today highlighting (rose border/accent)
   - Month/year navigation (header dropdowns vs Material swipe)

2. **All three date picker types:**
   - Primary event date (gigs and rehearsals)
   - Recurring until-date (rehearsals only)
   - Additional dates (potential gigs only)

3. **Cross-platform rendering:**
   - Web (Chrome, Safari)
   - iOS (simulator + physical device)
   - macOS (desktop)
   - Android (if accessible — not primary platform but should work)

4. **Form submission integrity:**
   - Verify events save with correct dates
   - Verify recurring events generate correct occurrences based on until-date
   - Verify multi-date gigs persist all dates correctly

### Regression Areas (Out-of-Scope Boundary Verification)

5. **Block-out date pickers (must remain Material):**
   - Event editor block-out start/end dates
   - Add Block Out drawer start/end dates
   - Verify these still use Material `showDatePicker` (not migrated)

6. **Expense date pickers (must remain Material):**
   - Gig expense date, reimbursement date
   - Verify these still use Material `showDatePicker` (not migrated)

7. **Financial entry date pickers (must remain Material):**
   - Add Financial Entry bottom sheet
   - Gig Pay bottom sheet
   - Verify these still use Material `showDatePicker` (not migrated)

8. **Calendar display (must remain unchanged):**
   - Calendar screen month grid uses `FCalendar.wheel` (already Forui)
   - Tapping a day opens `DayDetailBottomSheet` (not affected by this feature)
   - Month swipe navigation, event markers unchanged

### Visual Quality

9. **Forui date picker dialog visual consistency:**
   - Dialog width/height appropriate (~340px width target)
   - No layout overflow or clipping
   - Calendar grid fills dialog width (7 equal columns)
   - Cell borders visible (neutral for normal days, rose for today)
   - Header alignment (month/year dropdowns centered)

10. **Brand adherence:**
    - Rose accent (`#F43F5E`) applied to selected date and today's border
    - Dark mode background/surface colors correct
    - Text colors readable

---

## Rollout / Migration Strategy

**Deployment:** Standard web deploy via `./tools/deploy_web.sh` after QA approval. No backend migration required (UI-only change).

**Rollback Plan:** If critical regression detected, revert commit and redeploy. No data migration cleanup needed (no database changes).

**Monitoring:** No special monitoring required — date picker changes are immediately visible in event editor. User feedback via support channel if issues arise.

---

## Out of Scope

Explicitly excluded from this feature (candidate for follow-up feature `event-date-picker-forui-migration-phase-2`):

1. **Block-out date pickers:**
   - `lib/features/events/widgets/event_editor_drawer.dart` — `_selectBlockOutStartDate()`, `_selectBlockOutUntilDate()` (lines ~2887/2908)
   - `lib/features/calendar/widgets/add_block_out_drawer.dart` — 2 `showDatePicker` calls

2. **Expense date pickers:**
   - `lib/features/events/widgets/gig_expense_subview.dart` — expense date, reimbursement date (2 calls)

3. **Financial entry date pickers:**
   - `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` — entry date (1 call)
   - `lib/features/financials/widgets/gig_pay_bottom_sheet.dart` — pay date (1 call)

**Total out of scope:** 8 `showDatePicker` call sites in 5 files (all use identical manual theme override pattern)

---

**End of ARCHITECT_PLAN.md**
