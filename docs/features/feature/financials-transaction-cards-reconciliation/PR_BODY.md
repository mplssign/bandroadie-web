## Summary

Reconciles two independently-built features that both heavily modified the Financials screen:

- **#273** (`feature/financials-transaction-cards`, not merged) — redesigned the Financials list screen: transaction cards, summary header with total/count, a tri-state date-filter dropdown (All time / This year / This month), and a sort toggle.
- **#274** (`feature/transaction-drawer-redesign`, already merged) — redesigned the Add/Edit Transaction form into labeled sections with contact/venue suggestions and auto-balancing, built independently without awareness of #273.

Both branches modified the same files. This PR keeps #273's list-screen redesign, keeps #274's Add/Edit form as-is (untouched), and rebuilds the read-only transaction detail sheet to combine both: #273's UX polish (no icons, side-by-side labels/values, non-wrapping labels, reordered rows, `Done`+`Edit` footer) plus correct display of the fields #274 introduced (reimbursement method, notes, gig link).

## What changed

- `financials_screen.dart`: cards/summary-header/date-filter/sort redesign restored on top of the current (post-#274) codebase, preserving #274's save-callback shape.
- `financial_entry_details_bottom_sheet.dart`: rebuilt with the reconciled row order (Date, Description, Paid to, Purchased by, Needed for gig, Notes, then conditional Reimbursed/Reimbursement/Deposit-to-Savings rows) and a `Done` + `Edit` footer. The Edit-launch handler now correctly forwards all fields (including reimbursement method) when re-saving.
- `financials_controller.dart` / `financials_pdf_preview_screen.dart`: tri-state date filter (All time / This year / This month).
- `add_financial_entry_bottom_sheet.dart`, the repository, the model, and all database migrations: **untouched** — #274's version is authoritative.

## Known, accepted gap

The date-filter dropdown no longer renders at the extra-compact size it briefly had in an earlier #273 cycle — that required a small addition to the shared dropdown component that isn't present in #274's baseline. Cosmetic only; easy follow-up if wanted.

## Verification

- `flutter analyze`: 0 issues across all 8 changed/created files.
- `flutter test`: 46/46 passing.
- Independent QA review: **APPROVED**. Confirmed byte-identical (zero diff) on all off-limits files: the Add/Edit form, repository, model, and every migration file.

## Not included in this PR

- No new database migration (the schema changes needed were already shipped in #274).
- No new app build/deploy.

## Related

- Supersedes #273 (recommend closing that PR once this merges; its branch is left intact for reference, not deleted).
- Builds on #274 (already merged).
