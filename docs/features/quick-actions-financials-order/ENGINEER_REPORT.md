# ENGINEER_REPORT — Reorder Financials in Quick Actions

## Feature Slug

`quick-actions-financials-order`

## Feature Title

Reorder Financials in Quick Actions

## Cycle Number

1

## Goal

Render `Financials` immediately after `+ Add Event` and before
`+ Create Setlist` in the Home tab Quick Actions row.

## Architect Tasks Completed

- Moved the existing `showFinancials` block ahead of the
  `showCreateSetlist` block without changing either block's spacer guard.
- Added one widget test that asserts all three `OutlinedButton` labels in tree
  order.
- Left every `QuickActionsRow` consumer unchanged.

## Files Created

- `test/features/home/widgets/quick_actions_row_test.dart`
- `docs/features/quick-actions-financials-order/ENGINEER_REPORT.md`

## Files Modified

- `lib/features/home/widgets/quick_actions_row.dart`

## Analyzer Results

- `flutter analyze`: passed with no issues after the implementation.
- Final post-format `flutter analyze`: passed with no issues.

## Test Results

- Focused widget test: 1 passed, 0 failed.
- Full Flutter test suite: 322 passed, 0 failed.
- Final post-format focused widget test: 1 passed, 0 failed.

## Code Efficiency/Bloat Check

- Production code is a pure block reorder with no net line increase.
- The new test has one behavior assertion and introduces no helper, extension,
  utility, private widget, provider, or abstraction.
- No helper-equivalence search was required because no helper-like construct
  was added.
- No file exceeds its applicable size target.
- `dart fix --dry-run` reported nothing to fix.

## Verification (manual steps performed)

No manual app verification was performed. The architect plan assigns the
platform launch punch list to Tony at PR-test/release time.

## Deviations From Plan

None. The test has a file-scoped `avoid_redundant_argument_values` suppression
so the plan-mandated explicit `true` visibility inputs remain present while
analysis stays clean.

## Blockers Encountered

None.

## Ready For QA

Yes.