# Engineer Report

## Feature Slug

feature/gig-expenses

## Feature Title

Gig Expenses in Event Editor Drawer (Phase 1)

## Goal

Add gig-linked expense management directly in the gig create/edit drawer with an in-drawer expense sub-view and repository support for fetch/insert/update, while preserving existing gig pay behavior and current permission model.

## Architect Tasks Completed

- [x] Task 1: Extended FinancialEntryRepository with expense-specific gig methods: fetchGigExpenseEntries, insertGigExpenseEntry, updateGigExpenseEntry.
- [x] Task 2: Created in-drawer expense editor widget at lib/features/events/widgets/gig_expense_subview.dart with AppIcons.back row, amount/category/date/paid-by fields, and Save/Delete callbacks.
- [x] Task 3: Updated GigFormFields with Expenses section under Gig Pay, Add action, list rows (amount/category/date), and tap-to-edit callback wiring.
- [x] Task 4: Updated EventEditorDrawer with expense list state, current expense edit state, two-view toggle, edit-mode load/persist behavior, create-mode deferred behavior, and post-create expense flush.
- [x] Task 5: Wired permission gates using currentUserPermissionsProvider for financial visibility (canViewFinancials) and mutation (canCreateFinancials/canDeleteFinancials).
- [x] Task 6: Invalidated financialsProvider after expense insert/update/delete/flush while leaving existing event cache invalidation behavior unchanged.
- [x] Task 7: Ran Tier 1 verification commands and recorded outputs in this report.

### Addendum Architect Tasks Completed (Expense Reimbursement Tracking)

- [x] Task 1: Created migration file `supabase/migrations/20260803120000_add_reimbursement_fields_to_financial_entries.sql` with the exact Architect SQL (columns + consistency check constraint).
- [x] Task 2: Updated `FinancialEntry` model parsing/serialization for `is_reimbursed` and `reimbursed_date`.
- [x] Task 3: Extended `GigExpenseDraft` and `GigExpenseSubView` with reimbursement state, `Mark as Reimbursed` toggle, and conditional reimbursement date picker defaulting to today.
- [x] Task 4: Threaded reimbursement fields through `EventEditorDrawer` draft hydration, save/update calls, and deferred flush flow.
- [x] Task 5: Extended `FinancialEntryRepository.insertGigExpenseEntry` and `updateGigExpenseEntry` to persist `is_reimbursed` and clear `reimbursed_date` when reimbursement is off.
- [x] Task 6: Updated gig drawer Expenses list rendering in `GigFormFields` to show `Reimbursed` badge and a computed detail line from structured fields.
- [x] Task 7: Updated Financials details bottom sheet to show the same `Reimbursed` badge and computed reimbursement detail line for reimbursed expense entries.
- [x] Task 8: Verified scope guard held: no reimbursement controls were added to generic `add_financial_entry_bottom_sheet.dart`.
- [x] Task 9: Ran `flutter analyze` (0 issues). Manual UI checks are still required in app runtime for create-mode deferred flow, edit-mode flow, and badge/detail rendering verification.

## Files Created

- lib/features/events/widgets/gig_expense_subview.dart
- docs/features/gig-expenses/ENGINEER_REPORT.md
- supabase/migrations/20260803120000_add_reimbursement_fields_to_financial_entries.sql

## Files Modified

- lib/features/financials/financial_entry_repository.dart
- lib/features/events/widgets/event_editor_drawer.dart
- lib/features/events/widgets/gig_form_fields.dart
- lib/features/financials/models/financial_entry.dart
- lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart

## Analyzer Results

Command: flutter analyze
Result: 0 errors, 0 issues (No issues found)

Addendum re-run (after reimbursement implementation):

Command: flutter analyze
Result: 0 errors, 0 issues (No issues found)

## Test Results

Not run (Architect Tier 1 requires static checks and grep verification; no automated test command specified).

## Verification

Manual commands performed:

- PRE-DEPLOY TEST 1:
  - grep -n "CREATE UNIQUE INDEX IF NOT EXISTS uniq_gig_pay_entry" supabase/migrations/20260601000000_create_financial_entries.sql
  - grep -n "WHERE entry_type = 'gig_pay'" supabase/migrations/20260601000000_create_financial_entries.sql
  - grep -n "gig_id\s*UUID\s*REFERENCES public.gigs(id) ON DELETE SET NULL" supabase/migrations/20260601000000_create_financial_entries.sql
  - Confirmed unique index is gig_pay-scoped and gig_id FK uses ON DELETE SET NULL.
- PRE-DEPLOY TEST 2:
  - grep -n "fetchGigExpenseEntries\|insertGigExpenseEntry\|updateGigExpenseEntry" lib/features/financials/financial_entry_repository.dart
  - grep -n "buildExpensesSection\|onAddExpense\|onExpenseTap" lib/features/events/widgets/gig_form_fields.dart
  - grep -n "AppIcons.back\|\_isEditingExpense\|\_pendingGigExpenses\|createGig\|financialsProvider" lib/features/events/widgets/event_editor_drawer.dart
  - Confirmed repository methods, expenses section wiring, two-view toggle markers, deferred expense state, createGig integration, and financials invalidation markers are present.
- PRE-DEPLOY TEST 3:
  - flutter analyze
  - Result: No issues found.

## Git Diff Stat

Command: git diff --stat
Output:

- lib/features/events/widgets/event_editor_drawer.dart | 453 ++++++++++++++++-----
- lib/features/events/widgets/gig_form_fields.dart | 142 +++++++
- lib/features/financials/financial_entry_repository.dart | 89 ++++
- 3 files changed, 589 insertions(+), 95 deletions(-)

Note: New untracked file lib/features/events/widgets/gig_expense_subview.dart is present in git status and not included in git diff --stat until tracked.

## Deviations From Architect Plan

Manager review corrections were applied after initial implementation:

- Updated preset expense categories in [lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart) to the confirmed production list.
- Updated the expense sub-view default date in [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart) from gig date (\_selectedDate) to today's date (DateTime.now()).

Post-review UI fixes (found via manual testing):

- Removed duplicate Amount label in [lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart) so CurrencyTextField's internal label is the only Amount label.
- Moved expense sub-view back navigation into the main drawer header in [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart), and removed the duplicate in-subview title/back row.

Additional post-review updates:

- QA feedback (RBAC): Split expense delete UI gating from edit gating by introducing a dedicated delete permission path (canDeleteFinancials) passed as canDelete to [lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart).
- Tony mid-session request: Added optional Notes field to Add/Edit Expense flow, mapped to financial_entries.description through [lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart), [lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart), and [lib/features/financials/financial_entry_repository.dart](lib/features/financials/financial_entry_repository.dart).
- Tony explicit naming request: Renamed the sub-view label from "Notes (optional)" to "Description (optional)" intentionally to align with `financial_entries.description` and match the existing expense detail label in the Financials table view; this was a deliberate product wording choice, not a defect.

## Blockers Encountered

None.

## Ready For QA

Yes.
