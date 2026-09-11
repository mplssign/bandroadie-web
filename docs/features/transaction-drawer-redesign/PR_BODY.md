## Summary

Redesigns the Add/Edit Transaction drawer (Financials) to match the structure of the existing Add/Edit Event drawer — bordered sections with headings instead of one long flat form.

- **Header**: "Add Transaction" / "Edit Transaction" with a subtitle in create mode; Income/Expense segmented selector below.
- **About**: type, amount, date, short description (income placeholder: "Where did the money come from?").
- **Payment Details**: "Payment from" (income) / "Paid to" (expense) with autocomplete against existing contacts and venues, plus free-text entry; "Paid by" (expense); "Related to Gig".
- **Distribution** (income only): 1099, Disburse to Band with member splits, Deposit to Savings.
  - Turning Deposit to Savings ON with Disburse off now auto-fills the full transaction amount.
  - Reducing a member's split now moves the shortfall into Savings and auto-enables Deposit to Savings.
  - Splits + savings can never exceed the transaction amount — an over-allocated field now shows an inline error ("Exceeds remaining balance") and disables Save until corrected.
- **Reimbursement** (expense only): "Reimbursed by Band" toggle reveals a date picker and a Method dropdown (Zelle/Venmo/Cash/Check/Other, with free text for Other).
- **Notes**: its own section; keyboard now dismisses properly (bounded field + done action).
- Sticky footer: Cancel + Add Transaction/Save, with Delete as a separate destructive action in edit mode.

## Database

One additive migration: `financial_entries` gains two nullable columns (`reimbursement_method`, `notes`) and a tightened check constraint (satisfied by all existing rows). No RLS/RPC changes.

## Verification

- `flutter analyze` clean on all touched files.
- New widget test suite (16 tests) covering the sectioned layout, header/footer copy, reimbursement toggle, and the distribution auto-fill/validation logic — all passing.
- Full `flutter test` suite run with no new failures (2 pre-existing, unrelated failures in `login_screen_demo_button_test.dart`, confirmed zero diff in that area vs. `main`).
- QA reviewed the full diff against the plan (32 tasks across the base implementation and a follow-up addendum) — **APPROVED**, no Critical/Warning findings.

## Known/accepted items from QA

- The migration was verified by static SQL review only; a live-apply attempt against an ephemeral Supabase preview branch hit a Postgres credential issue unrelated to the migration's own correctness. The migration is purely additive (two nullable columns) and the tightened constraint is provably satisfied by every existing row from the SQL text alone.
- A minor, harmless UI-state reset (`_isReimbursed` clearing when switching to income mode) was found during review — it has no effect on saved data.

## Manual test plan (for reviewer)

See the Manual Verification Punch List in `docs/features/transaction-drawer-redesign/QA_REPORT.md` for the full numbered walkthrough (12 steps from the base redesign + 11 steps from the distribution addendum).

## Deployment

This PR does not apply any database migration and does not ship a new app build — both remain manual follow-up steps outside this PR.
