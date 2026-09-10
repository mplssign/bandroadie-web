## Summary

On the Financials Add/Edit Transaction sheet (both Income and Expense), tapping
into the Notes field opened the on-screen keyboard, which completely covered
the field and the Save/Cancel/Delete footer. The sheet's outer container never
accounted for the keyboard's height (`MediaQuery.viewInsets.bottom`), unlike
every other multi-field bottom sheet in the codebase.

## Changes

- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`:
  added `margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)`
  to the outer `Container`, mirroring the pattern already used by other
  keyboard-avoiding bottom sheets in this codebase. When the keyboard is
  closed the margin is zero (no visual change); when it opens, the sheet
  shifts up so the Notes field and footer stay visible.
- `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`:
  added one regression test asserting the container's margin tracks
  `viewInsets.bottom`.

## Verification

- `flutter analyze` on both changed files: clean.
- Focused test file: 17/17 pass (16 existing + 1 new).
- Full `flutter test` suite: 275 pass. One pre-existing, unrelated failure
  seen locally on the pre-rebase base has since been confirmed fixed on
  `main` (PR #276) and is unrelated to this change.
- QA independently re-ran all of the above and approved.

## Risk

LOW — single-widget, single-line layout fix. No effect on macOS/web (hardware
keyboards report `viewInsets.bottom == 0`, so the margin evaluates to zero
there, identical to today's behavior).

## Manual verification (Tony, on-device)

1. Open the Finance screen and tap "Add" to create a new Income entry.
2. Tap into the Notes field on iOS or Android (real device or simulator/emulator).
3. Confirm the keyboard opens and the Notes field remains fully visible above it.
4. Repeat for an Expense entry.
5. Repeat for editing an existing Income/Expense entry's Notes field.
