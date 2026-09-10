# QA Report — transaction-drawer-redesign

## Feature Slug

`transaction-drawer-redesign`

## Feature Title

Redesign Add/Edit Transaction Drawer with Sectioned Layout

## Cycle Number

1

## Final Verdict

**APPROVED**

## Validation Summary

Reviewed `ARCHITECT_PLAN.md` (original + ADDENDUM), `ENGINEER_REPORT.md` (including
the Fallback Mode banner, Follow-up Changes, and Addendum Implementation
sections), and the full uncommitted `git diff` against `HEAD` on
`feature/transaction-drawer-redesign`. All 17 original Engineer Task Breakdown
items and all 15 addendum Engineer Task Breakdown items were independently
verified present and correct in the diff by direct code inspection — not by
trusting the Fallback-Mode self-report. Analyzer and the widget test suite were
independently re-run (not just taken on the Manager's word) and both pass.
Migration was reviewed by static SQL inspection; live-apply to the ephemeral
`qa-transaction-drawer-redesign` branch could not be completed due to a
Postgres password-authentication failure against that branch's database (see
Database Safety below) — this is disclosed, not silently skipped.

**Testing performed**: code-path analysis of the full diff against both plan
documents; independent `flutter analyze` and `flutter test` runs (not reused
from Manager's report); static SQL review of the migration; diff-safety grep
for secrets/TODO/debugPrint; change-budget arithmetic against both Change
Budget tables. **Not performed** (correctly, per QA scope): any running-app /
manual UI verification — that is Tony's punch list below.

## Architect Scope Review

- Branch `feature/transaction-drawer-redesign` confirmed checked out, working
  tree matches the plan's expected file set: 6 planned modified files + 1
  planned new migration + 1 new/extended test file + plan/report docs. No
  off-limits file touched (`event_editor_drawer.dart`, `gig_pay_bottom_sheet.dart`,
  `gig_expense_subview.dart`, `lib/features/contacts/**`, `lib/features/gigs/**`,
  `lib/features/members/**`, `lib/app/theme/**`, any other migration, any
  platform folder — all confirmed absent from `git status --short`).
- Two untracked doc directories from unrelated in-flight sessions
  (`docs/features/bug/demo-session-cleanup-orphaned-anonymous-users/`,
  `docs/features/feature/financials-transaction-cards/`) are present but
  contain no source changes and are correctly out of this feature's diff —
  consistent with the Engineer Report's disclosed background on the fallback.
- Fallback Mode banner reviewed: the diff was cross-checked task-by-task
  against the plan text itself (not the self-report's checklist), so the
  extra scrutiny called for was applied.

## Completeness Check

**Original plan — all 17 Engineer Task Breakdown items confirmed in code:**
migration file exact match; model gains `reimbursementMethod`/`notes` wired
into `fromJson`/`toJson`; repository `insertEntry`/`updateEntry` gain the 5
params and payload entries exactly as specified (gig-linked helpers
untouched); controller passes the 5 params through with no state-shape
change; both call sites (`financials_screen.dart`,
`financial_entry_details_bottom_sheet.dart`) forward all 5 fields; drawer
rewritten to the full sectioned `_SectionCard` layout with sticky
header/footer, `FTheme(data: buildEventEditorTheme())` wrapper,
`useSafeArea: true`; About/Payment Details/Distribution/Reimbursement/Notes
sections all present and gated correctly by income/expense mode; contacts +
venues + gigs load-if-empty wired via `ConsumerStatefulWidget`; save flow
preserves `paidToUserId`/`paidToName` verbatim on income edit; the
`uniq_gig_pay_entry` friendly-error catch is present; header/footer copy
matches spec exactly (`'Add Transaction'`/`'Edit Transaction'`,
`'Delete Income'`/`'Delete Expense'`).

**Addendum — all 15 Engineer Task Breakdown items confirmed in code:**
`_distributionErrors` field; `_computeInitialDistributionErrors`,
`_pickFallbackErrorAttribution`, `_syncDistributionState`, `_onAmountChanged`
all present with bodies matching the plan's pseudocode; `_onDisbursementChanged`
fully removed (grep-confirmed no remaining references); `initState`/`dispose`
rewired to `_onAmountChanged`; `_populateSplits` no longer attaches per-split
listeners (no `isNew` local); `_onDisburseToggle` ends with
`_syncDistributionState()`; `_setIsIncome` clears `_distributionErrors` on
income→expense; per-member split and Savings `CurrencyTextField`s wired to
`_syncDistributionState(changedFieldKey: ...)`; Deposit-to-Savings switch
replaced with the exact 3-branch precedence rule; inline error rendering
present at both the per-split row and Savings field with correct
error-over-helper-text precedence; Save gate is
`_amountController.cents > 0 && _distributionErrors.isEmpty`; `mapEquals`
import present and correctly placed.

No partial implementations or missing edge cases found against either
document.

## Behavior Verification

**Code-path analysis only** (no runtime exercise — correctly out of QA's
scope per mode rules).

- Root cause for both the base redesign and the addendum's two refinements
  (no full-amount auto-fill; no over-allocation validation) is fixed at the
  source: the new `_syncDistributionState`/switch-precedence logic replaces
  the old `_onDisbursementChanged` early-return entirely, rather than
  patching around it.
- No extra behavior beyond spec was added to the distribution/reimbursement/
  autocomplete logic. One small, plan-unlisted addition was found: `_setIsIncome`
  also resets `_isReimbursed = false` when switching to income mode (in
  addition to the plan-specified `_distributionErrors` clear on the
  expense→income direction). This has no persisted-data effect — `_save()`
  already forces `isReimbursed: null` whenever `_isIncome == true` regardless
  of this flag — so it's inert UI-state hygiene, not a scope violation. Noted
  as a Suggestion below, not blocking.
- Verified `FAutocompleteController` / `FAutocompleteControl.managed` /
  `FAutocompleteItem.item` usage is copied verbatim from the existing pattern
  in `gig_form_fields.dart` / `event_editor_drawer.dart` — no new
  autocomplete abstraction introduced.
- Verified the full-height `Container` + `FTheme(buildEventEditorTheme())` +
  hardcoded header colors (`0xFFFAFAFA`/`0xFF8b8b93`) match
  `event_editor_drawer.dart`'s own existing header pattern byte-for-byte —
  not a new convention.

## Regression Check

**MEDIUM** (matches the Architect plan's own stated risk rating; nothing
found to elevate it).

- Auth/session/routing/init-order: unaffected — no touched file is on any of
  those paths; confirmed zero diff in `test/features/auth/` and
  `lib/features/auth/` vs `main`.
- Supabase RPC signatures: no RPC touched or created.
- Platform parity: no platform-conditional code introduced; single shared
  Flutter widget.
- Controller/FocusNode disposal: `dispose()` correctly disposes all new
  controllers (`_reimbursementMethodOtherController`, `_notesController`,
  `_payerController` as `FAutocompleteController`); the old
  `c.removeListener(_onDisbursementChanged)` per-split loop was correctly
  removed since no per-split listeners remain (only `c.dispose()`), matching
  the addendum's rewiring — no dangling listener risk.
- `setState` after async gaps: `_save()`'s `try/catch` correctly guards with
  `if (!mounted) return;` before every `setState`/`Navigator` call, including
  in the new `PostgrestException` branch.
- Rebuild triggers/frequency: split/savings `CurrencyTextField.onChanged` is
  a true user-only edit signal (verified against
  `currency_input_field.dart`'s internal `_syncFromController` vs. `onChanged`
  split, as the plan documents) — programmatic writes during
  `_populateSplits` no longer trigger redundant `setState` cascades, which is
  a net improvement over the pre-addendum code, not a regression.
- `financial_entry_details_bottom_sheet.dart`'s large diff (99+/-85) is
  confirmed whitespace/re-indentation only — every changed line diffed
  identical content, no `Text`, ordering, or widget-tree change; the
  `payerName`-always-labelled-"Payer" quirk is untouched, correctly out of
  scope.

## Database Safety

**Static SQL review only — live-apply not completed, disclosed below.**

- Migration `supabase/migrations/20260909000000_add_transaction_drawer_fields_to_financial_entries.sql`
  matches the plan exactly: `reimbursement_method TEXT`, `notes TEXT` added
  via `ADD COLUMN IF NOT EXISTS`; `financial_entries_reimbursement_consistency`
  dropped and re-added with the tightened 3-column form.
- Read the actual predecessor constraint
  (`supabase/migrations/20260803120000_add_reimbursement_fields_to_financial_entries.sql`):
  old form was `(is_reimbursed=FALSE AND reimbursed_date IS NULL) OR
  (is_reimbursed=TRUE AND reimbursed_date IS NOT NULL)`. The new form only
  adds `AND reimbursement_method IS NULL` to the FALSE branch. Since
  `reimbursement_method` is a brand-new column (defaults `NULL` for every
  existing row), every existing row satisfies the tightened constraint —
  confirmed by reading the column-add and constraint-add order in the same
  migration file (columns added before the constraint swap).
- No RLS, RPC, trigger, or `SECURITY DEFINER` function created or touched —
  confirmed no `CREATE FUNCTION` / `CREATE POLICY` / `CREATE TRIGGER`
  statement anywhere in the file. The `has_function_privilege` grant check
  from the QA process does not apply here (no new/changed
  `SECURITY DEFINER` function in this diff).
- **Live-apply attempt**: the ephemeral branch `qa-transaction-drawer-redesign`
  exists (`status: FUNCTIONS_DEPLOYED`, `preview_project_status: ACTIVE_HEALTHY`,
  created `--with-data`). The local CLI is already linked to that branch's
  project ref (`xtxubluezakwmvpxsbbi`). Attempted `supabase migration list`
  against it to check pending-migration status before applying; it failed
  with `FATAL: password authentication failed for user "postgres"
  (SQLSTATE 28P01)` even with `SUPABASE_DB_PASSWORD` set from the branch's
  own `supabase branches get` output. Per the explicit instruction in this
  task to not spend further time troubleshooting Supabase CLI auth, I did
  **not** attempt any workaround (no production fallback, no password
  reset) and stopped here. **This means the migration's applied-and-verified
  status is not confirmed by me at the SQL-execution level** — only by
  reading the file. Tony/Manager should either resolve the branch DB
  credential issue and re-run Tier 2, or treat the static review above as
  sufficient given the migration's simplicity (additive columns + a
  constraint tightening that is provably satisfied by all existing rows).
  This is disclosed as an incomplete-verification gap, not silently absorbed
  into an APPROVED verdict — see rationale below for why it doesn't change
  the verdict.

## Analyzer Results

Independently re-run (not reused from `ENGINEER_REPORT.md`):

```
flutter analyze lib/features/financials/ test/features/financials/
→ No issues found! (ran in 2.9s)
```

Clean at all severities across every touched file.

## Test Results

Independently re-run:

```
runTests: test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart
→ 16 passed, 0 failed
```

Confirmed zero diff in `test/features/auth/` / `lib/features/auth/` vs.
`main` (`git diff --stat main -- test/features/auth/ lib/features/auth/`
returns empty), corroborating the Engineer Report's claim that the 2
pre-existing `login_screen_demo_button_test.dart` failures in the full suite
are unrelated to this branch. Full `flutter test` suite was not re-run in
full by QA (Manager already ran it and the auth-unrelatedness is
independently verifiable via the empty diff above); the targeted financials
suite re-run above is the direct verification for this feature's own tests.

## Diff Safety Review

- Grepped the full diff (`lib/features/financials`, the new migration,
  `test/features/financials`) for `TODO|FIXME|debugPrint\(|api[_-]?key|secret|password`
  — zero matches.
- No secrets, API keys, or credentials in the diff.
- No leftover test scaffolding or accidental deletions found; the
  `financial_entry_details_bottom_sheet.dart` re-indentation is whitespace-only
  (confirmed above), not a content change.

## Change Budget Review

| File | Plan budget (combined original+addendum where applicable) | Actual net delta | Verdict |
|---|---|---|---|
| `add_financial_entry_bottom_sheet.dart` | +550 to +800 (orig) + +80 to +120 (addendum) = ~+630 to +920 | +549 (938 −389) | Under budget |
| `financial_entry_repository.dart` | +25 to +40 | +18 (24 −6) | Under budget |
| `financials_controller.dart` | +20 to +30 | +19 (21 −2) | Under budget |
| `financials_screen.dart` | +8 to +12 | +2 (18 −16) | Under budget |
| `financial_entry_details_bottom_sheet.dart` | +8 to +12 | +14 (99 −85) | ~1.17x — within tolerance, explained by disclosed re-indentation |
| `models/financial_entry.dart` | +8 to +12 | +8 | At lower bound |

No file exceeds 1.5x budget; no new files, public classes, or dependencies
beyond what the plan expected (1 migration file; 1 test file extended, not
newly created against the addendum's own budget). No Critical-level bloat.

## Code Efficiency Review

- No hand-rolled abstraction was created where an existing one applies:
  `FAutocompleteController`/`FAutocompleteControl.managed`/`FAutocompleteItem.item`
  are the exact same forui primitives already used in
  `gig_form_fields.dart`/`event_editor_drawer.dart` — grepped and confirmed
  reused, not reinvented.
- The private `_SectionCard` class is a verbatim duplicate of
  `event_editor_drawer.dart`'s, per the plan's explicit instruction to
  duplicate rather than extract to a shared component (extraction was
  explicitly Out of Scope in the plan).
- The drawer file is 1686 lines, over the repo's 500-line Dart-file target.
  `ENGINEER_REPORT.md` states the one-line justification required by the QA
  process ("this file predates this pass... out of scope to split up under
  this addendum's task list") — satisfies the guardrail; not a Warning.
- New private methods (`_syncDistributionState`, `_pickFallbackErrorAttribution`,
  `_onAmountChanged`, `_computeInitialDistributionErrors`) are each used from
  exactly the call sites the plan specifies; none is a single-use wrapper
  around something `package:collection` or an existing helper already
  provides.
- Test file reuses the existing (previously-unused) `_controllerText` helper
  rather than adding a new one, per the Engineer Report's own disclosure —
  confirmed by reading the test file; no duplicate helper found.
- One minor, undisclosed deviation (Suggestion-level, see Issues Found): the
  `_setIsIncome` reset of `_isReimbursed` on income switch is not mentioned in
  either the plan or `ENGINEER_REPORT.md`'s task-by-task breakdown, though it
  is harmless.

## Manual Verification Punch List

The following is **owner-run only** — QA did not and must not attempt these
(no `flutter run`, simulator, or browser automation was used). This is the
plan's own punch list, reproduced here for Tony to execute directly.

### From the original plan

1. Open the app → Home → Financials. Tap "Add Entry" while Income mode is
   selected. **Expected**: Full-height drawer opens; header shows
   `'Add Transaction'` + subtitle `"Track your band's income or expense."`;
   Income/Expense segmented pill below; body shows **About**, **Payment
   Details**, **Distribution** section cards in order; footer shows
   `Cancel` / `Add Transaction`.
2. In **Payment from**, type `Rive`. **Expected**: Autocomplete shows
   contacts/venues containing "Rive" tagged `Contact`/`Venue`, plus a
   trailing `Use "Rive"` row. Typing `xylophone` shows only `Use "xylophone"`.
3. Enter Amount `$250.00`, pick a Date, Type = "Merch Sale", turn on
   **Disburse to Band**. **Expected**: Member splits appear, evenly divided
   with remainder cents on the first member.
4. Reduce one member's split to `$30.00`. **Expected**: Deposit to Savings
   auto-toggles ON, label shows `($<shortfall>)`, Savings field shows the
   shortfall, helper text `"Automatically calculated from remaining amount."`
   appears.
5. Change that split back up to fully cover the amount. **Expected**:
   Savings snaps to `$0.00`; toggle stays ON where the user left it.
6. Tap **Add Transaction**. **Expected**: Drawer closes; entry appears at
   top of list; total = sum(splits) + savings.
7. Open the new entry's details → **Edit Entry**. **Expected**: Header
   `'Edit Transaction'`, no subtitle; footer shows `Cancel` / `Save` +
   `Delete Income` destructive button.
8. New Add drawer, switch to **Expense**. **Expected**: Distribution section
   replaced by **Reimbursement** (single "Reimbursed by Band" toggle, off);
   Payment Details shows **Paid to** → **Paid by** → **Related to Gig**.
9. Type `Jimm` in **Paid to**. **Expected**: same autocomplete behavior as
   step 2.
10. Turn **Reimbursed by Band** ON. **Expected**: "Reimbursed on" date row
    (default today) + "Method" dropdown appear; selecting `Other` reveals a
    free-text field with placeholder `"e.g., PayPal"`.
11. Enter `PayPal`, save, reopen in edit mode. **Expected**: toggle ON, date
    preserved, Method = `Other`, free-text shows `PayPal`.
12. Add drawer, Income mode, Type = `Gig Pay`, link **Related to Gig** to a
    gig that already has a Gig Pay entry, Save. **Expected**: error snackbar
    `"This gig already has a Gig Pay entry. Open the gig to edit it instead."`;
    drawer stays open.

### From the addendum

1. Amount `$200.00`, Disburse OFF, tap **Deposit to Savings** ON.
   **Expected**: Savings Amount auto-fills `$200.00` immediately; Save
   enabled.
2. Toggle Disburse ON. **Expected**: splits pre-fill evenly to $200.00 total;
   Savings snaps to `$0.00`; toggle stays ON; Save remains enabled.
3. Reduce one member's split from ~$33 to `$20`. **Expected**: Savings
   jumps to reflect the new remainder; helper text shown; Save enabled.
4. Type `$500` into that split. **Expected**: red `"Exceeds remaining
   balance"` appears directly beneath that split field; Save button
   disabled.
5. Reduce that split back to a valid value. **Expected**: error clears;
   Save re-enabled; Savings auto-recomputes.
6. Disburse OFF, Savings still ON, type `$300` into Savings (Amount $200).
   **Expected**: red error under Savings; Save disabled.
7. Clear Savings, enter `$150`. **Expected**: error clears; Save enabled.
8. With a positive remainder auto-filled in Savings, toggle Deposit to
   Savings OFF. **Expected**: Savings snaps to `$0.00`, field collapses,
   label subtotal unchanged, Save enabled.
9. Toggle Deposit to Savings ON again (Disburse still ON, remainder ~$13).
   **Expected**: Savings reveals and re-fills with the remainder ($13.00),
   not the full amount.
10. From scratch, Disburse OFF: Savings ON (fills $200) → OFF ($0) → ON
    again. **Expected**: refills $200 (idempotent).
11. Save any valid state. **Expected**: entry total = sum(splits) + savings
    = amount exactly.

### QA Regression Areas (also owner-run)

1. Gig Pay flow inside the event editor still opens/saves/updates
   `financial_entries.gig_id` correctly.
2. Gig Expense sub-view inside the event editor still opens/saves an
   expense linked to a gig.
3. An existing income entry with `paid_to_user_id` set: open in edit mode,
   change only the amount, save, reopen — `paidToUserId`/`paidToName` must
   still be set (not nulled).
4. Financials list / PDF export / reports still render existing entries
   correctly (new columns are `NULL` on old rows).
5. Contributor role (`can_view_financials=true`, `can_create_financials=false`)
   still cannot see Add / cannot save from Edit.
6. Band switch: contacts/venues/gigs suggestion lists reflect the newly
   active band.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

1. **[code-quality]** `_setIsIncome` resets `_isReimbursed = false` when
   switching to income mode — a small, reasonable UI-state-hygiene addition
   that is not itemized in either `ARCHITECT_PLAN.md`'s Engineer Task
   Breakdown or `ENGINEER_REPORT.md`'s task-by-task verification list. It has
   no persisted-data effect (`_save()` already forces `isReimbursed: null`
   whenever `_isIncome == true`), so it does not affect correctness or scope,
   but future QA cycles on this file should be aware it exists outside the
   documented task list.
2. **[database-safety]** Migration was verified by static SQL review only.
   Live-apply to the `qa-transaction-drawer-redesign` ephemeral branch could
   not be completed due to a Postgres password-authentication failure against
   that branch's database, even using the password returned by
   `supabase branches get`. Recommend Manager/Tony resolve the branch
   credential and re-run the Tier 2 SQL apply-check
   (`supabase migration list` / apply / rollback) before or shortly after
   this migration is applied to staging, given how central financial-data
   integrity is to this feature.

## Verdict Rationale

All plan tasks (32 total across both documents) are implemented correctly by
direct code inspection; no off-limits files touched; no regressions found in
code-path analysis; analyzer and the feature's own test suite pass on
independent re-run; diff is free of secrets/debug artifacts; change budget is
met or under in every file. The one incomplete verification (migration
live-apply) is disclosed rather than hidden, and does not itself justify
REQUIRES CHANGES because: the migration is purely additive (two nullable
columns) plus a constraint tightening that is provably satisfied by every
existing row from static SQL reading alone, with no RPC/RLS/trigger surface
that would need runtime confirmation. Both Suggestion-level findings are
non-blocking per the APPROVED criteria (no Critical/Warning present).

**Report path**: `docs/features/transaction-drawer-redesign/QA_REPORT.md`
