# ARCHITECT_PLAN.md

## 1. Feature Slug

feature/gig-expenses

## 2. Problem Summary

The gig editor currently supports one gig-linked income record (Gig Pay) but has no equivalent UI or repository path for gig-linked expenses. Bands need to add and manage multiple expenses per gig (rental, travel, sound company, etc.) directly inside the existing gig create/edit drawer.

Phase 1 scope is limited to adding an Expenses section and an in-drawer expense sub-view that syncs each expense row to financial_entries. Phase 2 layout restructuring (Income/Location/Important Times + sound check) and Phase 3 venue contacts on gig screen are explicitly out of scope.

## 3. Root Cause

Primary root cause: HIGH confidence

- Gig expense capability was not implemented in the event editor flow.
- The current path is gig_pay-only:
  - UI: GigFormFields exposes only buildGigPayButton for financial input.
  - State: EventEditorDrawer only tracks \_gigPayDetails.
  - Persistence: FinancialEntryRepository has upsertGigPayEntry and generic insert/update methods, but no gig_id-aware expense methods and no gig expense fetch by gig_id.
- The existing gig_pay repository method enforces one-row-per-gig semantics, which is correct for gig_pay but invalid for expenses where one gig must support many rows.

## 4. Reference Docs Consulted

- docs/agents/ARCHITECT.md
- docs/agents/GUARDRAILS.md
- docs/agents/OPERATING_MODEL.md
- docs/agents/PROJECT_CONTEXT.md

Additional implementation references read:

- lib/features/events/widgets/event_editor_drawer.dart
- lib/features/events/widgets/gig_form_fields.dart
- lib/features/financials/financial_entry_repository.dart
- lib/features/financials/models/financial_entry.dart
- lib/features/financials/widgets/gig_pay_bottom_sheet.dart
- lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart
- lib/features/setlists/widgets/song_details_bottom_sheet.dart
- lib/features/members/permissions/band_permissions.dart
- lib/features/members/permissions/band_permissions_provider.dart
- supabase/migrations/20260601000000_create_financial_entries.sql
- supabase/migrations/20260711081810_tighten_financial_entries_rbac.sql

## 5. Existing System Analysis

Current data flow for gig financials:

1. EventEditorDrawer stores gig pay locally in \_gigPayDetails.
2. Gig pay editor opens as a separate modal (GigPayBottomSheet), not as an in-drawer sub-view.
3. On save:

- Edit gig path: \_handleSave updates gig first, then calls upsertGigPayEntry.
- Create gig path: \_handleSave creates gig first, then calls upsertGigPayEntry with saved gig id.

4. Financial entries are invalidated through financialsProvider after gig pay write.

What is missing for expenses:

- No expenses section or list under Gig Pay in the gig form UI.
- No in-drawer expense add/edit sub-view with back navigation.
- No repository methods for:
  - fetching expense rows by gig_id,
  - inserting expense rows with gig_id,
  - updating existing gig-linked expense rows with expense-specific semantics.
- No local deferred state for create-mode expenses before gig id exists.

Database behavior already supports this feature without schema changes:

- financial_entries.entry_type allows expense.
- Unique partial index uniq_gig_pay_entry is scoped to entry_type = 'gig_pay' only, so multiple expense rows per gig are allowed.
- financial_entries.gig_id references gigs(id) ON DELETE SET NULL, so deleting a gig preserves linked financial rows by nulling gig_id.

## 6. Proposed Solution

Implement Phase 1 only by adding an Expenses section and an in-drawer expense sub-view in the existing gig editor.

What changes:

1. Add gig-expense repository methods in FinancialEntryRepository:

- fetchGigExpenseEntries(gigId)
- insertGigExpenseEntry(..., gigId)
- updateGigExpenseEntry(...)

These methods must force:

- entry_type = 'expense'
- is_income = false
- category = selected category or custom text
- gig_id = target gig id
- payor_name and paid_to_name / paid_to_user_id mapped from form fields

2. Add expense form/list state in EventEditorDrawer:

- main-view section state (expense list)
- sub-view toggle state (same drawer, no new modal)
- deferred list state for create mode before gig exists

3. Add an Expenses section in GigFormFields directly under Gig Pay area:

- Add expense action
- Saved/pending expense list (amount, category, date)
- Tap existing item to edit

4. Add a dedicated in-drawer expense sub-view widget using the Song Details two-view pattern:

- boolean toggle in EventEditorDrawer
- back row with AppIcons.back
- Save and Delete actions in sub-view
- fields:
  - Amount (required)
  - Category (predefined options + custom free-text option)
  - Date (default today)
  - Paid by (band member dropdown + Other free-text)

5. Save behavior rules:

- Edit mode (gig already exists): save/edit/delete expense immediately via repository.
- Create mode (gig id not yet available): save to local deferred expense state only.
- After createGig succeeds: flush deferred expenses to financial_entries with new gig id before closing drawer.

6. RBAC alignment:

- Gate expenses section visibility with existing canViewFinancials permission.
- Gate mutating actions (add/edit/delete immediate persistence) with existing financial write permissions (admin/member path), preserving current financial_entries access model.
- No new permission path and no bypass of current gates.

What must not change:

- Existing gig_pay behavior and one-row-per-gig semantics.
- Existing EventEditorDrawer save flow for non-financial event fields.
- Phase 2 section restructuring and sound check additions.
- Phase 3 venue contact integration in gig editor.

New files required:

- lib/features/events/widgets/gig_expense_subview.dart
  - Purpose: isolate expense sub-view form UI from the already-large EventEditorDrawer.

## 7. Database Impact

Database: not applicable (schema/policy unchanged)

- Migrations: none.
- RLS policies: unchanged.
- RPC signatures: unaffected.
- Triggers: unchanged.

Validation notes:

- Existing unique partial index remains gig_pay-only.
- Existing gig_id foreign key remains ON DELETE SET NULL.

## 8. Flutter Architecture Changes

State management:

- Keep EventEditorDrawer as parent state owner.
- Keep repository writes in parent (drawer), not leaf widget.
- Sub-view widget remains presentational with callbacks.

Widgets:

- GigFormFields gains a buildExpensesSection-style method and new constructor inputs for data/callbacks/permissions.
- EventEditorDrawer toggles between main form and expense sub-view.
- New GigExpenseSubView widget provides the expense editor UI in the same drawer.

Repository:

- Extend FinancialEntryRepository with gig-expense-focused methods; do not reuse upsertGigPayEntry semantics.

## 9. Files to Create

| File                                                 | Justification                                                                                                           |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| lib/features/events/widgets/gig_expense_subview.dart | Encapsulates the in-drawer expense editor form and back-row pattern; avoids further growth in event_editor_drawer.dart. |

## 10. Files to Modify

| File                                                    | What changes                                                                                                                          |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| lib/features/financials/financial_entry_repository.dart | Add gig-expense fetch/insert/update methods using expense-only semantics and gig_id linkage.                                          |
| lib/features/events/widgets/event_editor_drawer.dart    | Add expense state, two-view toggle, immediate vs deferred save behavior, deferred flush after createGig, and list/edit/delete wiring. |
| lib/features/events/widgets/gig_form_fields.dart        | Add Expenses section under Gig Pay with Add action and line-item list; wire taps/callbacks from drawer state.                         |

Migration policy: not required

Edge function deploy: not required

New dependencies: not allowed

## 11. Files Off-Limits

| File                                                   | Reason                                                      |
| ------------------------------------------------------ | ----------------------------------------------------------- |
| lib/features/events/widgets/event_form_fields.dart     | No requirements for shared date/time form behavior changes. |
| lib/features/rehearsals/\*\*                           | Rehearsal flow is unaffected.                               |
| lib/features/contacts/widgets/venue_contact_block.dart | Venue contact work is explicitly Phase 3 scope.             |
| supabase/migrations/\*\*                               | No schema/RLS/RPC/trigger change needed for this phase.     |
| lib/main.dart                                          | No routing/init-order changes required.                     |
| docs/features/gig-expenses/ENGINEER_REPORT.md          | Architect phase only; Engineer report is out of scope now.  |

## 12. System Impact Map

| System                                 | Impact                                              |
| -------------------------------------- | --------------------------------------------------- |
| Gigs                                   | affected                                            |
| Rehearsals                             | unaffected                                          |
| Setlists / Catalog                     | unaffected                                          |
| Members / RBAC                         | affected (permission-gated visibility/actions only) |
| Auth / Session                         | unaffected                                          |
| Routing                                | unaffected                                          |
| Notifications                          | unaffected                                          |
| Platform (iOS / Android / Web / macOS) | affected equally (shared Flutter gig editor path)   |

## 13. Regression Risk

LOW

Rationale:

- Change is localized to gig editor + financial repository.
- No database migration or RLS change.
- Existing gig_pay path remains intact.
- Main risk is UI-state branching in an already large drawer; mitigated by extracting the sub-view into a dedicated widget and preserving parent-owned write flow.

## 14. Engineer Task Breakdown

1. Extend FinancialEntryRepository with gig-expense methods:

- fetchGigExpenseEntries(gigId)
- insertGigExpenseEntry(...)
- updateGigExpenseEntry(...)

2. Create gig_expense_subview.dart:

- Back row (AppIcons.back)
- Amount input
- Category selector with predefined options + custom option
- Date picker
- Paid by member dropdown + Other free-text
- Save and Delete callbacks

3. Update GigFormFields API and UI:

- Add inputs for expense list, visibility, and callbacks
- Add Expenses section directly below existing Gig Pay section
- Render expense list rows with amount/category/date and tap-to-edit

4. Update EventEditorDrawer state and flow:

- Add expense list state and current-editing-expense state
- Add two-view toggle between main gig form and expense sub-view
- Load existing expenses when editing an existing gig
- Implement immediate writes for existing gig
- Implement deferred local writes for create mode before gig id exists
- Flush deferred expenses after createGig returns id

5. Wire permission gates:

- Use currentUserPermissionsProvider to gate section visibility and mutating actions per existing financial permissions model

6. Refresh data consistency after writes:

- Invalidate/refresh financialsProvider after successful expense insert/update/delete
- Keep existing event cache invalidation behavior unchanged

7. Run static and runtime verification checklist from section 15 and record outcomes in ENGINEER_REPORT.md.

## 15. Verification Plan

Tier 1 - Pre-deployment

-- PRE-DEPLOY TEST 1:
Confirm financial_entries constraints in source remain compatible with multi-expense-per-gig behavior.

bash:

grep -n "CREATE UNIQUE INDEX IF NOT EXISTS uniq_gig_pay_entry" supabase/migrations/20260601000000_create_financial_entries.sql
grep -n "WHERE entry_type = 'gig_pay'" supabase/migrations/20260601000000_create_financial_entries.sql
grep -n "gig_id\s*UUID\s*REFERENCES public.gigs\(id\) ON DELETE SET NULL" supabase/migrations/20260601000000_create_financial_entries.sql

Expected:

- unique index exists and is scoped only to gig_pay
- gig_id FK is ON DELETE SET NULL

-- PRE-DEPLOY TEST 2:
Analyze source for intended expense persistence behavior and same-sheet sub-view wiring.

bash:

grep -n "fetchGigExpenseEntries\|insertGigExpenseEntry\|updateGigExpenseEntry" lib/features/financials/financial_entry_repository.dart
grep -n "buildExpensesSection\|onAddExpense\|onExpenseTap" lib/features/events/widgets/gig_form_fields.dart
grep -n "AppIcons.back\|\_isEditingExpense\|\_pendingGigExpenses\|createGig\|financialsProvider" lib/features/events/widgets/event_editor_drawer.dart

Expected:

- repository methods exist
- GigFormFields contains expenses section wiring
- EventEditorDrawer contains two-view toggle and deferred expense state

-- PRE-DEPLOY TEST 3:
Run Flutter static checks.

bash:

flutter analyze

Expected:

- 0 errors

Tier 2 - Post-deployment

-- POST-DEPLOY TEST 1:
Create-mode deferred behavior.

Manual flow:

1. Open Add Gig drawer.
2. Add one expense before saving gig.
3. Confirm expense appears in local Expenses list.
4. Save gig.
5. Reopen saved gig and confirm expense persisted.

Expected:

- expense is deferred locally until gig creation
- expense row exists after gig save

-- POST-DEPLOY TEST 2:
Edit-mode immediate behavior.

Manual flow:

1. Open existing gig.
2. Add an expense and save sub-view.
3. Edit same expense and save.
4. Delete same expense.

Expected:

- each save/edit/delete persists immediately without tapping global gig Save
- list updates correctly after each action

-- POST-DEPLOY TEST 3:
RBAC behavior validation.

Manual flow:

1. As contributor with can_view_financials = false, open gig editor.
2. As contributor with can_view_financials = true (but no financial write permissions), open gig editor.
3. As admin/member, open gig editor.

Expected:

- no new looser path for financial data
- visibility and mutating actions follow existing financial permission model

-- POST-DEPLOY TEST 4:
Read-only production safety query (no malformed expense data introduced).

sql:

SELECT
COUNT(_) FILTER (
WHERE entry_type = 'expense' AND is_income <> FALSE
) AS expense_with_wrong_income_flag,
COUNT(_) FILTER (
WHERE entry_type = 'expense' AND gig_id IS NULL
) AS expense_without_gig_id,
COUNT(\*) FILTER (
WHERE entry_type = 'expense' AND amount_cents < 0
) AS negative_expense_amount
FROM financial_entries;

Expected:

- all counts are 0 for rows created through gig-expense flow

-- POST-DEPLOY TEST 5:
Delete-gig linkage behavior remains ON DELETE SET NULL.

sql:

BEGIN;

-- Choose a test gig with at least one expense row, then delete within transaction
-- and verify linked expense rows are preserved with gig_id nulled.

ROLLBACK;

Expected:

- linked financial_entries rows remain and gig_id becomes NULL in transaction scope

## 16. QA Regression Areas

- Gig create/edit drawer: Expenses section placement under Gig Pay.
- In-drawer two-view behavior: back navigation returns to main gig view without closing sheet.
- Expense add/edit/delete behavior for existing gigs (immediate persistence).
- Create-mode deferred expense behavior before first gig save.
- Category UX: predefined category + custom category path.
- Paid by UX: member selection + Other free-text.
- Gig pay behavior unchanged.
- Financials screen reflects new expense rows correctly.
- Contributor permission coverage for can_view_financials and financial write restrictions.
- Cross-platform validation on web, iOS, Android, macOS.

## 17. Rollout / Migration Strategy

- No migration required.
- Implement and ship Flutter client changes only.
- Run Tier 1 checks pre-merge.
- Run Tier 2 runtime checks in staging/production after deploy.
- If issues arise, rollback via client release rollback; data model remains backward-compatible.

## 18. Out of Scope

- Phase 2 gig screen restructuring (Income/Location/Important Times sections).
- Any sound check time schema or UI changes.
- Phase 3 venue contacts integration in gig editor.
- Changes to notification flows.
- Any Supabase schema/RLS/RPC migration work not strictly required for this phase.

## Addendum: Expense Reimbursement Tracking

### Root Cause / Gap

Current gig-expense support persists purchase metadata (amount/category/date/payer) but has no structured reimbursement fields, so the app cannot reliably represent whether an expense was reimbursed, when reimbursement happened, or render a consistent computed reimbursement detail line from canonical data.

Confidence: HIGH (confirmed in code)

- financial_entries schema has no reimbursement columns.
- FinancialEntry model does not parse/serialize reimbursement fields.
- Gig expense sub-view has no reimbursement toggle/date UX.
- Expense list row rendering and financial entry detail rendering have no reimbursement badge/detail-line logic.

### Database Impact

Migration policy: required.

Create one new migration file following repo timestamp naming convention:

- supabase/migrations/20260803120000_add_reimbursement_fields_to_financial_entries.sql

SQL:

```sql
-- Add reimbursement tracking fields to financial_entries
ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS is_reimbursed BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS reimbursed_date DATE;

-- Keep reimbursement data consistent: date is required only when reimbursed.
ALTER TABLE public.financial_entries
  DROP CONSTRAINT IF EXISTS financial_entries_reimbursement_consistency;

ALTER TABLE public.financial_entries
  ADD CONSTRAINT financial_entries_reimbursement_consistency
  CHECK (
    (is_reimbursed = FALSE AND reimbursed_date IS NULL)
    OR
    (is_reimbursed = TRUE AND reimbursed_date IS NOT NULL)
  );
```

RLS assessment:

- financial_entries SELECT/INSERT/UPDATE/DELETE policies are row-scoped by band membership/role and are not column-specific.
- No policy change required for adding these columns.
- Existing UPDATE policy already governs writes to the new columns.

### Display/Computation Contract

The reimbursement detail line must be computed at render time from structured fields only:

- purchase date: financial_entries.entry_date
- reimbursed date: financial_entries.reimbursed_date
- reimbursed recipient: the expense payer field already captured on the expense (payor_name in storage, mapped as payerName in model)

No new freeform reimbursement summary column or blob is allowed.

### Scope Decision: Generic Add/Edit Financial Entry Flow

Decision: keep reimbursement editing scoped to gig-linked expenses only for this addendum.

Rationale:

- Requirement explicitly targets gig expenses and names the two required surfaces: gig drawer expenses list and Financials table expense detail view.
- The generic add/edit flow is shared across non-gig income/expense use cases and expanding it now increases scope/risk.
- Financials detail view will still display reimbursement state for reimbursed expenses; editing reimbursement stays in gig expense flow.

Explicit caveat:

- If Tony later wants reimbursement editable from the generic add/edit flow, that should be a separate follow-up addendum.

### Files to Create (Addendum)

- supabase/migrations/20260803120000_add_reimbursement_fields_to_financial_entries.sql

### Files to Modify (Addendum)

- lib/features/financials/models/financial_entry.dart
  - Add isReimbursed (bool) and reimbursedDate (DateTime?) fields.
  - Map fromJson/toJson for is_reimbursed and reimbursed_date.

- lib/features/events/widgets/gig_expense_subview.dart
  - Extend GigExpenseDraft with reimbursement fields.
  - Add Mark as Reimbursed toggle.
  - Add reimbursed date picker shown only when toggle is on.
  - Default reimbursed date to today when toggled on for new/unspecified values.

- lib/features/events/widgets/event_editor_drawer.dart
  - Hydrate reimbursement fields when mapping FinancialEntry -> GigExpenseDraft.
  - Pass reimbursement fields through immediate/deferred save flows.

- lib/features/financials/financial_entry_repository.dart
  - Extend insertGigExpenseEntry/updateGigExpenseEntry signatures to accept isReimbursed/reimbursedDate.
  - Persist is_reimbursed and reimbursed_date (force reimbursed_date = NULL when isReimbursed = false).

- lib/features/events/widgets/gig_form_fields.dart
  - In buildExpensesSection, add Reimbursed badge when applicable.
  - Render computed reimbursement detail line for reimbursed expenses.

- lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart
  - Show Reimbursed badge for reimbursed expense entries.
  - Show computed reimbursement detail line using entry date, reimbursed date, and payer.

### Files Explicitly Off-Limits (Addendum)

- lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart
  - No reimbursement input controls in this addendum (scoped to gig-linked expenses only).

- lib/features/financials/financials_controller.dart
  - No controller architecture changes required; repository/model updates are sufficient.

- supabase/migrations/20260711081810_tighten_financial_entries_rbac.sql
  - Existing RBAC policies remain valid; do not alter.

- lib/main.dart
  - No app initialization changes.

### Regression Risk

MEDIUM

Why:

- Adds schema and model fields used across financial entry reads.
- Touches both gig editor expense flow and Financials detail rendering.
- Risk is bounded by no auth/init/routing change and no RLS policy mutation.

### Engineer Task List (Ordered, Addendum Only)

1. Create migration file supabase/migrations/20260803120000_add_reimbursement_fields_to_financial_entries.sql with the exact SQL above.
2. Update FinancialEntry model parsing/serialization for is_reimbursed and reimbursed_date.
3. Extend GigExpenseDraft and GigExpenseSubView UI with reimbursement toggle + conditional reimbursed date picker (default today).
4. Thread reimbursement fields through EventEditorDrawer expense mapping, save, update, delete-safe state transitions, and deferred flush.
5. Extend FinancialEntryRepository insertGigExpenseEntry/updateGigExpenseEntry to persist reimbursement fields and null reimbursement date when toggle is off.
6. Update GigFormFields expenses list rendering to show Reimbursed badge + computed detail line for reimbursed expenses.
7. Update FinancialEntryDetailsBottomSheet to show the same Reimbursed badge + computed detail line for reimbursed expense entries.
8. Verify no generic add/edit reimbursement controls were added (intentional scope guard).
9. Run flutter analyze and targeted manual checks:
   - add reimbursed expense in create-gig deferred mode
   - add/edit reimbursed expense in existing gig mode
   - confirm reimbursement badge/detail line appears in gig drawer list and Financials detail view
   - confirm toggling reimbursement off clears reimbursed_date in persisted row
