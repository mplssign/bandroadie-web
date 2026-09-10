# ARCHITECT_PLAN — transaction-drawer-redesign

## Feature Slug

`transaction-drawer-redesign`

## Feature Title

Redesign Add/Edit Transaction Drawer with Sectioned Layout

## Problem Summary

The current Add/Edit Entry drawer for financial transactions (income/expense) is
a single long flat vertical form: title, segmented Income/Expense toggle, a row
of type pills, then a linear stack of `AppTextField` / `AppSwitch` /
`OutlinedButton` rows with no visual grouping. Payer/Paid-to are plain text or a
member-picker-with-Other; there is no autocomplete against known contacts or
venues. Disbursement + Savings do not stay balanced (user must manually
reconcile). "Related to Gig," reimbursement date, and reimbursement method are
not surfaced at all in the manual drawer today — only via the Gig editor's
expense sub-view. Notes lives inside the same flat stack as everything else.

Tony wants the drawer restructured to match the shape of the existing Add/Edit
Event drawer (bordered `_SectionCard`s with a large heading and a fixed sticky
footer), extended with contact/venue autocomplete on the "who paid / was paid"
field, auto-balancing distribution math (unallocated member split flows to
savings and toggles Deposit to Savings on), and a dedicated Reimbursement
section (including a new reimbursement method).

## Root Cause

**Confidence: HIGH** (confirmed in code, not a hypothesis).

The current drawer is one `SingleChildScrollView` > `Column` at
[lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L497-L863)
that emits every field inline with `Text(label)` + widget rows and
`SizedBox(height: Spacing.spaceN)` between them. There are no section
containers, no section headings, and the header is a title + drag handle rather
than a title + subtitle + close button + segmented type control.

The reference pattern already exists in the codebase at
[lib/features/events/widgets/event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L2712-L3020):
sticky header with title/subtitle/close, an `Expanded` scrollable body composed
of `_SectionCard(title:'…', child:…)` blocks, and a
[`SheetFooter`](lib/components/ui/sheet_footer.dart) sticky footer. The private
`_SectionCard` implementation lives at
[event_editor_drawer.dart lines 3546–3580](lib/features/events/widgets/event_editor_drawer.dart#L3546-L3580).

The three genuinely new pieces of behaviour are:

1. **Payment-from / Paid-to autocomplete against contacts + venues.** The data
   already exists via
   [`contactsProvider`](lib/features/contacts/contacts_controller.dart#L171) and
   [`venuesProvider`](lib/features/contacts/venues_controller.dart#L204) —
   band-scoped, 5-minute in-memory cached, no new backend infrastructure
   required. The `FAutocomplete.text` /
   `FAutocomplete.textBuilder` pattern is already used at
   [gig_form_fields.dart lines 971–1065](lib/features/events/widgets/gig_form_fields.dart#L971-L1065)
   for gig-name/city autocomplete and can be reused verbatim.
2. **Auto-balancing distribution math.** The current
   [`_onDisbursementChanged`](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L272-L279)
   listener already syncs `_depositToSavingsController` to
   `total − sumOfSplits`, but it early-returns when `_depositToSavings` is
   `false`. Tony's new rule is: if member splits ever leave a positive
   remainder, savings must absorb it AND the Deposit-to-Savings switch must
   auto-turn on. That's a small guarded state transition inside the same
   listener plus a per-split `onChanged` hook — no new controller.
3. **"Related to Gig" + Reimbursement (date + method) surfaced in the manual
   drawer.** `gig_id`, `is_reimbursed`, and `reimbursed_date` are already
   columns on
   [`financial_entries`](supabase/migrations/20260601000000_create_financial_entries.sql#L7-L28)
   and
   [reimbursement additions](supabase/migrations/20260803120000_add_reimbursement_fields_to_financial_entries.sql#L1-L16),
   just not surfaced in the manual add drawer today. The redesign wires them
   through. Reimbursement **method** (Zelle/Venmo/Cash/Check/Other-freetext) is
   the ONE genuinely new column — nothing in the current schema can carry it.

## Existing System Analysis

- **Drawer entry points (2)**:
  [`financials_screen.dart:47`](lib/features/financials/financials_screen.dart#L40-L81)
  (add) and
  [`financial_entry_details_bottom_sheet.dart:179`](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart#L179-L210)
  (edit). Both call `showAddFinancialEntrySheet(...)` with the `_SaveCallback`
  typedef and pass `members`, `savingsTotalCents`, `initialEntry`, `onDelete`.
  Any new save-callback fields must land in both call sites.
- **Controller**:
  [`FinancialsNotifier`](lib/features/financials/financials_controller.dart#L100-L275)
  exposes `addEntry(...)` / `updateEntry(...)` /`deleteEntry(...)`. Both
  `addEntry` and `updateEntry` currently accept a fixed positional set of
  fields; they'll get 4 new optional params (`gigId`, `isReimbursed`,
  `reimbursedDate`, `reimbursementMethod`) and pass them straight through to
  the repository.
- **Repository**:
  [`FinancialEntryRepository.insertEntry` / `updateEntry`](lib/features/financials/financial_entry_repository.dart#L242-L338)
  write to `financial_entries` directly. Both need the same 4 new fields added
  to their payload. `gig_id`, `is_reimbursed`, `reimbursed_date` already exist
  as columns; `reimbursement_method` is new.
- **Model**: [`FinancialEntry`](lib/features/financials/models/financial_entry.dart#L54-L152)
  already carries `gigId`, `isReimbursed`, `reimbursedDate`; needs a new
  `reimbursementMethod` field wired into `fromJson` / `toJson`. `GigPayDetails`
  is unrelated (used by `gig_pay_bottom_sheet.dart`, off-limits here).
- **Autocomplete data sources**:
  [`ContactsRepository`](lib/features/contacts/contacts_repository.dart#L27-L64)
  and
  [`VenuesRepository`](lib/features/contacts/venues_repository.dart#L27-L67)
  fetch the whole band-scoped list into a 5-minute in-memory cache; the
  `ContactsNotifier.build()` and `VenuesNotifier.build()` return empty state
  and do NOT auto-load, so the drawer must call `.load(bandId)` in `initState`
  if `state.contacts.isEmpty` / `state.venues.isEmpty`.
- **"Related to Gig" data source**:
  [`gigProvider` → `state.allGigs`](lib/features/gigs/gig_controller.dart#L106-L214).
  `Gig` model exposes `id`, `name`, `date` — enough to render each item as
  "Name — Formatted Date."
- **`_SectionCard` pattern**:
  [`event_editor_drawer.dart:3546–3580`](lib/features/events/widgets/event_editor_drawer.dart#L3546-L3580)
  — a private, ~30-line container with `kEdCardBg` background, `kEdCardBorder`
  border, 12px radius, 24px padding, 28px section title. Colour tokens live in
  [`event_editor_theme.dart`](lib/app/theme/event_editor_theme.dart) as
  `kEdSurface / kEdCardBg / kEdCardBorder / kEdSegmentedBorder`.
- **Sticky footer**:
  [`SheetFooter`](lib/components/ui/sheet_footer.dart) already supports
  `primaryLabel` + `onPrimary` + `onCancel` + `destructiveLabel` +
  `onDestructive` — every button variant the redesign needs.
- **Existing semantic inversion (do NOT change)**: for expenses today, the UI
  labels `payor_name` as "Paid To" (vendor free text) and `paid_to_user_id` /
  `paid_to_name` as "Paid By" (member picker + Other free-text) — see
  [add_financial_entry_bottom_sheet.dart lines 601–681](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L601-L681).
  Tony's spec keeps this inversion. The Dart field names (`payerName`,
  `paidToUserId`, `paidToName`) and DB columns (`payor_name`, `paid_to_user_id`,
  `paid_to_name`) all stay unchanged — the redesign is purely a re-labelling
  from "Paid To" → "Paid to" (with autocomplete) and "Paid By" → "Paid by."
- **Edge case — `uniq_gig_pay_entry` UNIQUE partial index**:
  [migration 20260601000000 lines 41–43](supabase/migrations/20260601000000_create_financial_entries.sql#L41-L43)
  enforces at most one `entry_type = 'gig_pay'` per `gig_id`. If the user
  selects "Gig Pay" as the type AND links the manual entry to a gig that
  already has a gig_pay entry, insert will bounce with a UNIQUE violation.
  This is a pre-existing constraint the redesign inherits; see Engineer Task
  Breakdown item 8 for the surfaced error message.
- **Existing income entries with `paid_to_user_id` set**: the redesign removes
  the "Paid To" member picker from income mode entirely. To avoid silently
  nulling existing data on edit-and-resave, the drawer must pass the existing
  `paidToUserId` / `paidToName` through unchanged on save in income edit mode
  (they are simply not user-editable via this drawer any more).

## Proposed Solution

Replace the flat form body of `_AddFinancialEntryBottomSheet` with the
sectioned pattern from `EventEditorDrawer`, plus wire up the four new pieces of
behaviour (autocomplete, auto-balance, related gig, reimbursement details).

### Header (sticky, no drag handle)

```
Row:
  Column (Expanded):
    Title:  "Add Transaction" (create)  |  "Edit Transaction" (edit)
    Subtitle (create-mode only): "Track your band's income or expense."
  IconButton(icon: Icons.close, 32×32, onPressed: pop)

SizedBox(12)

_SegmentedToggle (existing widget, reused): Income | Expense
```

### Scrollable body — sections, in order

Each is a `_SectionCard(title: '…', child: Column(...))`. Section content uses
Forui-backed wrappers (`AppTextField`, `AppDropdown`, `AppSwitch`,
`CurrencyTextField`) and `FAutocomplete.textBuilder` for autocomplete.

**Section: About** (both income and expense)

- **Type**: existing horizontal `_TypePillRow` (preserve +Add / Remove management).
- **Amount**: `CurrencyTextField` (existing).
- **Date**: `OutlinedButton.icon` → `showAppDatePicker` (existing).
- **Short description**: `AppTextField`. Placeholder is income-aware:
  - Income: `"Where did the money come from?"`
  - Expense: `"e.g., Dinner after rehearsal"`
  - No visible "(optional)" wording.

**Section: Payment Details** (structure differs by mode)

- **Income**:
  - **Payment from** — `FAutocomplete.textBuilder`, single controller.
    - Filter source: `contactsProvider.state.contacts` (name field) +
      `venuesProvider.state.venues` (name field), combined and deduplicated by
      lowercased name.
    - `filter(query)`: return `.contains(query)` matches when `query.length >=
      2`, else empty. Suggestion rows show `name` + a small right-aligned
      `Contact` or `Venue` label — implement via `FAutocomplete.textBuilder`'s
      `contentBuilder` returning `FAutocompleteItem.item` wrappers around a
      custom `Row(name, Spacer, badge)` child (there is no `FAutocompleteItem.rich`
      in the current Forui version — verified by grep — so the item is
      constructed as `.item(value: name)` and the visual row is composed inside
      `contentBuilder`).
    - Bottom row of the suggestion list, when the current query has no exact
      match: `Use "<query>"` — implemented as one extra
      `FAutocompleteItem.item(value: query)` appended after the filtered
      matches when `query.trim().isNotEmpty` and no exact case-insensitive match
      exists in the merged list.
    - Selection or free-text entry writes to the same underlying
      `_payerController` (persists as `payor_name`). No `paid_to_user_id` /
      `paid_to_name` is edited in income mode.
  - **Related to Gig (optional)** — `AppDropdown<String?>`.
    - Items: `null` ("Not linked") + one item per `Gig` from
      `gigProvider.state.allGigs`, format = `"$name — ${DateFormat('MMM d, yyyy').format(date)}"`,
      sorted by `date` descending.
    - Selection writes to a new `_selectedGigId` field, persisted as `gig_id`.

- **Expense**:
  - **Paid to** — same `FAutocomplete.textBuilder` pattern as income "Payment
    from", also bound to `_payerController` → `payor_name` (this is the
    existing semantic inversion; kept unchanged).
  - **Paid by** — `AppDropdown<String?>` with the members + `Other` + the
    conditional free-text field. Same widget/behaviour as today at
    [lines 631–681](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L631-L681),
    just moved into this section. Persists to `paid_to_user_id` / `paid_to_name`.
  - **Related to Gig (optional)** — same `AppDropdown<String?>` as income.

**Section: Distribution** (income only)

- **1099 Expected** switch row (existing `AppSwitch`, moved into this card).
- **Disburse to Band** switch row (existing).
  - When ON: reveal the member split rows below (existing `AnimatedSize` block
    with per-member `CurrencyTextField` and short-name label preserved).
  - Each per-member `CurrencyTextField` gets a listener that recomputes the
    balance on every change (already wired via `_onDisbursementChanged` — see
    behaviour change below).
- **Deposit to Savings ($X.XX)** switch row (existing).
  - Label suffix `($<formatted savings total from widget.savingsTotalCents>)`
    stays as today.
  - When ON: reveal the `_depositToSavingsController` `CurrencyTextField` (as
    today) plus a small helper `Text` beneath it:
    `"Automatically calculated from remaining amount."` — only rendered when
    `_disburse` is also ON (i.e. savings is being fed by the split balancer),
    matching the mockup wording exactly.

**Auto-balance behavior (the new business logic)**

Change `_onDisbursementChanged` to:

```
totalDisbursed = sum(_splitControllers.values.cents)
remaining      = _amountController.cents - totalDisbursed

if _disburse and remaining > 0:
    _depositToSavingsController.cents = remaining
    if not _depositToSavings:
        _depositToSavings = true          // auto-enable the toggle
        (setState so the switch row + savings field animate in)
elif _disburse and remaining <= 0:
    // splits fully cover the amount; if savings was auto-enabled and non-zero, zero it out
    _depositToSavingsController.cents = 0
    (leave _depositToSavings alone — user may still want it on)
```

Guarantee at all times when `_disburse == true`:
`sum(splits) + depositToSavingsController.cents == _amountController.cents`
(or `sum(splits) == _amountController.cents` with savings = 0).

If the user directly toggles Deposit to Savings OFF while Disburse is ON and
there IS a positive remainder, respect the toggle: `_depositToSavingsController.cents
= 0` (any remainder is silently unallocated until the user rebalances). This
matches the current toggle-off semantics and avoids fighting the user.

**Section: Reimbursement** (expense only)

- **Reimbursed by Band** switch row (`AppSwitch`), bound to `_isReimbursed`.
  - When OFF: no extra rows.
  - When ON: reveal (`AnimatedSize`):
    - **Reimbursed on** — `OutlinedButton.icon` → `showAppDatePicker`, bound to
      `_reimbursedDate` (defaults to today when first switched on).
    - **Method** — `AppDropdown<String?>` with items:
      `null` ("Select method"), `"Zelle"`, `"Venmo"`, `"Cash"`, `"Check"`,
      `"Other"`. Bound to `_reimbursementMethod`.
    - **Method (other)** conditional `AppTextField`, only shown when
      `_reimbursementMethod == 'Other'`, bound to `_reimbursementMethodOtherController`.
      Placeholder: `"e.g., PayPal"`.
  - On save, if `_isReimbursed == false`, `reimbursedDate` and
    `reimbursementMethod` both go to `null`. If `_isReimbursed == true` and
    `_reimbursementMethod == 'Other'`, the persisted `reimbursement_method`
    value is the trimmed contents of the "other" text field (or `null` if
    empty — see DB constraint choice below).

**Section: Notes** (both income and expense)

- Single `AppTextField(maxLines: null)` bound to a renamed `_notesController`
  (currently `_descriptionController` — same underlying column
  `description`; UI label changes to "Notes", placeholder `"Add any extra
  context…"`).

Wait — the "Short description" in the About section already uses the
`description` column. There is only one `description` column; the current
drawer uses it for the short blurb. The redesign per Tony's spec has TWO
narrative fields — "Short description" (About) and "Notes" (final section) —
but the DB only supports one. Two viable reads:

1. **The "Short description" IS the notes field, just relocated / restyled.**
   The mockups show either short description OR notes filled in, never both —
   e.g., screenshot 2 ("Edit Income") shows Short description = "Banana Stand
   merch sales" AND Notes = "Banana Stand merch sales at Riverside Tavern." So
   BOTH are shown as separate values, ruling out this read.
2. **Two separate columns.** Requires a schema addition.

Given Tony wrote "the underlying transaction data model / database schema is
not expected to change unless the plan determines new fields are genuinely
required," and screenshots #2 and #3 both show BOTH fields with different
content — this IS a genuine schema requirement.

**Decision (recorded here, not a silent choice)**: add a second nullable column
`notes TEXT NULL` alongside the existing `description` column. `description`
keeps its current role (the "Short description" one-liner). `notes` is the new
long-form notes field. Both nullable. `notes` is not covered by any existing
constraint. This keeps the migration additive and the existing code path
(details view, PDF export, reports) unaffected until they choose to display
`notes`.

### Sticky footer (bottom-anchored, uses existing `SheetFooter`)

- **Create mode**: `SheetFooter(primaryLabel: 'Add Transaction', onPrimary:
  save, onCancel: pop)`.
- **Edit mode**: `SheetFooter(primaryLabel: 'Save', onPrimary: save, onCancel:
  pop, destructiveLabel: 'Delete Income' | 'Delete Expense', onDestructive:
  handleDelete)` — `SheetFooter` already renders the destructive button as a
  separate full-width row above the primary/cancel row (see
  [sheet_footer.dart lines 105–124](lib/components/ui/sheet_footer.dart#L105-L124)).

### Container / layout

Match `EventEditorDrawer.build`:
`Container(height: MediaQuery.of(context).size.height, decoration:
BoxDecoration(color: kEdSurface, border: Border.all(color: kEdCardBorder),
borderRadius: 14, boxShadow: [...]), child: Column([Expanded(SingleChildScrollView(padding:
16, child: body)), stickyFooter]))`.

`showAddFinancialEntrySheet` gains `useSafeArea: true` on the
`showModalBottomSheet` call (matches `EventEditorDrawer` invocation).

Wrap the whole widget in `FTheme(data: buildEventEditorTheme(), child: ...)`
so the transaction drawer inherits the same Forui theme scoping and switch
styling that the event editor uses — this is why `AppSwitch` and
`FAutocomplete` will render identically in both drawers.

## Database Impact

**Applies.** One additive migration.

**New file**: `supabase/migrations/<timestamp>_add_transaction_drawer_fields_to_financial_entries.sql`

```sql
-- Add reimbursement_method + notes columns for the redesigned transaction drawer.
ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS reimbursement_method TEXT,
  ADD COLUMN IF NOT EXISTS notes                TEXT;

-- Tighten the reimbursement consistency check so method can only be set when reimbursed.
ALTER TABLE public.financial_entries
  DROP CONSTRAINT IF EXISTS financial_entries_reimbursement_consistency;

ALTER TABLE public.financial_entries
  ADD CONSTRAINT financial_entries_reimbursement_consistency
  CHECK (
    (is_reimbursed = FALSE AND reimbursed_date IS NULL AND reimbursement_method IS NULL)
    OR
    (is_reimbursed = TRUE  AND reimbursed_date IS NOT NULL)
  );
```

Rules honoured:

- **RLS**: no change. The existing table-level policies (`financial_entries_select
  / insert / update / delete`, most recently rewritten in
  [migration 20260823120000](supabase/migrations/20260823120000_wrap_rls_auth_functions.sql#L453-L491))
  already cover any new columns on the table.
- **No new RPC**. Both new columns are writeable via the existing direct-write
  path already governed by RLS; no `SECURITY DEFINER` function is needed. There
  is no policy that queries `financial_entries` recursively, so no recursion
  risk added.
- **No `SECURITY DEFINER` function created**, so no `REVOKE ALL FROM PUBLIC,
  anon` or `GRANT EXECUTE ... TO authenticated` to add — but the migration
  file should still include a one-line comment noting "no security definer
  additions; RLS already covers new columns" so QA's SQL review is unambiguous.
- **Demo template provisioning RPC** at
  [migration 20260904120003 lines 335–355](supabase/migrations/20260904120003_provision_demo_session_rpc.sql#L335-L355):
  only clones a fixed subset of columns (`entry_type, category, amount_cents,
  is_income, description, entry_date, gig_id`). New nullable columns default
  to `NULL` on insert, so cloning silently drops them, which is the correct
  behaviour for the demo band (demo data doesn't currently include
  reimbursement or long-form notes). No RPC change required.
- **Nullable / safe rollback**: both new columns are nullable and the check
  constraint's untightened branch (`is_reimbursed = FALSE AND … IS NULL`)
  matches every existing row, so `ADD COLUMN` succeeds without a rewrite and
  `DROP COLUMN` cleanly rolls back with no data loss beyond values a user set
  after the migration ran.

## Flutter Architecture Changes

- **State management**: no change. Continue using the existing
  `FinancialsNotifier` (`Notifier` + `NotifierProvider`, per repo convention).
  No new provider is introduced. `contactsProvider` and `venuesProvider` are
  already `NotifierProvider`s.
- **Repositories**: extend the existing `FinancialEntryRepository.insertEntry`
  and `updateEntry` signatures — no new repository. The autocomplete reads via
  the existing `contactsProvider` / `venuesProvider` — no new fetch calls.
- **Widgets**: the redesigned drawer stays as a single private
  `_AddFinancialEntryBottomSheet` state widget inside the existing file. Break
  down INSIDE the file, not into new files, as `event_editor_drawer.dart` does:
  private `_SectionCard`, private `_buildAboutSection(...)`, private
  `_buildPaymentDetailsSection(...)`, etc. This keeps engineer diff manageable
  and matches the established pattern.
- **`_SectionCard`**: duplicate the ~30-line private class from
  `event_editor_drawer.dart` verbatim inside the new file. Extracting to a
  shared component would touch `event_editor_drawer.dart` (imports, tests) and
  is explicitly out of scope. Duplication cost is small; extraction can be a
  future dedicated feature if needed.
- **Init order**: n/a (no changes to app boot).
- **Platform parity**: n/a (single shared Flutter widget; no platform-specific
  branch; auth flow unchanged; Firebase / DeepLinkService untouched).

## Files to Create

1. `docs/features/transaction-drawer-redesign/ARCHITECT_PLAN.md` — this
   document (produced by Architect).
2. `supabase/migrations/<timestamp>_add_transaction_drawer_fields_to_financial_entries.sql`
   — as specified in **Database Impact**. Engineer picks a timestamp `>=
   20260909000000` (or whatever the current UTC timestamp resolves to on their
   machine) and after all currently-committed migrations.

## Files to Modify

1. **`lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`**
   (primary change — all sectioning, autocomplete, auto-balance, reimbursement,
   related-gig, sticky footer, header restructure).
   - Extend the `_SaveCallback` typedef with 4 new optional named params:
     `gigId`, `isReimbursed`, `reimbursedDate`, `reimbursementMethod`, `notes`.
     (5 new params — `notes` is the second narrative field.)
   - Extend `showAddFinancialEntrySheet(...)` doc comment accordingly.
   - Rewrite the `build()` body:
     - Full-height `Container` decorated to match `EventEditorDrawer` (kEdSurface, kEdCardBorder, radius 14, boxShadow).
     - `FTheme(data: buildEventEditorTheme(), child: ...)` wrapper.
     - Sticky header (`Row: Column[title, subtitle] | close IconButton`) with
       title mode-aware and subtitle create-mode-only.
     - `_SegmentedToggle` (existing widget, reused).
     - `Expanded(SingleChildScrollView(padding: 16, child: Column([about,
       paymentDetails, distribution?, reimbursement?, notes])))`.
     - Sticky `SheetFooter` with per-mode labels and destructive slot in edit
       mode.
   - Add `_selectedGigId`, `_isReimbursed`, `_reimbursedDate`,
     `_reimbursementMethod`, `_reimbursementMethodOtherController`,
     `_notesController` state fields (initialize from `initialEntry` in edit
     mode; default in add mode).
   - Modify `_onDisbursementChanged` to add the auto-enable-toggle behaviour
     described above.
   - Add per-member `_splitControllers` change listeners (already wired
     — the listener attach is at
     [line 258](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L258-L260)
     and is preserved).
   - Add helper `_buildAboutSection()`, `_buildPaymentDetailsSection()`,
     `_buildDistributionSection()`, `_buildReimbursementSection()`,
     `_buildNotesSection()` — all private methods on the state class. Add a
     private `_SectionCard` class at the bottom of the file (copy from
     `event_editor_drawer.dart`).
   - Add `_buildPaymentFromAutocomplete(BuildContext)` for the merged
     contacts+venues autocomplete widget (used for income "Payment from" AND
     expense "Paid to" — same widget, same underlying `_payerController`).
   - Add contact+venue load-if-empty in `initState`: `Future.microtask(() { if
     (contactsProvider.state.contacts.isEmpty) load; same for venues; });` —
     gated behind `activeBandIdProvider`.
   - In `_save()`: pass through the 5 new fields; for **income edit mode**,
     preserve `initialEntry!.paidToUserId` and `initialEntry!.paidToName`
     unchanged (do not null them). For **income create mode**, pass `null` for
     both.
   - Add a friendly-error guard: if `_selectedTypeName == 'Gig Pay'` AND
     `_selectedGigId != null`, `_save` catches the expected `PostgrestException`
     from the `uniq_gig_pay_entry` violation and reroutes it to a
     `showErrorSnackBar` with copy `"This gig already has a Gig Pay entry.
     Open the gig to edit it instead."` — do NOT preflight-query for a
     duplicate (that's a race).
   - Change `showAddFinancialEntrySheet` to pass `useSafeArea: true` to
     `showModalBottomSheet` (matches `EventEditorDrawer`).

2. **`lib/features/financials/financials_controller.dart`**
   - Extend `FinancialsNotifier.addEntry(...)` and `updateEntry(...)` with 5
     new optional named params: `String? gigId`, `bool? isReimbursed`,
     `DateTime? reimbursedDate`, `String? reimbursementMethod`, `String? notes`.
   - Pass them through to the repository. No state-shape change.

3. **`lib/features/financials/financial_entry_repository.dart`**
   - Extend `insertEntry(...)` and `updateEntry(...)` with the same 5 params.
   - Add corresponding entries to both payload maps:
     `'gig_id': gigId, 'is_reimbursed': isReimbursed ?? false, 'reimbursed_date':
     reimbursedDate?.toIso8601String().split('T').first, 'reimbursement_method':
     (isReimbursed ?? false) ? reimbursementMethod : null, 'notes': notes?.isEmpty
     == true ? null : notes`.
   - Do NOT touch the gig-linked helpers `insertGigExpenseEntry` /
     `updateGigExpenseEntry` / `upsertGigPayEntry` — those are called from the
     event editor and Gig Pay bottom sheet, which are off-limits here. If Tony
     later wants those to gain reimbursement_method too, that's a follow-up.

4. **`lib/features/financials/models/financial_entry.dart`**
   - Add `final String? reimbursementMethod;` and `final String? notes;`
     fields.
   - Add both to the constructor (as optional named), `fromJson` (with
     `json['reimbursement_method'] as String?` / `json['notes'] as String?`),
     and `toJson`.

5. **`lib/features/financials/financials_screen.dart`**
   - Update the `showAddFinancialEntrySheet` call at line 47 to unpack and
     forward the 5 new save-callback params to `notifier.addEntry(...)`.

6. **`lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`**
   - Update the `showAddFinancialEntrySheet` call at line 179 to unpack and
     forward the 5 new save-callback params to `notifier.updateEntry(...)`.
   - **Do NOT** re-lay-out the details view itself — Tony asked only for the
     ADD/EDIT drawer to be redesigned. Details view labelling inconsistencies
     (`payerName` labelled "Payer" for both income/expense — see
     [details sheet lines 118–133](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart#L118-L133))
     are pre-existing and out of scope.

## Files Off-Limits

- **`lib/features/events/widgets/event_editor_drawer.dart`** — structural
  reference only. No modification. Extracting `_SectionCard` from here to a
  shared file expands scope and touches the event editor's test surface;
  don't.
- **`lib/features/events/widgets/gig_pay_bottom_sheet.dart`** and
  **`lib/features/events/widgets/gig_expense_subview.dart`** — parallel sheets
  used inside the event editor. They have their own layout, own state, own
  repository calls (`upsertGigPayEntry`, `insertGigExpenseEntry`), and are not
  in Tony's scope for this feature. Leave them alone even if you notice
  duplication.
- **`lib/features/contacts/**`** — the drawer READS `contactsProvider` /
  `venuesProvider` only. No mutation, no new provider, no repository change.
- **`lib/features/gigs/**`** — the drawer READS `gigProvider.state.allGigs`
  only. No mutation, no new provider.
- **`lib/features/members/**`** — unchanged. `membersProvider` is already
  passed in via `widget.members`.
- **`lib/app/theme/**`** — reuse `event_editor_theme.dart` (import + call
  `buildEventEditorTheme()`); no new theme, no token change.
- **All migration files except the one you create** — do not amend existing
  migrations even if you notice a cleaner factoring.
- **Anything under `web/`, `ios/`, `macos/`, `android/`, `linux/`, `windows/`,
  `marketing/`** — no platform-specific change.

## Change Budget

Per-file expected net line delta (lines added minus lines removed):

| File | Expected net delta |
|---|---|
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | +550 to +800 lines |
| `lib/features/financials/financials_controller.dart` | +20 to +30 lines |
| `lib/features/financials/financial_entry_repository.dart` | +25 to +40 lines |
| `lib/features/financials/models/financial_entry.dart` | +8 to +12 lines |
| `lib/features/financials/financials_screen.dart` | +8 to +12 lines |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | +8 to +12 lines |

- **Expected new files**: 2 (this `ARCHITECT_PLAN.md`; one SQL migration).
- **Expected new public classes / methods**: 0 (all additions are private
  helpers on `_AddFinancialEntryBottomSheetState`; the extended
  `_SaveCallback` typedef is still private to the sheet file).
- **Expected new dependencies**: 0.

If the drawer file grows beyond ~2200 lines, that's a signal to stop and
reconsider — but that would require the Engineer to be adding scaffolding
beyond what's specified here; the plan does not budget for a helper-file
extraction.

## System Impact Map

| System | Impact |
|---|---|
| Gigs | Unaffected. `gigProvider.state.allGigs` is read-only. No mutation of `gigs` table. |
| Rehearsals | Unaffected. |
| Setlists | Unaffected. |
| Members | Unaffected. `membersProvider` remains the sole source; only the display of the member picker inside expense mode moves into a section card. |
| Auth | Unaffected. No session, PKCE, magic link, or deep link code touched. |
| Routing | Unaffected. Drawer is a `showModalBottomSheet` — same entry points, same navigation. |
| Notifications | Unaffected. No trigger, no navigation handler, no FCM code path touched. |
| Platforms | All (iOS, Android, macOS, Web). Behaviour identical across all four — no platform-conditional code introduced. |
| Financials | **Affected — the whole scope**: model gains 2 fields; repository gains 5 new columns in insert/update payloads; controller gains 5 new params; add/edit drawer restructured end to end; entry-details sheet gains 5 pass-through fields on its `showAddFinancialEntrySheet` invocation. Gig Pay bottom sheet and Gig Expense subview inside the event editor are NOT touched. |
| Contacts / Venues | **Read-only new consumer**: the drawer triggers `contactsProvider.load(bandId)` and `venuesProvider.load(bandId)` in `initState` if their state is empty. First-time load fetches the whole band's list (existing cached behaviour). No writes. |
| Supabase (DB) | **Affected**: additive migration on `public.financial_entries` (2 new nullable columns, 1 tightened check constraint). No RLS, RPC, trigger, or index change. |

## Regression Risk

**MEDIUM.**

Reasoning:

- **Not HIGH** because: no auth / session / routing / init-order / RLS / RPC
  touched; no `SECURITY DEFINER` function created; new columns are nullable
  and the tightened check constraint is satisfied by every existing row
  (`is_reimbursed = FALSE AND … IS NULL`); rollback is a clean `DROP COLUMN`.
- **Not LOW** because: the drawer is used across every band and both add /
  edit paths; the `_SaveCallback` signature widens, forcing both call sites in
  `financials_screen.dart` and `financial_entry_details_bottom_sheet.dart` to
  update in the same PR; auto-balance logic is genuinely new business logic
  where a bug produces silent incorrect financial data (worst case: total
  income ≠ splits + savings on save); `FAutocomplete` in Forui has a
  known-quirk history in this repo
  ([docs/features/forui-autocomplete-migration/](docs/features/forui-autocomplete-migration)),
  so wiring 2 new autocomplete instances carries incremental regression risk;
  existing income entries with `paid_to_user_id` / `paid_to_name` set will
  silently lose those values on edit-and-resave unless the "preserve on income
  edit" guard specified above is implemented.

Mitigations are in the Engineer Task Breakdown and Verification Plan.

## Engineer Task Breakdown

Execute in this order — later tasks depend on earlier ones. Each task is
atomic; commit after each if you want checkpoints, but the plan does not
require multiple commits.

1. **Migration.** Create
   `supabase/migrations/<timestamp>_add_transaction_drawer_fields_to_financial_entries.sql`
   exactly as spelled out in **Database Impact** (2 nullable columns, tightened
   check constraint, 1-line comment about "no security definer additions").
   Do NOT apply it to production. QA will apply it to an ephemeral DB.

2. **Model.** In
   `lib/features/financials/models/financial_entry.dart`, add
   `reimbursementMethod` and `notes` fields (both `String?`, optional in the
   constructor), and wire them into `fromJson` (keys
   `'reimbursement_method'`, `'notes'`) and `toJson`. Nothing else in the
   model changes.

3. **Repository.** In
   `lib/features/financials/financial_entry_repository.dart`, extend
   `insertEntry(...)` and `updateEntry(...)` with the 5 new params (`gigId,
   isReimbursed, reimbursedDate, reimbursementMethod, notes`). Add them to the
   payload map exactly as spelled out in **Files to Modify (3)**. Do NOT touch
   the 3 gig-linked helpers.

4. **Controller.** In
   `lib/features/financials/financials_controller.dart`, extend
   `FinancialsNotifier.addEntry(...)` and `updateEntry(...)` with the same 5
   new params and pass them through to the repository. State shape unchanged.

5. **Call site — `financials_screen.dart`.** In `_addEntry(...)`, extend the
   `onSave` callback destructuring to include the 5 new fields and forward
   them to `notifier.addEntry(...)`.

6. **Call site — `financial_entry_details_bottom_sheet.dart`.** Same
   extension at the `onSave` and `notifier.updateEntry` call in the Edit
   Entry footer action. Do NOT change any details-view labelling.

7. **Drawer rewrite — structure.** In
   `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`:
   - Widen the `_SaveCallback` typedef and the `_AddFinancialEntryBottomSheet`
     constructor to accept the new fields.
   - Replace the `build()` body with: full-height decorated `Container`
     matching `EventEditorDrawer`, wrapped in `FTheme(data:
     buildEventEditorTheme(), ...)`, containing a `Column` of
     `[stickyHeader, Expanded(SingleChildScrollView), SheetFooter]`.
   - Sticky header emits title + optional subtitle + close button, followed
     by the reused `_SegmentedToggle`.
   - Add private `_SectionCard` class (copy from `event_editor_drawer.dart`
     lines 3546–3580, no changes).
   - Change `showAddFinancialEntrySheet` to include `useSafeArea: true`.

8. **Drawer rewrite — About section.** Add `_buildAboutSection()` that
   emits: type pill row (reuse existing `_TypePillRow`), amount, date, short
   description. Placeholder text is income-aware as specified. Remove the
   visible "(optional)" wording from the short description label.

9. **Drawer rewrite — Payment Details section.** Add
   `_buildPaymentDetailsSection()`:
   - Load contacts + venues if empty (see step 12).
   - Build merged autocomplete list (contacts.name + venues.name, dedup by
     lowercased name, sort by name).
   - For income: emit "Payment from" `FAutocomplete.textBuilder` bound to
     `_payerController`, then "Related to Gig" `AppDropdown<String?>` bound
     to `_selectedGigId`.
   - For expense: emit "Paid to" (same autocomplete widget), then "Paid by"
     `AppDropdown<String?>` (existing member picker + "Other" + conditional
     free text — MOVE from current inline location, do not recreate), then
     "Related to Gig" dropdown.
   - Autocomplete suggestion list: contentBuilder returns `Row(name,
     Spacer, small tag "Contact" | "Venue")` cells, with an appended
     `Use "<query>"` cell when there is no case-insensitive exact match and
     `query.trim().isNotEmpty`. Selection or free-text writes to
     `_payerController.text`; no separate contact/venue-ID column is
     persisted.

10. **Drawer rewrite — Distribution section (income only).** Add
    `_buildDistributionSection()`:
    - 1099 Expected switch row.
    - Disburse to Band switch row + the existing member-split reveal.
    - Deposit to Savings switch row + the existing
      `_depositToSavingsController` reveal, with the mockup helper text
      `"Automatically calculated from remaining amount."` shown only when
      `_disburse && _depositToSavings` are both true.
    - Update `_onDisburseToggle` and each per-member split controller listener
      to invoke the new auto-balancer described in
      **Proposed Solution → Auto-balance behaviour**.
    - The auto-balancer's toggle-on side effect is inside `setState` so the
      switch animates in and the savings field reveals.

11. **Drawer rewrite — Reimbursement section (expense only).** Add
    `_buildReimbursementSection()`:
    - `AppSwitch` bound to `_isReimbursed` with label "Reimbursed by Band."
    - When ON: `AnimatedSize` reveals a date picker for `_reimbursedDate`
      (default `DateTime.now()` on first switch-on), a method
      `AppDropdown<String?>` bound to `_reimbursementMethod` with items
      `[null, Zelle, Venmo, Cash, Check, Other]`, and a conditional
      `AppTextField` for the "Other" free text bound to
      `_reimbursementMethodOtherController`.
    - Save-time: when `_isReimbursed == false`, both `reimbursedDate` and
      `reimbursementMethod` params to the callback are `null`. When
      `_isReimbursed == true`, `reimbursedDate` is the selected date; the
      `reimbursementMethod` string is either the picked value, or (when
      picker == "Other") the trimmed contents of the other-text controller,
      or `null` if the user picked nothing / left "Other" blank.

12. **Drawer rewrite — Notes section.** Add `_buildNotesSection()` — single
    `AppTextField(maxLines: null)` bound to `_notesController`.

13. **Init-time contact/venue load.** In `initState`, wrap in
    `Future.microtask` a check-then-load for both providers, gated by
    `activeBandIdProvider`. The drawer is a `Consumer` context (state class
    already extends `State`), so use a `ProviderContainer`-safe pattern: call
    `ProviderScope.containerOf(context).read(...)` inside a
    `WidgetsBinding.instance.addPostFrameCallback((_) { ... })`, or convert
    the state widget to `ConsumerStatefulWidget` / `ConsumerState` (this is
    the cleaner move — every recent redesign in this repo uses
    `ConsumerStatefulWidget`; see `EventEditorDrawer` at line 68).

14. **Init-time gig list.** Same as (13) for `gigProvider` — if `allGigs` is
    empty and the user has a band, trigger `gigProvider.refresh()` (the
    controller name for its reload). This is a NON-blocking secondary load;
    the dropdown just shows an empty list until the load completes.

15. **Save flow.** `_save()`:
    - Assemble the 5 new callback params:
      - `gigId: _selectedGigId`
      - `isReimbursed: !_isIncome ? _isReimbursed : null` (nullable on income
        save — do NOT force `false`, preserve existing value from
        `initialEntry` on income edit)
      - `reimbursedDate: !_isIncome && _isReimbursed ? _reimbursedDate :
        null`
      - `reimbursementMethod`: computed as per step 11
      - `notes`: `_notesController.text.trim()` or `null` if empty
    - **Income edit preservation**: when `_isIncome && widget.initialEntry !=
      null`, `paidToUserId` and `paidToName` passed to the callback are
      `widget.initialEntry!.paidToUserId` and `.paidToName` verbatim — NOT
      the redesigned drawer's controller state (which no longer edits them).
    - Wrap the `widget.onSave(...)` call in a `try/catch` that specifically
      catches `PostgrestException` where `code == '23505'` and message
      references `uniq_gig_pay_entry` — surface with the friendly copy from
      **Files to Modify (1)**.

16. **Header title/subtitle.** In the sticky header: title is
    `widget.initialEntry != null ? 'Edit Transaction' : 'Add Transaction'`.
    Subtitle only rendered when `widget.initialEntry == null`, text
    `'Track your band\'s income or expense.'`.

17. **Footer button labels.** In `_buildFixedBottomActions()`: primary label
    is `widget.initialEntry != null ? 'Save' : 'Add Transaction'`. Destructive
    slot uses existing pattern with copy `'Delete Income' | 'Delete Expense'`
    (matching mockup 3's "Delete Expense").

## Verification Plan

### Tier 1 — pre-deploy (before the migration is applied)

Executable by QA without a running app. These must be green before merge:

1. `flutter analyze` clean across all 6 modified files and the new SQL file
   (SQL isn't analyzed, but confirm it's syntactically valid via `psql -f`
   dry-parse if convenient — not required).
2. **New unit tests** in `test/features/financials/` (create the folder if
   needed):
   - `distribution_balancer_test.dart` — pure Dart tests over the balancer
     function extracted (if reasonable) OR called via a test-only public wrap.
     If extraction adds too much scaffolding, embed the tests directly against
     a lightweight harness that instantiates `CurrencyInputController`s and
     calls the listener. Cases:
     - `total = 250.00`, 6 members split evenly → per-member = $41.66, first
       gets $41.70 (remainder go-first pattern).
     - Reduce one member to $30.00 → `_depositToSavings` becomes `true`,
       savings = $11.66.
     - Reduce first member from $41.70 to $0.00 → savings = $41.70.
     - Toggle Deposit to Savings OFF while remainder is positive → savings
       goes to $0, `_disburse` stays true, splits unchanged. On the next
       split change with positive remainder, savings toggle re-auto-enables.
     - Zero total → all splits & savings = 0 regardless of toggles.
   - Add cases only for the actual behaviour changes; do NOT rewrite tests
     for behaviour that already exists.
3. **Widget test** in `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`
   (create if missing) verifying:
   - In add mode, title text `'Add Transaction'` and subtitle
     `"Track your band's income or expense."` both render.
   - In edit mode with a stub `FinancialEntry`, title text
     `'Edit Transaction'` renders and subtitle does NOT.
   - All 4 section titles (`'About'`, `'Payment Details'`, `'Distribution'` |
     `'Reimbursement'`, `'Notes'`) render for the respective income/expense
     modes.
   - Bottom `SheetFooter` renders `'Add Transaction'` (create) or `'Save'`
     (edit) as the primary label.
   - Reimbursement toggle in expense edit mode: turning it on reveals a
     "Reimbursed on" date row and a "Method" selector. Selecting "Other"
     reveals the free-text field.
4. **Existing** `flutter test` suite must still pass unchanged — QA runs the
   full test target once.

None of the Tier 1 checks call anything that requires the app to be running.

### Tier 2 — post-deploy checks (migration applied on ephemeral DB)

Executable by QA against an ephemeral Supabase instance with the migration
applied:

1. **Static SQL review** of the new migration file:
   - `reimbursement_method` and `notes` columns exist as `TEXT NULL`.
   - Check constraint `financial_entries_reimbursement_consistency` was
     dropped and re-added with the new 3-column form (verify by SQL:
     `SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname =
     'financial_entries_reimbursement_consistency'` — expected output contains
     both `reimbursement_method IS NULL` and `reimbursed_date IS NOT NULL`).
   - No new `SECURITY DEFINER` function was added (nothing to grant / revoke).
2. **Ephemeral-DB apply check** (SQL only, no app):
   - Insert an existing-schema-valid row without `reimbursement_method` or
     `notes` → succeeds (verify defaults are `NULL`).
   - Insert a row with `is_reimbursed = FALSE, reimbursement_method = 'Zelle'`
     → **fails** the check constraint (this is the tightened branch).
   - Insert a row with `is_reimbursed = TRUE, reimbursed_date = today,
     reimbursement_method = 'Zelle'` → succeeds.
   - Insert a row with `is_reimbursed = TRUE, reimbursed_date = today,
     reimbursement_method = NULL` → succeeds (method optional when reimbursed).
   - Rollback: `ALTER TABLE public.financial_entries DROP COLUMN
     reimbursement_method; DROP COLUMN notes;` succeeds and restores the
     original check constraint via a separate re-add (verify migration is
     reversible even if not literally reversed here). This test must roll back
     or clean up so the ephemeral DB is reusable.
3. **Guardrail**: this Tier 2 has no queries that hardcode production UUIDs;
   all inserts use freshly-generated test data.

### Owner-run manual QA punch list (Tony, at PR-test time)

QA hands this list to Tony verbatim; QA does not attempt to run it because it
requires a launched app. Each step numbered, each with an exact expected
result.

1. Open the app → Home → Financials. Tap "Add Entry" while Income mode is
   selected on the list.
   **Expected**: The drawer opens full-height. Header shows title
   `'Add Transaction'` (top-left) and subtitle
   `"Track your band's income or expense."` beneath it, with a close (X)
   button top-right. Below the header is the Income / Expense segmented pill
   (Income selected, rose fill). Below that, in scrollable body: three
   bordered `_SectionCard`s — **About**, **Payment Details**, **Distribution**
   (in that order, top to bottom). Sticky bottom bar shows `Cancel` (left
   text) and `Add Transaction` (right, rose fill).

2. In **Payment from**, type `Rive`.
   **Expected**: Autocomplete dropdown appears after the 2nd character showing
   your band's contacts and venues whose names contain `Rive`, each row
   labeled `Contact` or `Venue` on the right. The last row is
   `Use "Rive"`. Tapping any suggestion fills the field. Typing `xylophone`
   (no matches) shows just the `Use "xylophone"` free-text row.

3. Enter Amount `$250.00`, pick a Date, pick Type = "Merch Sale". Turn on
   **Disburse to Band**.
   **Expected**: Member split rows appear, amounts split evenly (with any
   remainder cents pushed onto the first member). If you have 6 members and
   $250.00, expect Buster B. → $41.70, others → $41.66 each (or your band's
   member order).

4. Change one member's amount from ~$41.66 down to `$30.00`.
   **Expected**: **Deposit to Savings** auto-toggles ON. Its label now reads
   `Deposit to Savings ($11.66)` (or however much the shortfall is). The
   Savings Amount field beneath shows `$11.66`. Helper text below the field
   reads `"Automatically calculated from remaining amount."`.

5. Change that same member's amount back up to $41.66.
   **Expected**: Savings Amount snaps back to `$0.00`. The Deposit to Savings
   toggle stays ON (user's manual state is respected) but its label subtotal
   is `($0.00)`. Note: this is fine — the switch stays where the user last
   left it.

6. Tap **Add Transaction**.
   **Expected**: Drawer closes, entry appears at the top of the list.
   Verified: the total on the entry equals sum(splits) + savings.

7. Tap the new entry to open its details sheet. Tap **Edit Entry**.
   **Expected**: The redesigned drawer reopens with header title
   `'Edit Transaction'` and **no** subtitle. Bottom bar shows `Cancel` (left),
   `Save` (right), and above them a full-width `Delete Income` destructive
   button.

8. Switch back to a fresh Add drawer, then switch the segmented control to
   **Expense**.
   **Expected**: The **Distribution** section disappears. In its place appears
   a **Reimbursement** section with a single "Reimbursed by Band" toggle
   (off). The **Payment Details** section now shows **Paid to** (autocomplete)
   first, then **Paid by** (member dropdown with "Other"), then **Related to
   Gig**.

9. Type `Jimm` in **Paid to** → verify same autocomplete behaviour as step 2.

10. Turn **Reimbursed by Band** ON.
    **Expected**: A **Reimbursed on** date row appears (default today) and a
    **Method** dropdown appears (default empty). Select `Other` — a free-text
    field appears below with placeholder `"e.g., PayPal"`.

11. Enter `PayPal` in the Other field, save the entry, reopen it in edit
    mode.
    **Expected**: The Reimbursement toggle is ON, the date is what you picked,
    the Method dropdown shows `Other`, and the free-text field shows
    `PayPal`.

12. In the Add drawer with Income mode, select Type `Gig Pay` AND link
    **Related to Gig** to a gig that already has a Gig Pay entry. Save.
    **Expected**: Error snackbar with copy `"This gig already has a Gig Pay
    entry. Open the gig to edit it instead."` The drawer stays open; the
    user can change the gig or the type.

## QA Regression Areas

Manually spot-check (owner-run at PR-test time — QA cannot):

1. **Gig Pay flow inside the event editor** (Gig Pay bottom sheet at
   `gig_pay_bottom_sheet.dart`) — still opens, saves, and updates the linked
   `financial_entries.gig_id` row correctly. Unchanged from today.
2. **Gig Expense sub-view inside the event editor**
   (`gig_expense_subview.dart`) — still opens, saves an expense linked to a
   gig, and the entry shows in Financials. Unchanged from today.
3. **Existing manual entries with `paid_to_user_id` set on income** —
   open one in edit mode via the new drawer, change the amount only, save.
   Re-open. Verify `paidToUserId` and `paidToName` are still set to what
   they were (they must not be nulled — this is the "income edit
   preservation" guard in Engineer Task 15).
4. **Financials list, PDF export, financial report screens** — the list
   and reports display the same entries as before. `notes` and
   `reimbursement_method` are not required to be surfaced anywhere else in
   this PR; verify they at least don't break existing rendering (they will
   just be `NULL` on all pre-migration entries).
5. **Contributor role** (`can_view_financials = true`,
   `can_create_financials = false`) — verify contributor still cannot see
   the Add button and cannot save from Edit mode. RLS + button-permission
   plumbing unchanged.
6. **Band switch** — switch active band, re-open Financials, re-open the
   drawer. Verify `contactsProvider` / `venuesProvider` / `gigProvider`
   suggestion lists all reflect the newly-active band (the existing
   `Notifier.build()` band-watching pattern handles this).

## Rollout Strategy

1. **Migration applied to staging first.** Apply `<timestamp>_add_transaction_drawer_fields_to_financial_entries.sql`
   to staging Supabase. Run the Tier 2 SQL apply check on staging.
2. **Flutter build → staging web.** Deploy the branch's web build to Vercel
   preview. Tony runs the owner punch list.
3. **Migration applied to production.** After staging punch list passes,
   apply the same migration to production. This is safe out of order relative
   to the client because both columns are nullable and the client tolerates
   `null` values on read (the old client just never wrote them; the new client
   reads a mix of `null` and set values).
4. **Client rollout — web first, then iOS / Android.** Standard order for this
   repo. There is no config change, no `--dart-define` change, no
   platform-specific rebuild required beyond the normal build pipeline.
5. **Rollback plan.**
   - Client: revert the PR; the old client ignores the new columns.
   - DB: `ALTER TABLE public.financial_entries DROP COLUMN reimbursement_method,
     DROP COLUMN notes;` plus reverting the check constraint to its pre-PR
     form. Users who set method/notes in the interim would lose those values;
     that's an acceptable tradeoff for a UI-driven rollback because the
     financial totals themselves (`amount_cents`, `disbursements`,
     `deposit_to_savings_cents`) are on unchanged columns.
6. **--dart-define / init order / platform parity**: no changes. This PR
   does not touch `RUNTIME_CONFIG.md` or `AI_DECISIONS.md`.

## Out of Scope

- **Refactoring the semantic inversion** where `payor_name` is labelled
  "Paid to" for expense and "Payment from" for income (existing quirk;
  Tony's spec preserves it verbatim in the mockup).
- **Extracting `_SectionCard` to a shared component** in `lib/components/ui/`
  — kept private-per-file, matching how `event_editor_drawer.dart` handles
  it.
- **Re-laying-out the details view sheet** (`financial_entry_details_bottom_sheet.dart`)
  or fixing its `payerName`-always-labelled-"Payer" quirk — Tony's request is
  scoped to the ADD/EDIT drawer only.
- **Surfacing `notes` in the details view / PDF export / reports** — those
  are consumers of the same column; if they should render `notes`, that's a
  follow-up feature. The data will be there once the migration is applied.
- **Adding `reimbursement_method` to the Gig-linked expense flow inside the
  event editor** (`gig_expense_subview.dart`) — parallel sheet, off-limits.
  If Tony wants the Gig-linked expense flow to also gain a Method picker,
  that's a separate, symmetric feature.
- **Making reimbursement Method a required field when the toggle is ON** —
  the spec doesn't say so; the DB constraint doesn't say so; leave method
  optional.
- **Preflight-querying for a duplicate Gig-Pay entry** before insert — race
  condition, and the DB UNIQUE index is the source of truth. Client just
  catches the friendly error.
- **Any change to the demo-provisioning RPC** to seed new column values —
  nullable columns default to `NULL`, which is correct for the demo data.
- **Any web-marketing, iOS/macOS/Android platform, or auth code change.**

---

# ADDENDUM — 2026-09-09 — Distribution: full-amount auto-fill + over-allocation validation

**This addendum begins here.** The plan above is unchanged and remains the
governing document for everything already implemented on
`feature/transaction-drawer-redesign` (branch confirmed, still the current
checked-out branch — no new branch, no merge-base check). This addendum
refines *only* the income-mode Distribution section behavior on top of the
existing sectioned redesign. Nothing above is invalidated.

## Feature Slug

`transaction-drawer-redesign` (unchanged)

## Feature Title

Redesign Add/Edit Transaction Drawer with Sectioned Layout (unchanged)

## Addendum Problem Summary

Two refinements to the Distribution card inside the redesigned drawer's income
mode:

1. **Auto-fill Deposit-to-Savings with the full transaction Amount when the
   user turns the toggle ON.** Today, turning Deposit to Savings ON while
   Disburse to Band is OFF leaves the Savings Amount field blank ($0.00);
   the user has to type the value in manually. Tony wants the field to
   auto-populate with the full transaction Amount in that case. When Disburse
   to Band is ON, the existing remainder-based auto-fill (savings absorbs
   `amount − sum(splits)`) must not regress.
2. **Prevent `sum(splits) + savings > amount` from ever being saved, and
   surface the violation inline on the specific field the user just edited.**
   Today, a user can type a split value or a Savings Amount that pushes the
   allocation total above the transaction Amount, and the drawer silently
   accepts it and lets Save proceed — producing a financially inconsistent
   record where the entry's parts sum to more than its whole.

## Addendum Root Cause

**Confidence: HIGH** (confirmed by reading the current
`add_financial_entry_bottom_sheet.dart` end-to-end — see specific line
citations below).

### Requirement 1 — why the current toggle-on doesn't fill full amount

The current Deposit-to-Savings switch handler at
[add_financial_entry_bottom_sheet.dart lines 1015–1030](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1015-L1030)
only auto-fills when Disburse is ON:

```dart
if (v && _disburse) {
  final totalDisbursed = _splitControllers.values
      .fold<int>(0, (sum, c) => sum + c.cents);
  final remaining = _amountController.cents - totalDisbursed;
  _depositToSavingsController.cents = remaining > 0 ? remaining : 0;
} else if (!v) {
  _depositToSavingsController.cents = 0;
}
```

The `else` branch (`v == true && !_disburse`) is intentionally empty in the
current code — so turning Savings ON while Disburse is OFF leaves the
controller at whatever value it already held (usually `0` for a fresh entry).

Similarly, `_onDisbursementChanged` at
[lines 371–386](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L371-L386)
early-returns when `!_disburse`, so the amount-listener path also never fills
savings in the disburse-off case.

### Requirement 2 — why over-allocation goes silently unvalidated

`_onDisbursementChanged` at
[lines 371–386](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L371-L386)
does the auto-balance for the Disburse-ON case, but its "over" branch just
sets savings to zero and returns:

```dart
} else {
  _depositToSavingsController.cents = 0;
}
```

It never checks whether `sum(splits) > amount` on its own (which is possible
when the user types a large value into a single split — the remainder goes
negative, savings snaps to 0, and splits alone still exceed amount). And
`_depositToSavingsController` has no change listener at all today (no
`addListener` call for it anywhere in `initState` — verified), so the user
typing a value into the Savings Amount field that alone exceeds amount
doesn't trigger any validation. The save gate at
[line 585](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L585)
is only `_amountController.cents > 0`. Result: `sum(splits) + savings` can
exceed `amount` and Save will happily submit it to the DB (which has no
CHECK constraint enforcing this invariant either — verified against
`supabase/migrations/20260601000000_create_financial_entries.sql`).

### Precedence rule for requirement 1 vs. the existing balancer

The two auto-fill paths (new toggle-based, existing remainder-based) collide
in this case: Disburse is ON, splits are populated (whether fully or
partially covering amount), and the user then manually turns Savings ON.
Filling with the full transaction Amount here would immediately violate
requirement 2. The correct behavior is to defer to the existing balancer's
current savings value (which is exactly `max(0, amount − sum(splits))` by
construction) so no self-inflicted violation ever occurs on a toggle-on.
This resolves cleanly into a single rule (spelled out below in
**Addendum Proposed Solution → Precedence for req 1**) with no need for
an explicit `_savingsSetByAutoBalancer` history flag.

### Blocking Save on validation error — chosen approach

This is a UX judgment call, but not one with two equally valid answers:
allowing Save while a distribution field is visibly errored would commit a
record where `sum(parts) > whole`. The original plan's own Regression Risk
section flagged exactly this scenario as the "worst-case bug" for this
feature (`"total income ≠ splits + savings on save"`). So Save must be
blocked. The two remaining sub-options are (a) disable the Save button while
any error is present, or (b) leave Save enabled but show an error snackbar
on attempted submit. The codebase's existing precedent (`enabled =
_amountController.cents > 0` on the same button, at
[line 585](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L585))
already gates Save on form validity via button-disable rather than
tap-then-error. Matching that precedent — disable Save — gives immediate
feedback and is consistent with the drawer's own established pattern. This
addendum uses approach (a).

## Existing System Analysis (delta from original)

Everything the original plan describes about the drawer's overall structure,
sectioning, autocomplete, reimbursement, and notes is unchanged. New /
relevant pieces for this addendum:

- **Distribution section's current handler wiring**:
  - `_amountController.addListener(_onDisbursementChanged)` in `initState`
    at
    [line 259](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L259).
    Fires on both user typing and any programmatic mutation of amount.
  - Per-member split controllers get
    `.addListener(_onDisbursementChanged)` inside `_populateSplits` at
    [line 348](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L348).
    Fires on both user typing AND programmatic writes inside
    `_populateSplits` itself (each `cents =` assignment during initial
    even-split populate triggers the listener once per member).
  - `_depositToSavingsController` has NO change listener wired.
- **`CurrencyTextField.onChanged`**: verified at
  [lib/shared/widgets/currency_input_field.dart lines 289–345](lib/shared/widgets/currency_input_field.dart#L289-L345).
  This callback is invoked from the internal text `_onChanged` path
  (line 337: `widget.onChanged?.call()`) which is fired only by the wrapped
  `AppTextField.onChanged` — user typing. Programmatic mutations of the
  controller (e.g., `_populateSplits` setting `cents = X`) reach
  `_syncFromController` at
  [line 322](lib/shared/widgets/currency_input_field.dart#L322), which does
  NOT invoke `widget.onChanged`. So `CurrencyTextField.onChanged` is a
  true user-only edit signal — the cleanest way to attribute an error to
  "the specific field the user just edited" without a helper state flag.
- **Inline-error convention in the codebase** (chosen from the two
  patterns Tony flagged):
  - `FAutocomplete` uses `forceErrorText` (see
    [gig_form_fields.dart line 1002](lib/features/events/widgets/gig_form_fields.dart#L1002)).
    Not applicable here — the fields in question are `CurrencyTextField`, not
    `FAutocomplete`.
  - `AppTextField`-backed fields render a sibling `Text` widget beneath the
    field, styled `AppTextStyles.footnote.copyWith(color: AppColors.error)`.
    Canonical example at
    [event_editor_helpers.dart lines 89–96](lib/features/events/widgets/event_editor_helpers.dart#L89-L96):
    ```dart
    if (error != null) ...[
      const SizedBox(height: 4),
      Text(
        error!,
        style: AppTextStyles.footnote.copyWith(color: AppColors.error),
      ),
    ],
    ```
    This addendum uses that pattern.
  - Note: `AppTextField` does NOT currently expose `forceErrorText` /
    `errorText` (verified —
    [lib/components/ui/app_text_field.dart lines 15–125](lib/components/ui/app_text_field.dart#L15-L125)).
    And `CurrencyTextField` (which internally renders `AppTextField`) does not
    expose one either. Extending either widget with a new error prop is
    explicitly out of scope for this addendum — it would touch every callsite
    across the app. Sibling-`Text`-below is the compatible, non-invasive
    choice and matches the established codebase convention.
- **Existing helper text under the Savings Amount field** at
  [lines 1044–1057](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1044-L1057):
  ```dart
  if (_disburse) ...[
    const SizedBox(height: Spacing.space4),
    Text(
      'Automatically calculated from remaining amount.',
      style: AppTextStyles.footnote
          .copyWith(color: context.colors.textMuted),
    ),
  ],
  ```
  When the field is in an error state, the error message replaces this
  helper text (errors take precedence over informational hints — standard
  Material convention).

## Addendum Proposed Solution

### State delta (new fields on `_AddFinancialEntryBottomSheetState`)

Add exactly one new state field:

```dart
Map<String, String> _distributionErrors = const {};
```

Keys are field IDs:

- `'savings'` — the Savings Amount field.
- `'split:<userId>'` — one specific member's split field.

Values are the human-readable error message (single string used for both,
see **Copy** below). No other state fields, flags, or controllers added.

### Precedence for req 1 (auto-fill on Deposit-to-Savings ON)

Inside the existing Deposit-to-Savings `AppSwitch.onChanged` handler at
[lines 1010–1032](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1010-L1032),
replace the current body with the following precedence, run inside a single
`setState`:

```
if v == false:
    _depositToSavingsController.cents = 0
else if _disburse:
    totalDisbursed = sum(_splitControllers.values.cents)
    remaining      = _amountController.cents - totalDisbursed
    _depositToSavingsController.cents = remaining > 0 ? remaining : 0
else:
    _depositToSavingsController.cents = _amountController.cents
```

Cases this resolves — enumerate them explicitly so Engineer and QA can
match tests to lines:

| State when user taps Savings ON | Result | Rationale |
|---|---|---|
| Disburse OFF, amount = $200, savings = $0 | savings = $200 | New req 1 — full amount. |
| Disburse OFF, amount = $200, savings = $50 (edit-mode entry pre-loaded) | not applicable — toggle is already ON on load; this handler doesn't fire | Precedence only applies on transitions of the toggle. |
| Disburse OFF, amount = $200, savings was $50 then user turned OFF then ON | savings = $200 | Toggle-OFF cleared savings to 0. Re-ON fires new precedence, Disburse still OFF → full amount. |
| Disburse ON, splits sum to $200 = amount, savings = $0 | savings = $0 | Remaining = 0. Filling full amount would immediately violate req 2; fill 0 instead. Answers Tony's stated question. |
| Disburse ON, splits sum to $170, amount = $200, savings = $0 | savings = $30 | Existing remainder behavior; preserved. |
| Disburse ON, splits sum to $170, amount = $200, savings already = $30 (auto-set by balancer, toggle also auto-ON) | not applicable — toggle is already ON | Handler doesn't fire on this state. |
| Amount = $0 | savings = $0 | Trivial edge case — no-op. |

This rule NEVER produces a state where `sum(splits) + savings > amount`
purely from a toggle press. That's the design guarantee.

The `_onDisbursementChanged` path (auto-set savings from a positive remainder
when the user reduces a split) is **preserved verbatim** — the addendum only
touches the switch's `onChanged` body. The regression guard in the
Verification Plan below explicitly tests that this existing behavior still
works.

### Validation for req 2 (over-allocation errors + Save gate)

Add a single new instance method:

```dart
void _syncDistributionState({String? changedFieldKey}) {
  // 1. Auto-balance side effect (unchanged from existing _onDisbursementChanged
  //    body when _disburse is true).
  if (_disburse) {
    final totalDisbursed = _splitControllers.values
        .fold<int>(0, (sum, c) => sum + c.cents);
    final remaining = _amountController.cents - totalDisbursed;
    if (remaining > 0) {
      _depositToSavingsController.cents = remaining;
      if (!_depositToSavings) {
        _depositToSavings = true; // caller wraps in setState — see wiring
      }
    } else {
      _depositToSavingsController.cents = 0;
    }
  }

  // 2. Recompute error state.
  final total = _amountController.cents;
  final savingsCents =
      _depositToSavings ? _depositToSavingsController.cents : 0;
  final totalSplits = _disburse
      ? _splitControllers.values.fold<int>(0, (s, c) => s + c.cents)
      : 0;
  final overBy = (totalSplits + savingsCents) - total;

  Map<String, String> next = const {};
  if (overBy > 0) {
    String? attributeTo = changedFieldKey;
    attributeTo ??= _pickFallbackErrorAttribution();
    if (attributeTo != null) {
      next = {attributeTo: 'Exceeds remaining balance'};
    }
  }
  if (!mapEquals(next, _distributionErrors)) {
    setState(() => _distributionErrors = next);
  }
}

String? _pickFallbackErrorAttribution() {
  // Used when the trigger has no natural field to attribute to (Amount
  // change, Disburse toggle, income/expense switch). Prefers Savings when
  // it's the only enabled destination; otherwise flags the largest non-zero
  // split (most likely to be user-set high).
  if (_depositToSavings && _depositToSavingsController.cents > 0) {
    return 'savings';
  }
  if (_disburse) {
    String? key;
    int max = 0;
    for (final entry in _splitControllers.entries) {
      if (entry.value.cents > max) {
        max = entry.value.cents;
        key = 'split:${entry.key}';
      }
    }
    return key;
  }
  return null;
}
```

**Copy**: the message is exactly `'Exceeds remaining balance'` — matches
Tony's suggested wording, matches the codebase's existing terse style
(`'Location is required'`, `'City is required'` from
[event_editor_drawer.dart lines 1837–1865](lib/features/events/widgets/event_editor_drawer.dart#L1837-L1865)),
and avoids currency formatting inside the plan (no need to compute-and-render
"by \$X.XX" — the user knows their number from the field itself).

### Listener / callback rewiring (the specific edits inside the file)

The addendum flips the split and savings edit-detection from
`ValueNotifier.addListener` (fires on programmatic mutation too) to
`CurrencyTextField.onChanged` (user-only). This lets attribution to
`'split:<userId>'` or `'savings'` be perfectly accurate without needing a
`_lastEditedFieldKey` state field or a `_isProgrammaticFill` guard flag.

Specific edits inside `_AddFinancialEntryBottomSheetState`:

1. **`initState`** — replace
   `_amountController.addListener(_onDisbursementChanged)` at
   [line 259](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L259)
   with
   `_amountController.addListener(_onAmountChanged)` where the new
   `void _onAmountChanged() => _syncDistributionState(changedFieldKey: null);`.
   Amount changes attribute via fallback (never to the Amount field itself).

2. **`initState`** — after all controllers are initialized, seed the initial
   error map directly (no setState during initState):
   `_distributionErrors = _computeInitialDistributionErrors();`
   where `_computeInitialDistributionErrors()` is a pure function that runs
   the step-2-only body of `_syncDistributionState` (no auto-balance side
   effect, no setState) and returns the resulting map. This ensures
   edit-mode entries that were somehow saved over-allocated (pre-addendum
   data) show the error on first render and Save is disabled until fixed.

3. **`dispose`** — remove the
   `c.removeListener(_onDisbursementChanged)` line at
   [line 269](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L269-L272)
   (the per-member split loop) — no longer needed since the split
   controllers no longer have per-listener attachments. `c.dispose()`
   still fires and cleans up the underlying `ValueNotifier`. Also update the
   `_amountController.removeListener` line at
   [line 265](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L265)
   to reference `_onAmountChanged` instead of `_onDisbursementChanged`.

4. **`_populateSplits`** — remove the
   `_splitControllers[m.userId]!.addListener(_onDisbursementChanged)`
   at [line 348](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L348).
   The split controllers no longer need a listener — the split field's
   `CurrencyTextField.onChanged` is now the sole trigger. Also delete the
   `isNew` local and its guard block since it existed only to gate that
   `addListener` call — trivial cleanup.

5. **`_onDisburseToggle`** — at the end (after the existing setState body),
   append a single call: `_syncDistributionState(changedFieldKey: null);`.
   This handles the case where a user toggles Disburse ON with a stale
   savings value already sitting on the field (rare but possible via
   edit-mode). Fallback attribution picks whichever field is now over.

6. **`_onDisbursementChanged`** — remove entirely. Its body is fully
   subsumed by `_syncDistributionState` (which also does validation).
   Every call site of `_onDisbursementChanged` in the file is replaced
   with the appropriate `_syncDistributionState(...)` call per the wiring
   table below.

7. **`_setIsIncome`** — inside the existing setState body, add
   `_distributionErrors = const {};` alongside the existing clears (of
   `_disburse`, `_depositToSavings`, etc.) that already happen when
   switching to expense mode. Expense mode has no distribution section, so
   any prior errors are irrelevant.

8. **Per-member split's `CurrencyTextField`** in `_buildDistributionSection`
   at [lines 970–984](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L970-L984)
   (the split-reveal loop) — add
   `onChanged: () => _syncDistributionState(changedFieldKey: 'split:${member.userId}')`.
   User typing into a split now attributes any resulting violation to
   that specific member.

9. **Savings Amount `CurrencyTextField`** at
   [lines 1035–1039](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1035-L1039)
   — add
   `onChanged: () => _syncDistributionState(changedFieldKey: 'savings')`.
   User typing into Savings attributes any resulting violation to Savings.

10. **Deposit-to-Savings `AppSwitch.onChanged`** at
    [lines 1010–1032](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1010-L1032)
    — replace the body with the precedence table in
    **Addendum Proposed Solution → Precedence for req 1** above, wrapped in
    a single setState. After the setState, call
    `_syncDistributionState(changedFieldKey: null);`. Fallback attribution
    kicks in only if the newly-filled value plus splits somehow overshoots
    amount — which the precedence rule guarantees won't happen — so in
    practice this call just clears any lingering error.

### Save button gating

Change the `enabled` computation in `_buildFixedBottomActions` at
[line 585](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L585)
from:

```dart
final enabled = _amountController.cents > 0;
```

to:

```dart
final enabled =
    _amountController.cents > 0 && _distributionErrors.isEmpty;
```

That's it — 1-line change. `SheetFooter` already renders the primary as
disabled when `onPrimary` is null, which is the existing null-guard pattern
from the same widget (`onPrimary: enabled ? _save : null`).

### Inline error render

Two locations in `_buildDistributionSection` need the sibling-`Text` render:

- **Per-member split row** at
  [lines 963–986](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L963-L986)
  — wrap the current `Row(children: [name, spacer, CurrencyTextField])` in
  a `Column`, adding beneath it (only when
  `_distributionErrors['split:${member.userId}'] != null`) a second `Row`
  that mirrors the layout with an empty `Expanded` on the left (mirroring
  the member-name column) and an `Expanded(child: Text(errorMsg, style:
  AppTextStyles.footnote.copyWith(color: AppColors.error)))` on the right
  (aligned under the CurrencyTextField column). Insert a `SizedBox(height:
  4)` between the row and the error line to match the visual spacing
  used at
  [event_editor_helpers.dart line 90](lib/features/events/widgets/event_editor_helpers.dart#L90).
- **Savings Amount field** at
  [lines 1034–1057](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1034-L1057)
  — change the current `if (_disburse) ...[helperText]` to a
  precedence-ordered structure:
  ```
  if (_distributionErrors['savings'] != null) ...[
    SizedBox(height: 4),
    Text('Exceeds remaining balance',
        style: AppTextStyles.footnote.copyWith(color: AppColors.error)),
  ] else if (_disburse) ...[
    SizedBox(height: Spacing.space4),
    Text('Automatically calculated from remaining amount.',
        style: AppTextStyles.footnote.copyWith(color: context.colors.textMuted)),
  ],
  ```
  Error takes precedence over the helper (standard Material convention).

Neither `AppTextField`, `CurrencyTextField`, nor `AppSwitch` is modified —
the error is rendered strictly as a sibling `Text` below the field, matching
the existing convention.

## Database Impact

**Not applicable.** The addendum has no DB changes:

- No new columns.
- No new RPCs, `SECURITY DEFINER` functions, RLS policies, or triggers.
- The original addendum-referenced migration
  (`supabase/migrations/20260909000000_add_transaction_drawer_fields_to_financial_entries.sql`)
  is unchanged.
- No CHECK constraint added for `sum(splits) + savings <= amount` — the
  disbursement splits are stored in a separate `financial_entry_disbursements`
  table (per the original plan's read of the schema; not touched here) so a
  DB-level cross-table CHECK isn't ergonomic, and the client-side validation
  is now authoritative for this invariant. Save is gated so a user can't
  submit a violation regardless. If Tony later wants a defense-in-depth DB
  check, that's a separate targeted migration outside this addendum's scope.

## Flutter Architecture Changes

**None.** Same `Notifier` + `NotifierProvider` shape, same repository, same
model, same call sites. Everything lives inside the existing
`_AddFinancialEntryBottomSheetState`.

## Files to Create

None.

## Files to Modify

1. **`lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`**
   (the only source file this addendum touches) —
   - Add `_distributionErrors` state field.
   - Add `_syncDistributionState({String? changedFieldKey})` method.
   - Add `_pickFallbackErrorAttribution()` helper method.
   - Add `_onAmountChanged()` wrapper method for the amount listener.
   - Add `_computeInitialDistributionErrors()` pure helper for initState seed.
   - Remove `_onDisbursementChanged` (subsumed).
   - Rewire `_amountController.addListener` to `_onAmountChanged`.
   - Remove per-split `addListener` inside `_populateSplits` and the
     matching `removeListener` inside `dispose`.
   - Add `onChanged: () => _syncDistributionState(changedFieldKey:
     'split:${member.userId}')` to each per-member split `CurrencyTextField`.
   - Add `onChanged: () => _syncDistributionState(changedFieldKey: 'savings')`
     to the Savings Amount `CurrencyTextField`.
   - Replace the Deposit-to-Savings switch's `onChanged` body with the new
     precedence rule + a trailing `_syncDistributionState(changedFieldKey:
     null)`.
   - Append `_syncDistributionState(changedFieldKey: null)` at the end of
     `_onDisburseToggle`.
   - Clear `_distributionErrors = const {}` inside `_setIsIncome`'s
     income→expense branch.
   - Add the inline-error `Text` render under each per-member split row and
     under the Savings Amount field (with helper-text precedence).
   - Update the Save button's `enabled` computation to include
     `_distributionErrors.isEmpty`.

2. **`test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`**
   (existing test file — extend, don't rewrite; add new `group('distribution
   auto-fill and validation', () { ... })` block).

Note: **no other file is modified.** In particular:

- **Not modified**: `AppTextField`, `CurrencyTextField`, `AppSwitch`,
  `SheetFooter`, `event_editor_theme.dart`, any theme file, any other
  financials widget or controller or repository, any model, any migration,
  any platform folder.

## Files Off-Limits

Same as the original plan — plus these explicitly for the addendum:

- **`lib/components/ui/app_text_field.dart`** — do NOT add a `forceErrorText`
  or `errorText` prop. Every callsite would need updating; regression
  surface is huge. Use sibling `Text` widgets under the field per the
  established codebase convention.
- **`lib/shared/widgets/currency_input_field.dart`** — do NOT modify
  `CurrencyTextField` to add an error prop. Same reasoning.
- **`lib/features/financials/financials_controller.dart`,
  `.../financial_entry_repository.dart`,
  `.../models/financial_entry.dart`,
  `.../financials_screen.dart`,
  `.../widgets/financial_entry_details_bottom_sheet.dart`** — no data-shape
  change. All of these were touched by the original plan; nothing new here.
- **Any migration file** — no DB change in this addendum.

## Change Budget

Delta from the current in-flight branch, single-file:

| File | Expected net delta |
|---|---|
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | +80 to +120 lines |
| `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart` | +100 to +160 lines (7 new tests) |

- **Expected new files**: 0.
- **Expected new public classes / methods**: 0. All new methods
  (`_syncDistributionState`, `_pickFallbackErrorAttribution`,
  `_onAmountChanged`, `_computeInitialDistributionErrors`) are private
  instance members on the existing `_AddFinancialEntryBottomSheetState`.
- **Expected new dependencies**: 0.

If the drawer file grows by more than ~150 net lines against this addendum,
that's a signal Engineer is doing more than what's specified — stop and
reconsider.

## System Impact Map

| System | Impact |
|---|---|
| Gigs, Rehearsals, Setlists, Members, Auth, Routing, Notifications, Contacts / Venues | **Unaffected.** |
| Platforms (iOS, Android, macOS, Web) | All four, behavior identical. No platform-conditional code. No init-order change. Firebase / DeepLinkService unchanged. |
| Financials — save flow | Save is now additionally gated on `_distributionErrors.isEmpty`. Every existing save that would have been allowed AND was valid (`sum(splits) + savings <= amount`) is still allowed. Only previously-invalid saves are newly blocked — which is the point. |
| Financials — read / list / details / PDF / reports | **Unaffected.** No model, repository, or column changes. |
| Supabase (DB) | **Unaffected.** No migration, no RPC, no RLS, no CHECK. |

## Regression Risk

**LOW.**

Reasoning:

- No auth, session, routing, init-order, RLS, RPC, migration, or platform
  code touched.
- No model, repository, controller, or provider shape change.
- Purely local ephemeral widget state (one new `Map<String, String>` field
  and a handful of private methods on a single state class).
- The existing "reduce a split → savings auto-fills the remainder AND
  Deposit-to-Savings auto-enables" behavior is preserved verbatim inside
  `_syncDistributionState`'s auto-balance step, and covered by an explicit
  regression test in the Verification Plan below.
- The listener→onChanged migration is a straight swap: split and savings
  controllers currently trigger validation-adjacent code on every mutation
  (including programmatic ones); after the change they only trigger it on
  user typing. The removed programmatic triggers were incidental artifacts
  of the old wiring (each `_populateSplits` write fired the listener
  redundantly N times per Disburse toggle) — no external caller depends on
  them.
- Save-gate widening (blocking on distribution errors) only tightens the
  existing gate — cannot block previously-blockable saves.

## Engineer Task Breakdown

Execute in order. Each task is atomic; a single commit at the end is fine.

1. **State field**: add `Map<String, String> _distributionErrors = const {};`
   to `_AddFinancialEntryBottomSheetState`, alongside the existing
   `_disburse` / `_depositToSavings` bool fields.

2. **Helper methods**: add (as private instance methods on the state class)
   `_computeInitialDistributionErrors()` (pure — no setState),
   `_pickFallbackErrorAttribution()`, `_syncDistributionState({String?
   changedFieldKey})`, and `_onAmountChanged()`. Bodies exactly as spelled
   out in **Addendum Proposed Solution → Validation for req 2**. `mapEquals`
   is available via `package:flutter/foundation.dart` — add the import if
   not already present (it is not — verified).

3. **Remove `_onDisbursementChanged`**: delete the method entirely from the
   state class.

4. **`initState` rewiring**:
   - Change `_amountController.addListener(_onDisbursementChanged)` to
     `_amountController.addListener(_onAmountChanged)`.
   - After every other initialization in `initState` (right before the
     `Future.microtask` block that loads contacts/venues/gigs), seed
     `_distributionErrors = _computeInitialDistributionErrors();` — direct
     assignment, no setState.

5. **`dispose` rewiring**:
   - Change `_amountController.removeListener(_onDisbursementChanged)` to
     `_amountController.removeListener(_onAmountChanged)`.
   - Remove the `c.removeListener(_onDisbursementChanged);` line inside the
     per-split loop. `c.dispose()` remains.

6. **`_populateSplits` cleanup**:
   - Remove the `final isNew = !_splitControllers.containsKey(m.userId);`
     line and the `if (isNew) { _splitControllers[m.userId]!.addListener(...);
     }` block. `_splitControllers.putIfAbsent(...)` remains, as does the
     value assignment `_splitControllers[m.userId]!.cents = i == 0 ?
     perMember + remainder : perMember;`.

7. **`_onDisburseToggle` addendum call**: at the very end (after the existing
   setState body), add a single line: `_syncDistributionState(changedFieldKey:
   null);`.

8. **`_setIsIncome` cleanup addition**: inside the existing setState body,
   in the same location where `_disburse = false;` and `_depositToSavings =
   false;` happen on income→expense, add `_distributionErrors = const {};`.

9. **Split `CurrencyTextField` `onChanged`**: inside
   `_buildDistributionSection`'s per-member `Column`/`Row` builder (the
   `.map((member) { ... })` region), add
   `onChanged: () => _syncDistributionState(changedFieldKey: 'split:${member.userId}'),`
   to the `CurrencyTextField(...)` invocation. The `label: ''` and
   `clearOnFocus: true` args are preserved.

10. **Savings `CurrencyTextField` `onChanged`**: add
    `onChanged: () => _syncDistributionState(changedFieldKey: 'savings'),`
    to the `CurrencyTextField` inside the `AnimatedSize` block bound to
    `_depositToSavingsController`. The `label: 'Savings Amount'` and
    `clearOnFocus: true` args are preserved.

11. **Deposit-to-Savings `AppSwitch.onChanged` body**: replace with the
    precedence rule from **Addendum Proposed Solution → Precedence for req
    1**, wrapped in setState. After the setState, add
    `_syncDistributionState(changedFieldKey: null);`.

12. **Split row error render**: convert each per-member split's `Row` to a
    `Column` whose first child is the existing `Row(...)` and whose second
    (conditional) child is an aligned error `Row`:

    ```dart
    if (_distributionErrors['split:${member.userId}'] != null) ...[
      const SizedBox(height: 4),
      Row(
        children: [
          const Expanded(child: SizedBox.shrink()),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: Text(
              _distributionErrors['split:${member.userId}']!,
              style: AppTextStyles.footnote
                  .copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    ],
    ```

    Keep the outer `Padding(padding: EdgeInsets.only(bottom:
    Spacing.space12), child: ...)` around the new `Column`.

13. **Savings error render**: replace the existing `if (_disburse) ...[
    helperText ]` with the precedence-ordered structure from **Addendum
    Proposed Solution → Inline error render** (error branch first, helper
    fallback second).

14. **Save button gate**: change
    `final enabled = _amountController.cents > 0;` to
    `final enabled = _amountController.cents > 0 && _distributionErrors.isEmpty;`.

15. **Import**: add `import 'package:flutter/foundation.dart' show mapEquals;`
    at the top of `add_financial_entry_bottom_sheet.dart` if not already
    present (grep-verified not present). Alphabetize per the file's existing
    import order.

## Verification Plan

### Tier 1 — pre-deploy (before merge)

Executable by QA without a running app:

1. `flutter analyze lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
   — 0 issues.
2. `flutter analyze test/features/financials/` — 0 issues.
3. **Extend the existing widget test file at
   `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`**
   with a new `group('distribution auto-fill and validation', () { ... })`
   containing the following 7 tests. Do NOT rewrite existing tests. Each
   uses the existing test harness (`showAddFinancialEntrySheet` inside a
   `ProviderScope` with mock `MemberVM` list — same pattern the existing
   suite uses; check the file to confirm the shape):

   1. `'Deposit to Savings ON with Disburse OFF auto-fills full Amount'`
      — set `_amountController.cents = 20000` (via typing "20000" into the
      Amount field); with Disburse OFF, tap the Deposit-to-Savings switch;
      expect `_depositToSavingsController.cents == 20000` AND the Savings
      Amount `CurrencyTextField` visually renders `$200.00`.

   2. `'Deposit to Savings ON with Disburse ON and splits fully covering
      Amount fills $0'` — set amount = $250.00; toggle Disburse ON (member
      splits auto-populate to sum-to-amount); tap Deposit-to-Savings ON;
      expect `_depositToSavingsController.cents == 0` (no double-count).

   3. `'Deposit to Savings ON with Disburse ON and positive remainder fills
      remainder — REGRESSION GUARD'` — set amount = $250.00; toggle Disburse
      ON; reduce one member's split from $41.66 to $30.00 via the field's
      `onChanged`; expect (a) Deposit-to-Savings switch auto-flipped to ON,
      (b) `_depositToSavingsController.cents == 1166` ($11.66), (c) no
      distribution errors.

   4. `'Typing a split that exceeds Amount shows inline error on that split
      and disables Save'` — set amount = $250.00; toggle Disburse ON; type
      into member A's split field a value that makes total > $250 (e.g.,
      $500); expect (a) `_distributionErrors['split:${memberA.userId}'] ==
      'Exceeds remaining balance'`, (b) a `Text` widget with that message
      renders in the split row's error slot, (c) the Save button's
      `onPrimary` is null (disabled).

   5. `'Correcting the offending split clears the error and re-enables
      Save'` — continuation of test 4: reduce member A's split back to
      $41.66; expect (a) `_distributionErrors` is empty, (b) no error `Text`
      renders, (c) Save button is enabled.

   6. `'Typing a Savings value that exceeds Amount shows inline error on
      Savings and disables Save'` — set amount = $200.00; toggle
      Deposit-to-Savings ON (savings auto-fills to $200); type additional
      digits to push savings to $300; expect (a)
      `_distributionErrors['savings'] == 'Exceeds remaining balance'`, (b)
      the error `Text` renders under Savings (helper text is hidden), (c)
      Save disabled.

   7. `'Correcting the offending Savings value clears the error and
      re-enables Save'` — continuation of test 6: clear Savings and re-enter
      $150; expect no errors and Save enabled.

4. **Existing test suite passes**: run `flutter test` in full; only the two
   pre-existing unrelated `login_screen_demo_button_test.dart` failures
   documented in `ENGINEER_REPORT.md` are permitted. Zero new failures.

None of these Tier 1 checks require a running app. They are `flutter test`
harness widget tests only.

### Tier 2 — post-deploy

**Not applicable.** This addendum has no DB / migration / edge-function
component. Nothing new to apply to an ephemeral Supabase instance beyond
the migration already covered by the original plan's Tier 2.

### Owner-run manual QA punch list (Tony, at PR-test time)

QA hands this list to Tony verbatim; QA does not attempt to run it because
it requires a launched app. Each step numbered, each with an exact expected
result.

1. Open the app → Financials → tap "Add Entry" with Income mode selected.
   In the drawer, enter Amount `$200.00`, leave Disburse to Band OFF, tap
   **Deposit to Savings** ON.
   **Expected**: The Savings Amount field appears and displays `$200.00`
   immediately (auto-populated). Save button is enabled and shows
   `Add Transaction`.

2. In the same drawer, toggle Disburse to Band ON.
   **Expected**: Member split rows appear, each pre-filled with an even
   share of $200.00. The Savings Amount field snaps to `$0.00` (splits fully
   allocate the amount; auto-balancer zeroes savings). Deposit-to-Savings
   switch stays ON where the user left it — its label subtotal is still
   `($X.XX)` from `widget.savingsTotalCents`. Save button remains enabled.

3. Reduce one member's split from ~$33 to `$20`.
   **Expected**: Savings Amount jumps to reflect the new remainder (~$13
   from the ~$13 unallocated). Helper text `"Automatically calculated from
   remaining amount."` shows beneath Savings (Disburse is ON). Save
   enabled.

4. Type into that same member's split field a value clearly above the
   Amount, e.g. `$500`.
   **Expected**: An error message `"Exceeds remaining balance"` (red,
   footnote size) appears **immediately beneath that member's split
   field**, aligned under the input column. The Savings Amount field's
   helper text is gone (Savings is now $0 with no error attributed to it).
   Save button becomes greyed out / disabled.

5. Reduce that same member's split back to a valid value (any value ≤
   remaining budget).
   **Expected**: The red error under that split disappears. Save button
   re-enables. Savings Amount auto-recomputes to any positive remainder.

6. Turn Disburse to Band OFF (splits collapse away). With Deposit to
   Savings still ON, type into the Savings Amount field a value clearly
   above Amount (e.g., Amount is $200, type $300 into Savings).
   **Expected**: Red error text `"Exceeds remaining balance"` appears
   immediately under the Savings Amount field. Save button disabled.

7. Clear Savings and re-enter a value ≤ Amount (e.g., `$150`).
   **Expected**: Error clears. Save enabled.

8. Back to Disburse ON with a positive remainder from step 3 (savings
   auto-filled). Tap Deposit to Savings toggle OFF.
   **Expected**: Savings Amount snaps to `$0.00`. Field is hidden by the
   AnimatedSize collapse. Deposit-to-Savings label subtotal still reads
   `(<band savings total>)`. Save enabled.

9. Tap Deposit to Savings toggle ON again (Disburse still ON, splits still
   allocated with some remainder — say `$13`).
   **Expected**: Savings Amount reveals and populates with the remainder
   (`$13.00`), not full Amount. Confirms the auto-balancer's stored value
   is respected when Disburse is ON.

10. Return to Add mode with Disburse OFF from scratch. Set Amount = $200,
    tap Savings ON (fills $200 per step 1), tap Savings OFF (savings→$0),
    then tap Savings ON again.
    **Expected**: Savings re-fills with $200 (full Amount). Confirms the
    Disburse-OFF full-amount behavior is idempotent.

11. Save any of the above valid states.
    **Expected**: Drawer closes, entry appears in the Financials list, the
    displayed total matches `sum(splits) + savings` (which now equals
    `amount` by validation).

## QA Regression Areas

Manually spot-check (owner-run at PR-test time — QA cannot):

1. **Existing "user reduces split → savings auto-fills" flow** works
   identically to how it worked on the branch immediately before this
   addendum. Widget test 3 in Tier 1 is the mechanical guard; step 3
   in the manual punch list is the visual guard.
2. **Existing edit-mode entries with valid distribution values** (sum ≤
   amount) open in the drawer with no errors on any field and with Save
   enabled — no false positives.
3. **Income → Expense switch** clears any distribution errors that might
   have been present in income mode (the entire Distribution section is
   replaced by Reimbursement). Verified by inspecting the expense-mode
   drawer after having triggered an error in income mode.
4. **Payment Details section, autocomplete, Reimbursement section, Notes
   section** all continue to work as they did before this addendum — the
   addendum does not touch any of those code paths.
5. **Gig Pay flow inside the event editor**
   (`gig_pay_bottom_sheet.dart`) and **Gig Expense sub-view inside the
   event editor** (`gig_expense_subview.dart`) — off-limits and untouched.
   Confirm they still open, save, and update linked entries unchanged.

## Rollout Strategy

Same as the original plan. This addendum has no separate rollout — it is
part of the same in-flight PR. No migration to apply (that migration is
still the original's, unchanged), no config change, no `--dart-define`
change, no platform-specific rebuild.

## Out of Scope

- **Extending `AppTextField` / `CurrencyTextField` with a first-class error
  prop** — much larger surface change; sibling-`Text`-below is the
  established convention and is used here.
- **Adding a DB-level CHECK enforcing `sum(splits) + savings <= amount`** —
  splits live in a separate table, cross-table CHECK isn't ergonomic, and
  client-side gating combined with a `try/catch` around the Save call is
  the practical enforcement. If Tony wants defense-in-depth, that's a
  separate targeted migration.
- **Changing the on-the-wire schema** (`amount_cents`, disbursement rows,
  `deposit_to_savings_cents`) — nothing to change.
- **Auto-adjusting other fields to resolve a violation** (e.g., auto-reducing
  savings when a split grows). The user typed the value; the fix is theirs
  to make. Auto-fixing would hide the arithmetic error and confuse the
  user.
- **Making the error message currency-formatted** ("Exceeds by $X.XX") —
  adds a formatter dependency and diverges from the codebase's terse
  message style. Not required by Tony's ask.
- **Any change to the Details bottom sheet, PDF export, financial reports,
  or the demo-provisioning RPC.**
- **Any web-marketing, iOS/macOS/Android platform, or auth code change.**

