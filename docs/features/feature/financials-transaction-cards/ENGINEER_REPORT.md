# ENGINEER_REPORT — feature/financials-transaction-cards

## Feature Slug
`feature/financials-transaction-cards`

## Feature Title
Financials screen — replace transaction table with cards, add summary header

## Cycle Number
10

## Goal
Two independent, narrow fixes, no new Architect plan needed for either:
1. Revert the Cycle 9 out-of-scope change to
   `add_financial_entry_bottom_sheet.dart`'s `_onDisbursementChanged` that
   QA flagged Critical — restore the early-return guard to run *before*
   `setState` instead of inside it.
2. Tony's new request: `financial_entry_details_bottom_sheet.dart`'s
   `_DetailRow` value `Text` must not wrap — add `maxLines: 1`,
   `overflow: TextOverflow.ellipsis`, `softWrap: false`.

**Cycle 10 continuation (Manager-authorized Option B):** the literal revert
in fix 1 above exposed a genuine regression — with the guard restored
before `setState`, the Save button never re-enables on Amount changes when
`_depositToSavings`/`_disburse` are both off, because
`_onDisbursementChanged` was the sole listener driving the outer rebuild.
Manager authorized Option B from this report's original Deviations
section: keep `_onDisbursementChanged` exactly as reverted (no added
responsibility), and add a second, separate, single-purpose listener
dedicated to the Save button's enabled-state recompute.

## Architect Tasks Completed
Both fixes applied exactly as specified:
1. `_onDisbursementChanged` reverted to:
   ```dart
   void _onDisbursementChanged() {
     if (!_depositToSavings || !_disburse) return;
     setState(() {
       final totalDisbursed =
           _splitControllers.values.fold<int>(0, (sum, c) => sum + c.cents);
       final remaining = _amountController.cents - totalDisbursed;
       _depositToSavingsController.cents = remaining > 0 ? remaining : 0;
     });
   }
   ```
   The guard now gates the function before any `setState` call, matching
   the pre-Cycle-8 shape exactly (byte-for-byte, confirmed by reading).
2. `_DetailRow`'s value `Text` now reads:
   ```dart
   Text(
     value,
     style: AppTextStyles.callout
         .copyWith(color: context.colors.textPrimary),
     maxLines: 1,
     overflow: TextOverflow.ellipsis,
     softWrap: false,
   ),
   ```
   Nothing else in the file (label styling, spacing, `_TypeBadge`, etc.)
   was touched.
3. **Option B addendum:** added a second, dedicated listener,
   `_onAmountChanged`, separate from `_onDisbursementChanged`:
   ```dart
   void _onAmountChanged() => setState(() {});
   ```
   Registered on `_amountController` in `initState` immediately after the
   existing `_amountController.addListener(_onDisbursementChanged);` line,
   and removed in `dispose` immediately after the existing
   `_amountController.removeListener(_onDisbursementChanged);` line.
   `_onDisbursementChanged` itself was not touched again — it stays
   exactly the QA-approved revert shape (guard before `setState`, only the
   disbursement-sync assignment inside). The two listeners are
   independent and single-purpose: `_onDisbursementChanged` keeps the
   savings-remainder field in sync when disbursing; `_onAmountChanged`'s
   only job is to force the outer `State` to rebuild on every Amount
   change so the Save button's `enabled` flag (computed at `build()` time
   from `_amountController.cents`) gets re-evaluated, regardless of the
   `_depositToSavings`/`_disburse` state.

## Files Created
None.

## Files Modified
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
  — `_onDisbursementChanged` guard-order revert, plus (this continuation)
  the new `_onAmountChanged` listener and its `initState`/`dispose`
  registration.
- `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`
  — single-property addition (`maxLines`/`overflow`/`softWrap`) to
  `_DetailRow`'s value `Text`. Not touched again this continuation.

## Analyzer Results
```
flutter analyze lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart
Analyzing add_financial_entry_bottom_sheet.dart...
No issues found! (ran in 4.6s)
```
0 issues at any severity on the changed file (Option B addendum). The
`financial_entry_details_bottom_sheet.dart` analyzer result from the
original Cycle 10 pass above is unchanged — that file was not touched
again this continuation.

## Test Results
`flutter test test/features/financials/widgets/` (full directory), after
adding the `_onAmountChanged` listener:
```
00:18 +49: All tests passed!
```
**49 passed, 0 failed** (49 total). The previously-failing
`add_financial_entry_bottom_sheet_test.dart: notes field passes through to
onSave.notes` now passes — the outer `State` rebuilds on every Amount
change via `_onAmountChanged`, so `enabled` (and thus the Save button's
`onPrimary`) is re-evaluated and the test's tap on Save actually invokes
`onSave`. No other test regressed.

## Code Efficiency/Bloat Check
No new helpers, extensions, providers, or widgets introduced. All diffs
remain single-purpose, minimal edits (guard-order swap; three-property
addition to one existing `Text`; one one-line listener method plus its
two registration/removal call sites). No file size targets affected.
`_onAmountChanged` is a genuine second responsibility (Save-button
recompute) distinct from `_onDisbursementChanged`'s (savings-remainder
sync) — kept separate per Manager's explicit instruction rather than
merged, so this is not a case of two near-duplicate listeners that should
have been one.

## Verification (manual steps performed)
- Read `_onDisbursementChanged` before and after: confirmed the reverted
  version is byte-for-byte the guard-before-`setState` shape the request
  specified, and that the sync logic inside (`totalDisbursed`/`remaining`/
  `_depositToSavingsController.cents` assignment) is unchanged.
- Read `_DetailRow` before and after: confirmed only the target `Text`
  widget changed; label `Text`, `SizedBox` width, `Column`/`Row` structure,
  and `_TypeBadge` are untouched.
- Root-caused the one test failure by reading `_buildFixedBottomActions()`:
  the Save button's `onPrimary` is `enabled ? _save : null` where
  `enabled = _amountController.cents > 0`, computed at the outer `State`'s
  `build()` time. `_onDisbursementChanged` is the *only* listener registered
  on `_amountController`. With the guard before `setState`, no rebuild fires
  on an Amount-field change when `_depositToSavings`/`_disburse` are both
  false (the common case, and the case the new test exercises) — so
  `enabled` never gets recomputed, `onPrimary` stays `null` from the
  initial build, and tapping "Save" is a no-op. That's why
  `capturedNotes` comes back `null` in the failing test: `onSave` is never
  invoked. Confirmed this reproduces by temporarily swapping the buggy
  version back in (test passes) and swapping the literal-revert version
  back in (test fails), isolating the cause to this one method.

## Deviations From Plan
Both original fixes were applied exactly as specified, character-for-
character. Applying fix 1 exactly as specified reintroduced a real
functional regression (the Save button never re-enabling on Amount changes
in the common non-disburse case) — documented in full in this report's
first pass, with three options (A/B/C) laid out for Manager/Architect/Tony
to decide between rather than picked unilaterally.

**Resolution:** Manager authorized Option B. Implemented as a second,
separate, single-purpose `_onAmountChanged` listener (see Architect Tasks
Completed item 3 above) rather than folding the fix into
`_onDisbursementChanged`, per Manager's explicit instruction to keep that
method exactly the QA-approved revert shape with no added responsibility.
This is authorized new scope beyond the original plan's two fixes, not a
self-directed deviation.

## Blockers Encountered
None remaining. The Save-button-never-enables regression flagged in this
report's first pass is resolved by the Option B addendum; full suite is
green.

## Ready For QA
Ready For QA: Yes

