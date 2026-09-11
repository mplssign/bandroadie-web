## Summary

Redesigns the Financials screen's transaction list from an 8-column, horizontally-scrollable table into a vertically-scrolling list of transaction cards, with a new summary header (total, date range, transaction count, and two inline action links replacing the old bottom-pinned buttons). Also updates the transaction detail bottom sheet with clearer labels and two new rows.

No schema, RLS, or backend changes.

## What changed

- **Summary header** (new): shows `TOTAL EXPENSES`/`TOTAL INCOME` + total for the current view + date range, transaction count, and two inline chevron links — "View Savings Balance" (opens existing savings sheet) and "Generate Report" (opens existing PDF report screen). Replaces the old bottom-pinned outlined buttons.
- **Transaction list**: replaced the table with cards (title, category subtitle, date, right-aligned amount, chevron). Green outlined badge shows "Disbursed" on income entries with disbursements, or "Reimbursed" on reimbursed expenses — never the opposite type.
- **Sort control**: "Newest first ▾" / "Oldest first ▾" toggle in the list header — tapping it re-sorts the visible list; purely presentational, does not affect the generated report.
- **Date filter chips** (All Time / This Year / This Month / Custom): unchanged.
- **Detail bottom sheet**: removed per-row icons; renamed "Payer" → "Paid by", "Description" → "Notes", footer button "Edit Entry" → "Edit"; added an explicit "Reimbursed: Yes/No" row for expenses; added a new "Related to gig" row (plain text, not tappable).

## Known, pre-existing, out-of-scope gap

The general Add/Edit entry form has no toggle for "Reimbursed" — only the gig-expense-specific flow sets it. This redesign makes that status more visible, so a manually-entered expense may show "Reimbursed: No" with no way to change it via Edit. Not a regression introduced by this PR; flagged for a future pass.

## Verification

- `flutter analyze` clean on all changed/created files.
- New widget tests added (`test/features/financials/widgets/`) — 34 passed, 0 failed.
- Independent QA review: **APPROVED**, low regression risk, no auth/routing/RLS/schema touched.
- Manual verification punch list included in `QA_REPORT.md` for owner testing before merge.

## Not included in this PR

- No database migration.
- No new app build/deploy.
