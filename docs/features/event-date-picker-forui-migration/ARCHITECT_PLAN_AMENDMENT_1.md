# ARCHITECT_PLAN_AMENDMENT_1.md

**Feature Identifier:** `feature/event-date-picker-forui-migration`  
**Amendment:** 1  
**Date:** 2026-08-17  
**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Supersedes:** QA_REPORT.md APPROVED verdict (narrower scope only)

---

## Amendment Context

**Original Scope (Completed & QA Approved):**

Three date pickers in `event_editor_drawer.dart`:

- Primary event date (`_showDatePicker`)
- Recurring event until-date (`_showUntilDatePicker`)
- Multi-date gig additional dates (`_showAdditionalDatePicker`)

**Original Scope Explicitly Excluded:**

Eight date pickers marked "out of scope" in ARCHITECT_PLAN.md Files Off-Limits table:

1. Block-out date pickers in event_editor_drawer.dart (2 pickers)
2. Block-out date pickers in add_block_out_drawer.dart (2 pickers)
3. Expense date pickers in gig_expense_subview.dart (2 pickers)
4. Financial entry date picker in add_financial_entry_bottom_sheet.dart (1 picker)
5. Gig pay date picker in gig_pay_bottom_sheet.dart (1 picker)

**Tony's Request:**

> "Block out date isn't updated. I want all date pickers updated."

**Amendment Scope:**

Migrate all 8 remaining `showDatePicker` call sites to use the existing `showAppDatePicker` helper created in the base implementation. Same pattern, no new components, just extending coverage to achieve 100% date picker consistency across the app.

---

## Root Cause Analysis

**Current State:**

After the base implementation (QA APPROVED), the app has:

- ✅ **Forui date pickers:** Event creation/editing primary dates (3 call sites in event_editor_drawer.dart)
- ❌ **Material date pickers:** Block-out, expense, and financial flows (8 call sites across 4 files)

All 8 remaining sites use identical pattern to the original 3:

- Call Material `showDatePicker`
- Pass custom `builder: (context, child) => Theme(...).copyWith(colorScheme: ...)` to override colors
- Use `AppColors.primary` (#F43F5E) for accent
- Vary `firstDate`/`lastDate` constraints per flow

**Inconsistency:**

Users creating events see Forui date picker. Same user creating block-out dates or entering expenses sees Material date picker. Inconsistent UX violates the Forui migration goal.

**Solution Availability:**

The base implementation already created `showAppDatePicker` helper (`lib/components/ui/app_date_picker.dart`, 38 lines) that wraps `FCalendar.grid` with proper theme integration. Drop-in replacement ready — no new code needed, just call site replacements.

**Confidence:** HIGH (verified via grep search, code inspection confirmed all 8 sites use identical Material pattern)

---

## Proposed Solution

### Phase 1: Verify Base Implementation Intact

**Action:** Confirm `showAppDatePicker` helper exists and analyzer-clean before proceeding.

**Requirements:**

1. Verify `lib/components/ui/app_date_picker.dart` exists (created in base implementation)
2. Run `flutter analyze lib/components/ui/app_date_picker.dart` → 0 errors expected
3. Verify signature matches Material `showDatePicker`: 4 required params (context, initialDate, firstDate, lastDate)

**Rationale:** Amendment depends on base implementation. If base is broken, stop and escalate to Manager.

---

### Phase 2: Migrate Block-Out Date Pickers (Event Editor)

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Changes:**

1. **Replace `_selectBlockOutStartDate()` method (line ~2888):**

**Before:**

```dart
Future<void> _selectBlockOutStartDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _selectedDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    builder: (context, child) => _blockOutDatePickerTheme(child),
  );
  if (picked != null) {
    setState(() {
      _selectedDate = picked;
      if (_blockOutUntilDate != null &&
          _blockOutUntilDate!.isBefore(_selectedDate)) {
        _blockOutUntilDate = null;
      }
    });
    _markDirty();
    HapticFeedback.selectionClick();
  }
}
```

**After:**

```dart
Future<void> _selectBlockOutStartDate() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _selectedDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
  );
  if (picked != null) {
    setState(() {
      _selectedDate = picked;
      if (_blockOutUntilDate != null &&
          _blockOutUntilDate!.isBefore(_selectedDate)) {
        _blockOutUntilDate = null;
      }
    });
    _markDirty();
    HapticFeedback.selectionClick();
  }
}
```

2. **Replace `_selectBlockOutUntilDate()` method (line ~2909):**

**Before:**

```dart
Future<void> _selectBlockOutUntilDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _blockOutUntilDate ?? _selectedDate,
    firstDate: _selectedDate,
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    builder: (context, child) => _blockOutDatePickerTheme(child),
  );
  if (picked != null) {
    setState(() => _blockOutUntilDate = picked);
    _markDirty();
    HapticFeedback.selectionClick();
  }
}
```

**After:**

```dart
Future<void> _selectBlockOutUntilDate() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _blockOutUntilDate ?? _selectedDate,
    firstDate: _selectedDate,
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
  );
  if (picked != null) {
    setState(() => _blockOutUntilDate = picked);
    _markDirty();
    HapticFeedback.selectionClick();
  }
}
```

3. **Optional Cleanup:**

After both replacements, `_blockOutDatePickerTheme(Widget?)` helper method (lines ~2921-2931) becomes unused. Remove if no other references exist. Verify with grep search before deletion.

**Rationale:** Same file already imports `app_date_picker.dart` from base implementation (line ~62). No new import needed. Result-handling logic (null check, setState, \_markDirty, haptic feedback) preserved exactly.

---

### Phase 3: Migrate Block-Out Date Pickers (Calendar Screen)

**File:** `lib/features/calendar/widgets/add_block_out_drawer.dart`

**Changes:**

1. **Add import:**

```dart
import '../../../components/ui/app_date_picker.dart';
```

2. **Replace `_selectStartDate()` method (line ~453):**

**Before:**

```dart
Future<void> _selectStartDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _startDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    builder: (context, child) => _datePickerTheme(child),
  );

  if (picked != null) {
    setState(() {
      _startDate = picked;
      // Clear until date if it's now before start date
      if (_untilDate != null && _untilDate!.isBefore(_startDate)) {
        _untilDate = null;
      }
    });
    HapticFeedback.selectionClick();
  }
}
```

**After:**

```dart
Future<void> _selectStartDate() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _startDate,
    firstDate: DateTime.now().subtract(const Duration(days: 365)),
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
  );

  if (picked != null) {
    setState(() {
      _startDate = picked;
      // Clear until date if it's now before start date
      if (_untilDate != null && _untilDate!.isBefore(_startDate)) {
        _untilDate = null;
      }
    });
    HapticFeedback.selectionClick();
  }
}
```

3. **Replace `_selectUntilDate()` method (line ~474):**

**Before:**

```dart
Future<void> _selectUntilDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _untilDate ?? _startDate,
    firstDate: _startDate,
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    builder: (context, child) => _datePickerTheme(child),
  );

  if (picked != null) {
    setState(() {
      _untilDate = picked;
    });
    HapticFeedback.selectionClick();
  }
}
```

**After:**

```dart
Future<void> _selectUntilDate() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _untilDate ?? _startDate,
    firstDate: _startDate,
    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
  );

  if (picked != null) {
    setState(() {
      _untilDate = picked;
    });
    HapticFeedback.selectionClick();
  }
}
```

4. **Optional Cleanup:**

After both replacements, `_datePickerTheme(Widget?)` helper method (lines ~495-504) becomes unused. Remove if no other references exist. Verify with grep search before deletion.

**Rationale:** Identical pattern to event_editor_drawer.dart. Result-handling logic (null check, setState, haptic feedback, until-date clearing) preserved exactly.

---

### Phase 4: Migrate Expense Date Pickers

**File:** `lib/features/events/widgets/gig_expense_subview.dart`

**Changes:**

1. **Add import:**

```dart
import '../../../components/ui/app_date_picker.dart';
```

2. **Replace `_pickDate()` method (line ~186):**

**Before:**

```dart
Future<void> _pickDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _entryDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!),
  );
  if (!mounted || picked == null) return;
  setState(() => _entryDate = picked);
}
```

**After:**

```dart
Future<void> _pickDate() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _entryDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (!mounted || picked == null) return;
  setState(() => _entryDate = picked);
}
```

3. **Replace `_pickReimbursedDate()` method (line ~199):**

**Before:**

```dart
Future<void> _pickReimbursedDate() async {
  final initialDate = _reimbursedDate ?? DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!),
  );
  if (!mounted || picked == null) return;
  setState(() => _reimbursedDate = picked);
}
```

**After:**

```dart
Future<void> _pickReimbursedDate() async {
  final initialDate = _reimbursedDate ?? DateTime.now();
  final picked = await showAppDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (!mounted || picked == null) return;
  setState(() => _reimbursedDate = picked);
}
```

**Rationale:** Simpler theme builder (no AppColors.primary override), but still inconsistent with Forui. Wide date range (2000-2100) preserved — no constraints tighter than 100-year window. Mounted guards already exist — preserve exactly.

---

### Phase 5: Migrate Financial Entry Date Picker

**File:** `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`

**Changes:**

1. **Add import:**

```dart
import '../../../components/ui/app_date_picker.dart';
```

2. **Replace `_pickDate()` method (line ~349):**

**Before:**

```dart
Future<void> _pickDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _entryDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!),
  );
  if (!mounted || picked == null) return;
  setState(() => _entryDate = picked);
}
```

**After:**

```dart
Future<void> _pickDate() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _entryDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (!mounted || picked == null) return;
  setState(() => _entryDate = picked);
}
```

**Rationale:** Same pattern as gig_expense_subview.dart. Wide date range (2000-2100) preserved. Mounted guard already exists — preserve exactly.

---

### Phase 6: Migrate Gig Pay Date Picker

**File:** `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`

**Changes:**

1. **Add import:**

```dart
import '../../../components/ui/app_date_picker.dart';
```

2. **Replace `_pickDate()` method (line ~106):**

**Before:**

```dart
Future<void> _pickDate() async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _paymentDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
    builder: (context, child) => Theme(
      data: Theme.of(context),
      child: child!,
    ),
  );
  if (!mounted) return;
  if (picked != null) {
    setState(() => _paymentDate = picked);
  }
}
```

**After:**

```dart
Future<void> _pickDate() async {
  final picked = await showAppDatePicker(
    context: context,
    initialDate: _paymentDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  if (!mounted) return;
  if (picked != null) {
    setState(() => _paymentDate = picked);
  }
}
```

**Rationale:** Same pattern as other financial/expense flows. Wide date range (2000-2100) preserved. Mounted guard already exists — preserve exactly. Note the mounted guard is checked before null check (slightly different order than Phase 4-5, but existing behavior preserved).

---

### Phase 7: Optional Cleanup

**Action:** Remove unused theme helper methods if confirmed safe.

**Requirements:**

1. In `event_editor_drawer.dart`: Run `grep -n "_blockOutDatePickerTheme" lib/features/events/widgets/event_editor_drawer.dart`
   - If only method definition found (no other calls), delete `_blockOutDatePickerTheme(Widget?)` method (lines ~2921-2931)
2. In `add_block_out_drawer.dart`: Run `grep -n "_datePickerTheme" lib/features/calendar/widgets/add_block_out_drawer.dart`
   - If only method definition found (no other calls), delete `_datePickerTheme(Widget?)` method (lines ~495-504)

**Rationale:** These helpers were single-purpose wrappers for `showDatePicker` theme overrides. After migration to `showAppDatePicker`, they become dead code. Remove to reduce line count and prevent confusion.

**Critical:** Only delete if grep confirms no other references. If other code paths use these helpers, **do not delete** — leave for future cleanup.

---

### Phase 8: Final Verification

**Action:** Run `flutter analyze` and verify imports.

**Requirements:**

1. Run `flutter analyze` on all modified files:
   ```bash
   flutter analyze \
     lib/features/events/widgets/event_editor_drawer.dart \
     lib/features/calendar/widgets/add_block_out_drawer.dart \
     lib/features/events/widgets/gig_expense_subview.dart \
     lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart \
     lib/features/financials/widgets/gig_pay_bottom_sheet.dart
   ```
2. Confirm 0 errors, 0 new warnings
3. Verify no unused imports (analyzer will flag `unused_import` if app_date_picker.dart not used)
4. Verify Material import still present (other widgets in these files still use Material components)

**Verification:** Analyzer clean, all imports justified

---

## Database Impact

**Database:** not applicable (UI-only change, no schema/RLS/RPC modifications)

---

## Flutter Architecture Changes

**State Management:** no change — all date pickers still update local widget state via `setState`, saved on form submission via existing flows.

**Widgets:**

- **Modified:** 5 files (event_editor_drawer.dart, add_block_out_drawer.dart, gig_expense_subview.dart, add_financial_entry_bottom_sheet.dart, gig_pay_bottom_sheet.dart)
- **No new files:** Reuses existing `lib/components/ui/app_date_picker.dart` from base implementation
- **Net line change:** ~-60 to -80 lines (removes theme override boilerplate, optionally removes 2 unused helper methods)

**Repositories:** no change

---

## Files to Create

None (reuses base implementation)

---

## Files to Modify

| File                                                                    | What Changes                                                                                                                                                                                                                                                                                                                                              |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart`                  | Replace 2 block-out date picker methods: `_selectBlockOutStartDate()`, `_selectBlockOutUntilDate()` — each replaces `showDatePicker` + `_blockOutDatePickerTheme` builder with `showAppDatePicker` call. Result-handling logic unchanged. Optional: delete `_blockOutDatePickerTheme` helper if unused. (Note: file already imports app_date_picker.dart) |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`               | Add import for `app_date_picker.dart`. Replace 2 date picker methods: `_selectStartDate()`, `_selectUntilDate()` — each replaces `showDatePicker` + `_datePickerTheme` builder with `showAppDatePicker` call. Result-handling logic unchanged. Optional: delete `_datePickerTheme` helper if unused. Net reduction ~15-25 lines.                          |
| `lib/features/events/widgets/gig_expense_subview.dart`                  | Add import for `app_date_picker.dart`. Replace 2 date picker methods: `_pickDate()`, `_pickReimbursedDate()` — each replaces `showDatePicker` + simple Theme builder with `showAppDatePicker` call. Mounted guards preserved. Net reduction ~8-10 lines.                                                                                                  |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | Add import for `app_date_picker.dart`. Replace `_pickDate()` method — replaces `showDatePicker` + simple Theme builder with `showAppDatePicker` call. Mounted guard preserved. Net reduction ~4 lines.                                                                                                                                                    |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`             | Add import for `app_date_picker.dart`. Replace `_pickDate()` method — replaces `showDatePicker` + Theme builder with `showAppDatePicker` call. Mounted guard preserved. Net reduction ~5-6 lines.                                                                                                                                                         |

---

## Files Off-Limits

| File                                                   | Reason                                                                                                                                                                                        |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_date_picker.dart`               | Created in base implementation, QA APPROVED — do not modify (amendment only replaces call sites)                                                                                              |
| `lib/features/events/widgets/event_form_fields.dart`   | Renders date picker buttons (triggers callbacks), does not call `showDatePicker` directly — no changes needed                                                                                 |
| `lib/features/calendar/widgets/calendar_grid.dart`     | Already migrated to Forui (`FCalendar.wheel`) in `calendar-forui-wheel-grid` feature — do not touch                                                                                           |
| `lib/main.dart`                                        | Initialization order must not change (GUARDRAILS.md section 1)                                                                                                                                |
| Any migration, edge function, or database file         | UI-only change, no backend impact                                                                                                                                                             |
| Any file not explicitly listed in "Files to Modify"    | Amendment scope limited to 8 remaining `showDatePicker` call sites — do not expand opportunistically                                                                                          |
| Test files                                             | No test coverage exists for date picker flows (per base implementation ENGINEER_REPORT.md "Test Results: Not run") — do not create tests (out of scope)                                       |
| `lib/features/events/widgets/event_editor_drawer.dart` | Lines 2970-3010 (`_showDatePicker()`), 3127-3143 (`_showUntilDatePicker()`), 2956-2969 (`_showAdditionalDatePicker()`) — already migrated in base implementation (QA APPROVED) — do not touch |

---

## System Impact Map

| System                                 | Impact         | Detail                                                                                                                          |
| -------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | **affected**   | Date selection UI for gig block-out dates, expense entry/reimbursement dates (existing: primary/additional dates)               |
| Rehearsals                             | **affected**   | Date selection UI for rehearsal block-out dates (existing: primary date, recurring until-date)                                  |
| Setlists / Catalog                     | **unaffected** | No date picker usage in setlist flows                                                                                           |
| Members / RBAC                         | **unaffected** | No permission or role changes                                                                                                   |
| Auth / Session                         | **unaffected** | No authentication or session flow changes                                                                                       |
| Routing                                | **unaffected** | No route changes                                                                                                                |
| Notifications                          | **unaffected** | No notification triggers or delivery changes                                                                                    |
| Calendar                               | **affected**   | Date selection UI for creating block-out dates from calendar screen (add_block_out_drawer.dart)                                 |
| Financials                             | **affected**   | Date selection UI for financial entry date (add_financial_entry_bottom_sheet.dart) and gig pay date (gig_pay_bottom_sheet.dart) |
| Platform (iOS / Android / Web / macOS) | **affected**   | UI change visible on all platforms — remaining 8 date pickers switch from Material to Forui appearance/behavior                 |

---

## Regression Risk

**Level:** LOW (same as base implementation)

**Rationale:**

- **Base implementation validated:** `showAppDatePicker` already QA APPROVED with 0 analyzer errors — proven stable
- **Drop-in replacement:** Every call site follows identical pattern to base implementation (4 params, null-checked result, setState after)
- **Isolated changes:** Each file's changes limited to 1-2 methods, no cross-file dependencies
- **Mounted guards preserved:** All existing mounted checks retained exactly (some files have them, some don't — amendment preserves original behavior)
- **No state management changes:** Still local setState in each widget, no new providers/notifiers/repositories
- **No auth/session/routing impact:** Pure UI change within existing flows

**Risk factors:**

- **Multiple files (5 vs. 1):** Base implementation touched 1 file (event_editor_drawer.dart). Amendment touches 5 files. Slightly higher coordination risk, but each file change is independent.
- **Financial flows:** gig_expense_subview.dart, add_financial_entry_bottom_sheet.dart, gig_pay_bottom_sheet.dart involve money/reimbursement — dates affect accounting. However, date selection logic unchanged (only picker appearance changes), so financial correctness preserved.
- **Optional cleanup risk:** Deleting unused theme helpers (`_blockOutDatePickerTheme`, `_datePickerTheme`) could break if grep misses a reference. Mitigation: Make cleanup optional, verify via grep, run full analyzer after deletion.

**Regression testing focus:**

- Block-out dates (most complex: 4 call sites across 2 files, interdependent start/until date logic)
- Financial date pickers (money-sensitive, must not affect entry/payment date accuracy)
- Cross-file consistency (all 8 pickers should look/behave identically after migration)

---

## Engineer Task Breakdown

Execute in order. Stop and report blockers immediately.

### Task 1: Verify Base Implementation

**Action:** Confirm `showAppDatePicker` helper intact and analyzer-clean.

**Requirements:**

1. Verify `lib/components/ui/app_date_picker.dart` exists
2. Run `flutter analyze lib/components/ui/app_date_picker.dart`
3. Confirm 0 errors, 0 warnings
4. Verify function signature: `Future<DateTime?> showAppDatePicker({required BuildContext context, required DateTime initialDate, required DateTime firstDate, required DateTime lastDate})`

**Verification:** Base implementation ready

**Blocker handling:** If file missing or analyzer fails, stop and escalate to Manager — amendment depends on base implementation.

---

### Task 2: Migrate Block-Out Date Pickers (Event Editor)

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**Action:** Replace `showDatePicker` with `showAppDatePicker` in 2 block-out methods.

**Requirements:**

1. Locate `_selectBlockOutStartDate()` method (line ~2888)
2. Replace `showDatePicker(..., builder: (context, child) => _blockOutDatePickerTheme(child))` with `showAppDatePicker(...)`
3. **Do not change:** null check, setState logic, `_blockOutUntilDate` clearing, `_markDirty()` call, `HapticFeedback.selectionClick()` call
4. Locate `_selectBlockOutUntilDate()` method (line ~2909)
5. Replace `showDatePicker(..., builder: (context, child) => _blockOutDatePickerTheme(child))` with `showAppDatePicker(...)`
6. **Do not change:** null check, setState logic, `_markDirty()` call, `HapticFeedback.selectionClick()` call
7. **Do not add import:** File already imports `../../../components/ui/app_date_picker.dart` from base implementation (verify at line ~62)
8. Run `flutter analyze lib/features/events/widgets/event_editor_drawer.dart` → 0 new errors expected

**Verification:** Both methods simplified, theme override removed, result handling unchanged, analyzer clean

---

### Task 3: Migrate Block-Out Date Pickers (Calendar Screen)

**File:** `lib/features/calendar/widgets/add_block_out_drawer.dart`

**Action:** Add import and replace 2 date picker methods.

**Requirements:**

1. Add import at top of file: `import '../../../components/ui/app_date_picker.dart';`
2. Locate `_selectStartDate()` method (line ~453)
3. Replace `showDatePicker(..., builder: (context, child) => _datePickerTheme(child))` with `showAppDatePicker(...)`
4. **Do not change:** null check, setState logic, `_untilDate` clearing logic, `HapticFeedback.selectionClick()` call, inline comment "Clear until date if it's now before start date"
5. Locate `_selectUntilDate()` method (line ~474)
6. Replace `showDatePicker(..., builder: (context, child) => _datePickerTheme(child))` with `showAppDatePicker(...)`
7. **Do not change:** null check, setState logic, `HapticFeedback.selectionClick()` call
8. Run `flutter analyze lib/features/calendar/widgets/add_block_out_drawer.dart` → 0 new errors expected

**Verification:** Both methods simplified, theme override removed, result handling unchanged, analyzer clean

---

### Task 4: Migrate Expense Date Pickers

**File:** `lib/features/events/widgets/gig_expense_subview.dart`

**Action:** Add import and replace 2 date picker methods.

**Requirements:**

1. Add import at top of file: `import '../../../components/ui/app_date_picker.dart';`
2. Locate `_pickDate()` method (line ~186)
3. Replace `showDatePicker(..., builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!))` with `showAppDatePicker(...)`
4. **Do not change:** mounted guard (`if (!mounted || picked == null) return;`), setState logic
5. Locate `_pickReimbursedDate()` method (line ~199)
6. Replace `showDatePicker(..., builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!))` with `showAppDatePicker(...)`
7. **Do not change:** `initialDate` computation (`_reimbursedDate ?? DateTime.now()`), mounted guard, setState logic
8. Run `flutter analyze lib/features/events/widgets/gig_expense_subview.dart` → 0 new errors expected

**Verification:** Both methods simplified, theme override removed, mounted guards preserved, analyzer clean

---

### Task 5: Migrate Financial Entry Date Picker

**File:** `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`

**Action:** Add import and replace date picker method.

**Requirements:**

1. Add import at top of file: `import '../../../components/ui/app_date_picker.dart';`
2. Locate `_pickDate()` method (line ~349)
3. Replace `showDatePicker(..., builder: (ctx, child) => Theme(data: Theme.of(ctx), child: child!))` with `showAppDatePicker(...)`
4. **Do not change:** mounted guard (`if (!mounted || picked == null) return;`), setState logic
5. Run `flutter analyze lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` → 0 new errors expected

**Verification:** Method simplified, theme override removed, mounted guard preserved, analyzer clean

---

### Task 6: Migrate Gig Pay Date Picker

**File:** `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`

**Action:** Add import and replace date picker method.

**Requirements:**

1. Add import at top of file: `import '../../../components/ui/app_date_picker.dart';`
2. Locate `_pickDate()` method (line ~106)
3. Replace `showDatePicker(..., builder: (context, child) => Theme(data: Theme.of(context), child: child!))` with `showAppDatePicker(...)`
4. **Do not change:** mounted guard (`if (!mounted) return;`), null check (`if (picked != null)`), setState logic
5. Note: This file has different guard order (mounted check before null check vs. combined check in Task 4-5) — preserve original order exactly
6. Run `flutter analyze lib/features/financials/widgets/gig_pay_bottom_sheet.dart` → 0 new errors expected

**Verification:** Method simplified, theme override removed, mounted guard order preserved, analyzer clean

---

### Task 7: Optional Cleanup (Theme Helpers)

**Action:** Remove unused theme helper methods if safe.

**Requirements:**

1. **event_editor_drawer.dart:**
   - Run `grep -n "_blockOutDatePickerTheme" lib/features/events/widgets/event_editor_drawer.dart`
   - Count references: method definition (line ~2921) + any calls
   - If only 1 reference (method definition), delete lines ~2921-2931
   - If 2+ references, **do not delete** — method still in use
2. **add_block_out_drawer.dart:**
   - Run `grep -n "_datePickerTheme" lib/features/calendar/widgets/add_block_out_drawer.dart`
   - Count references: method definition (line ~495) + any calls
   - If only 1 reference (method definition), delete lines ~495-504
   - If 2+ references, **do not delete** — method still in use
3. Run `flutter analyze` on both files after deletion (if deleted)
4. Confirm 0 new errors

**Verification:** Dead code removed (if safe), analyzer clean

**Blocker handling:** If grep finds additional references, skip deletion and note in ENGINEER_REPORT.md — do not delete methods that are still called.

---

### Task 8: Final Verification

**Action:** Run full analyzer on all modified files.

**Requirements:**

1. Run `flutter analyze` on all 5 modified files:
   ```bash
   flutter analyze \
     lib/features/events/widgets/event_editor_drawer.dart \
     lib/features/calendar/widgets/add_block_out_drawer.dart \
     lib/features/events/widgets/gig_expense_subview.dart \
     lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart \
     lib/features/financials/widgets/gig_pay_bottom_sheet.dart
   ```
2. Confirm 0 new errors, 0 new warnings (pre-existing warnings in unrelated files acceptable)
3. Verify no unused imports (analyzer flags `unused_import` if app_date_picker.dart not used)
4. Verify Material import still present in each file (other widgets still use Material components)
5. Run `flutter analyze` on full codebase (no args) — confirm no NEW errors introduced

**Verification:** All modified files analyzer-clean, no new codebase-wide errors

---

## Verification Plan

### Tier 1 — Pre-deployment (not applicable)

N/A — no database changes, no migrations, no backend deployment required.

---

### Tier 2 — Post-deployment (Manual QA Only)

**Context:** This amendment adds 8 date picker migrations to the 3 already QA APPROVED in base implementation. All verification is manual interaction testing.

#### Test 1: Block-Out Date Pickers (Event Editor)

**Steps:**

1. Open event editor drawer
2. Switch to "Block Out" tab (if multi-tab, or create block-out event if single event type)
3. Tap block-out start date field
4. **Verify:** Forui date picker dialog appears (not Material picker)
5. **Verify:** Dialog shows current month/year header with dropdown navigation (same as base implementation)
6. **Verify:** Grid layout (7 columns, weeks as rows)
7. Select a date 2 weeks from today
8. **Verify:** Dialog dismisses, selected date appears in field
9. Tap block-out until date field
10. **Verify:** Forui date picker dialog appears
11. **Verify:** Cannot select dates before start date (firstDate constraint enforced)
12. Select a date 1 month from start date
13. **Verify:** Dialog dismisses, until-date appears in field
14. Save block-out
15. **Verify:** Block-out created with correct date range

**Expected:** Block-out date pickers in event editor use Forui dialog, start/until date relationship preserved

---

#### Test 2: Block-Out Date Pickers (Calendar Screen)

**Steps:**

1. Navigate to Calendar screen
2. Trigger "Add Block Out" drawer (button or gesture)
3. Tap start date field
4. **Verify:** Forui date picker dialog appears (not Material picker)
5. Select a date 1 week from today
6. **Verify:** Dialog dismisses, start date appears
7. Tap until date field
8. **Verify:** Forui date picker dialog appears
9. **Verify:** Cannot select dates before start date (firstDate constraint enforced)
10. Select a date 2 weeks from start date
11. **Verify:** Dialog dismisses, until-date appears
12. Save block-out
13. **Verify:** Block-out created with correct date range
14. **Verify:** Block-out appears on calendar grid

**Expected:** Block-out date pickers in calendar drawer use Forui dialog, identical behavior to event editor block-outs

---

#### Test 3: Expense Date Pickers

**Steps:**

1. Create or open a gig
2. Navigate to Expenses subview
3. Tap "+ Add Expense" button
4. Enter expense amount and category
5. Tap entry date field
6. **Verify:** Forui date picker dialog appears (not Material picker)
7. **Verify:** Wide date range selectable (2000-2100 per code)
8. Select a date 3 days ago
9. **Verify:** Dialog dismisses, entry date appears
10. Toggle "Reimbursed" on
11. Tap reimbursed date field
12. **Verify:** Forui date picker dialog appears
13. Select today's date
14. **Verify:** Dialog dismisses, reimbursed date appears
15. Save expense
16. **Verify:** Expense created with correct entry and reimbursed dates

**Expected:** Expense date pickers use Forui dialog, wide date range preserved, both entry and reimbursed dates work

---

#### Test 4: Financial Entry Date Picker

**Steps:**

1. Navigate to Financials screen (or band settings → Financials)
2. Tap "+ Add Entry" button (or trigger add_financial_entry_bottom_sheet.dart)
3. Enter amount and select type (income or expense)
4. Tap entry date field
5. **Verify:** Forui date picker dialog appears (not Material picker)
6. **Verify:** Wide date range selectable (2000-2100 per code)
7. Select a date 1 week ago
8. **Verify:** Dialog dismisses, entry date appears
9. Save financial entry
10. **Verify:** Entry created with correct date

**Expected:** Financial entry date picker uses Forui dialog, wide date range preserved

---

#### Test 5: Gig Pay Date Picker

**Steps:**

1. Navigate to a gig with payment tracking (or trigger gig_pay_bottom_sheet.dart)
2. Tap "Record Payment" button (or equivalent trigger)
3. Enter payment amount and select payer
4. Tap payment date field
5. **Verify:** Forui date picker dialog appears (not Material picker)
6. **Verify:** Wide date range selectable (2000-2100 per code)
7. Select a date 5 days ago
8. **Verify:** Dialog dismisses, payment date appears
9. Save payment
10. **Verify:** Payment record created with correct date

**Expected:** Gig pay date picker uses Forui dialog, wide date range preserved

---

#### Test 6: Date Picker Cancel Behavior (All New Pickers)

**Steps:**

1. Open any of the 8 newly migrated date pickers (block-out, expense, financial, gig pay)
2. Tap outside dialog (barrier dismiss)
3. **Verify:** Dialog dismisses, date unchanged (not null)
4. Reopen same date picker
5. **Verify:** Dialog reopens with previous initialDate
6. Press Escape key (desktop) or tap barrier (mobile)
7. **Verify:** Dialog dismisses, date unchanged

**Expected:** Cancel/dismiss preserves existing date value across all 8 new pickers

---

#### Test 7: Consistency Check (Base vs. Amendment)

**Steps:**

1. Open event editor (base implementation scope)
2. Tap primary event date field → **Verify:** Forui picker
3. Switch to block-out tab → Tap block-out start date → **Verify:** Forui picker (amendment scope)
4. Close event editor
5. Open calendar screen → Trigger add block-out drawer → Tap start date → **Verify:** Forui picker (amendment scope)
6. Open gig → Navigate to expenses → Tap entry date → **Verify:** Forui picker (amendment scope)
7. **Compare:** All 4 pickers (event primary, event block-out, calendar block-out, expense) should look identical (same grid layout, same header, same colors, same month/year navigation)

**Expected:** All date pickers (base + amendment) use identical Forui appearance — no visual inconsistency

---

#### Test 8: Cross-Platform Smoke Test

**Platforms:** Web (Chrome), iOS (simulator), macOS (desktop)

**Steps:**

1. For each platform:
   - Open 1 date picker from base implementation (event primary date)
   - Open 1 date picker from amendment (block-out start date)
   - **Verify:** Both use Forui dialog
   - **Verify:** Dialog renders correctly (no layout overflow, grid visible, header readable)
   - Select a date in each picker
   - **Verify:** Both dismiss correctly, selected date appears
2. **Cross-platform consistency:** Forui picker appearance should be consistent across Web/iOS/macOS (minor platform-specific styling acceptable, but layout/structure identical)

**Expected:** Amendment date pickers work identically to base implementation across all platforms

---

## QA Re-Review Requirements

**Context:** QA_REPORT.md currently shows **APPROVED** verdict for base implementation (3 date pickers in event_editor_drawer.dart). That approval explicitly verified that the 8 call sites in this amendment remained Material (Files Off-Limits boundary check, Test 5 in original QA_REPORT.md).

**Superseded Verdict:** The APPROVED verdict in QA_REPORT.md is now superseded by this amendment. QA must re-review the combined diff (base + amendment) as a single feature.

**QA Agent Instructions:**

1. **Do not treat amendment as separate feature** — validate as extension of original feature
2. **Review full git diff** — base implementation (3 pickers) + amendment (8 pickers) = 11 total picker migrations
3. **Re-run analyzer** on all modified files (6 files: app_date_picker.dart + 5 files in amendment)
4. **Verify Files Off-Limits boundary** — original boundary excluded these 8 pickers, amendment brings them into scope, so original boundary check (Test 5) is no longer applicable
5. **Code-path analysis** — confirm all 8 amendment call sites use `showAppDatePicker` correctly (same pattern as base implementation)
6. **Mounted guard preservation** — verify each file's original mounted guard behavior preserved (some have guards, some don't — amendment must not add/remove guards)
7. **Optional cleanup verification** — if Engineer deleted unused theme helpers, verify via grep that no other references existed
8. **Final verdict** — APPROVED or REQUIRES CHANGES (applies to full feature: base + amendment combined)

**QA Verdict Location:** Append to existing `QA_REPORT.md` with section header `## Amendment 1 Re-Review` — do not create new QA_REPORT file.

---

## Known Limitations

1. **No runtime testing in pipeline:** Per ARCHITECT_PLAN.md Verification Plan Tier 2, all validation is manual QA — no automated tests exist for date picker flows. Amendment follows same pattern (code-path analysis + manual QA only).

2. **Pre-existing GUARDRAILS.md §5 violation:** Several methods call `setState` after `await` without `mounted` guard (e.g., `_selectBlockOutStartDate()`, `_selectBlockOutUntilDate()` in event_editor_drawer.dart). This is NOT a regression — violation existed before base implementation and is explicitly preserved per base ARCHITECT_PLAN.md Task 2-3. Amendment preserves this behavior exactly (does not add/remove mounted guards). Recommend fixing in follow-up feature.

3. **Large file sizes:** event_editor_drawer.dart (3,153 lines) and add_block_out_drawer.dart (~900 lines) exceed GUARDRAILS.md §8 targets (400 lines for feature widgets). Amendment makes minimal localized changes (2 methods per file) — does not worsen maintainability.

4. **Optional cleanup risk:** Deleting unused theme helper methods (`_blockOutDatePickerTheme`, `_datePickerTheme`) depends on grep accuracy. If grep misses a dynamic reference (e.g., string-based method call, reflection), deletion could break at runtime. Mitigation: Task 7 is optional, Engineer can skip if uncertain, full analyzer runs after deletion.

---

**Amendment Approved For Implementation:** 2026-08-17  
**Architect:** GitHub Copilot (Claude Sonnet 4.5)
