# ENGINEER_REPORT

## Feature Slug

feature/band-gear-management

## Feature Title

Band Gear Management

## Cycle Number

10

## Goal

Cycle 10 — In-branch UX-polish + minor-schema adjustment driven by
Tony's cycle-9 Step 6b test finding on the current PR head: "The
price column should be wide enough to display this number '$9,999.99'.
Include another column in the table for 'New/Used' and in the New
gear item, include a checkbox to denote if the item is Used. In New
Gear Item, under Owner, use a button toggle with the labels 'Band'
and 'Member'." Four items in scope: (1) Gear table Price column
min-width floor at `$9,999.99` even when no visible row is that
large; (2) new `New/Used` column between Owner and Price, backed by a
new `is_used BOOLEAN NOT NULL DEFAULT FALSE` column on `band_gear`
(follows the same additive-column pattern as cycle 4's
`contributor_permissions.can_view_gear` scaffolding); (3) `Used`
toggle in the Gear form sheet using the same `AppSwitch` shape
`add_financial_entry_bottom_sheet.dart` uses for its
`is_1099_expected` boolean; (4) Owner segmented control relabeled to
`Band` / `Member` (two-segment `SegmentedButton` — the existing
peer button-toggle widget already in this file). Cycles 8 and 9
uncommitted work rolls forward unchanged; QA validates cycles
8+9+10 together as one pass.

Cycle 9 — In-branch UX-polish adjustment driven by Tony's cycle-8 Step 6b
test finding on the current PR head: "In Gear, make the table column width
for Name 50 px wider, Purchased on column should be wide enough to display
the date without truncating, change 'Purchased From' to 'From' and make that
50px wider. Also all currency fields should have the decimal point built in.
The placeholder should be '$  0.00' and when typing, the first digit typed
is displayed like this '$  0.01', and the second number entered '$  0.12'
and the third '$  1.23' and so on." Bump Gear table Name min-width by
50 px (140 → 190), swap `_kPurchasedOnWidth` (was 110, fixed) for a
dynamic width computed with the same `_measureText` pattern the Price
column already uses so the widest formatted `MMM d, y` date never
truncates, rename `_kPurchasedFromWidth` → `_kFromWidth` (110 → 160,
+50 px), change the table header label `'Purchased From'` → `'From'`,
and replace the Gear form-sheet Price `AppTextField` with a POS-style
cents-first input that reuses the shared `CurrencyInputController` (int
cents storage) and an inline `_GearCurrencyFormatter` emitting Tony's
literal `$  0.00` / `$  0.01` / `$  0.12` / `$  1.23` / `$  1,234.56`
shape. Form-sheet `Purchased From` label also renamed to `From` to match
the table. Cycle 8's modal owner-filter landed on disk but was never
QA'd — QA validates cycles 8 and 9 together as one pass. Cycles 1
through 7 work rolls forward unchanged.

Cycle 8 — In-branch UX-scope adjustment driven by Tony's cycle-7 Step 6b test
finding on the current PR head: "I want a filter to select ownership — either
Band or one or many band members. This filter would open a modal for the user
to make their selections." Replace cycle 7's 3-segment owner toggle
(`All / Band-owned / Member-owned`) with a single chip that opens a modal
bottom-sheet multi-select. Controller state swaps `GearOwnerFilter` +
`ownerFilter` for `Set<String> ownerSelection` — sentinel `'band'` matches
band-owned; every other entry is a `users.id` UUID matching a specific member
owner. Empty set = no owner filter. Cycles 1 through 7 work rolls forward
unchanged.

Cycle 7 — In-branch UX-scope adjustment driven by Tony's cycle-7 Step 6b test
finding on the current PR head: "the gear screen should match the financials
screen, including the filters. Gear should be listed in a table to match
financials instead of cards." Rewrite `gear_screen.dart` as a table-based
mirror of `lib/features/financials/financials_screen.dart`, extend
`gear_controller.dart` with matching filter state (`GearOwnerFilter`,
`GearDateFilter`, `customStartDate`, `customEndDate`, `filteredItems`) and
notifier methods (`setOwnerFilter`, `setDateFilter`, `setCustomDateRange`),
delete `widgets/gear_row.dart` and `widgets/gear_empty_state.dart` and
inline both into the screen file (financials' precedent shape). Cycle 8
supersedes the owner-filter portion (`GearOwnerFilter` enum + toggle +
`setOwnerFilter` are removed; see the Cycle 8 section below). Cycle 1
through 6 work rolls forward unchanged.

Cycle 6 — In-branch revert-only cycle driven by Tony's cycle-5 QA-APPROVED
state review (Manager cycle-6 note): "remove 'Gear' from the menu. It should
only be in the Quick Actions section." Cycle 5's Quick Actions surfacing
stays exactly as-is; cycle 3's side-drawer surfacing is fully reverted
(`side_drawer.dart` and `app_shell.dart` restored to main tip byte-identical).
No new code introduced this cycle.

Cycle 5 — In-branch additive scope extension driven by Tony's PR #261 6b test
finding ("i don't see a button for Gear under Quick actions"). Surface Gear
under the Home dashboard's Quick Actions row by mirroring the existing
Financials precedent exactly (`_handleOpenFinancials` + `onFinancials` /
`showFinancials` on `QuickActionsRow`). The base `ARCHITECT_PLAN.md` surfaced
Gear only via the side drawer (Task 15) — Quick Actions was not part of the
original plan; this cycle adds it as the minimal, precedent-matching wiring.
All cycle-1-through-4 work rolls forward unchanged.

Cycle 4 — Implement the contributor visibility gate scope addition from the
Architect cycle-3 revision (three follow-up RBAC migrations + Dart parity
edits) and re-run the Tier 1 verification procedure. Cycle-3 uncommitted
implementation work is unchanged and rolls forward as-is.

## Architect Tasks Completed

Cycle 10 (this cycle) — in-branch UX-polish + additive-column schema
change, no new architect tasks:

- Cycle 10 price min-width + New/Used column + Owner Band/Member
  toggle + Used form-sheet checkbox: Executed. See the "Cycle 10
  revision" dedicated section below for the four items. The `is_used`
  column added to `band_gear` is documented explicitly as a new
  in-branch scope addition beyond the original `ARCHITECT_PLAN.md`;
  it follows the same additive-column pattern as cycle-4's
  `contributor_permissions.can_view_gear` scaffolding
  ([supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql](../../../supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql)).

Cycle 9 (previous cycle) — in-branch UX-polish adjustment, no new architect tasks:

- Cycle 9 column-width polish + cents-first price input: Executed. See
  the "Cycle 9 revision" dedicated section below for the five items
  (Name +50 px min, Purchased On dynamic, From label + 50 px, cents-first
  price input, validation compatibility). Reuses the shared
  `CurrencyInputController` for int-cents state and copies the POS-style
  formatter inline in `gear_form_sheet.dart` under a distinct display
  format so financials' column widths are not disturbed.

Cycle 8 — in-branch UX-scope adjustment, no new architect tasks (landed on
disk in the cycle-8 pass, rolled into cycle 9's QA gate since cycle 8 was
never QA'd on its own):

- Cycle 8 owner-filter modal multi-select: Executed. Replaces (not extends)
  cycle 7's `GearOwnerFilter` enum + `_OwnerFilterToggle`. See the
  "Cycle 8+9 combined" Files Modified block below.

Cycle 7 — in-branch UX-scope adjustment, no new architect tasks:

- Cycle 7 Financials-parity rewrite (Gear screen table + filters): Executed.
  See dedicated section below. The 3-segment `_OwnerFilterToggle` shipped
  in cycle 7 is removed in cycle 8; the table + date filters + entries
  list + empty/error states from cycle 7 roll forward unchanged.

Cycle 6 — revert-only, no new architect tasks:

- Cycle 6 revert (side-drawer surfacing removed per Tony's cycle-5
  QA-APPROVED review directive): Executed. See dedicated section below.

Cycle 5 — additive scope extension:

- Cycle 5 addition (Quick Actions surfacing): Completed. See dedicated
  section below.

Cycle 4:

- Task 2 — Migration 1 of 3 (sub-permission column): Completed. Added
  `supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`
  with `ALTER TABLE public.contributor_permissions ADD COLUMN IF NOT EXISTS
can_view_gear BOOLEAN NOT NULL DEFAULT FALSE;`, direct mirror of
  `20260604000001_add_can_view_financials_to_contributor_permissions.sql`.
- Task 3 — Migration 2 of 3 (RPC fix): Completed. Added
  `supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql`
  with a full-body `CREATE OR REPLACE FUNCTION public.update_member_role(UUID,
UUID, TEXT, JSONB)` mirroring
  `20260711120000_fix_update_member_role_can_view_financials.sql`, adding
  exactly one SET-clause line `can_view_gear = COALESCE((p_sub_permissions->>
'can_view_gear')::boolean, FALSE),`. Terminates with `GRANT EXECUTE ON
FUNCTION public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;`.
- Task 4 — Migration 3 of 3 (RLS helper + SELECT policy swap): Completed.
  Added `supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql`
  with (a) `CREATE OR REPLACE FUNCTION public.check_gear_view_permission(
p_band_id UUID) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET
search_path = public` body mirroring `check_financial_view_permission`;
  (b) `REVOKE ALL ON FUNCTION public.check_gear_view_permission(UUID) FROM
PUBLIC, anon;` and `GRANT EXECUTE ON FUNCTION public.check_gear_view_permission(
UUID) TO authenticated;`; (c) `DROP POLICY IF EXISTS "Band members can view
gear" ON public.band_gear;` then `CREATE POLICY "Band members can view gear"
ON public.band_gear FOR SELECT USING (public.check_gear_view_permission(
band_id));`. INSERT / UPDATE / DELETE policies are not touched.
- Task 9 — Sub-permission field on Dart model: Completed. Edited
  `lib/features/members/permissions/contributor_permissions.dart` to add a
  `canViewGear` field with `fromJson` / `toJson` / `copyWith` / `allEnabled`
  / `allDisabled` / `toString` parity to `canViewFinancials`, defaulting
  `false` in the immutable constructor.
- Task 10 — Rewire `BandPermissions.canViewGear` body: Completed. Edited
  `lib/features/members/permissions/band_permissions.dart` to change the
  `canViewGear` getter body from `isAdmin || isMember || isContributor` to
  `isAdmin || isMember` for the admin/member branch and
  `subPermissions?.canViewGear ?? false` for the contributor branch.
  `canManageGear` unchanged.
- Task 11 — Role Management sheet toggle: Completed. Edited
  `lib/features/members/widgets/role_management_sheet.dart` to add one new
  `_buildPermissionToggle` "Can view gear" immediately after "Can view
  financials" (wired to `_subPermissions.canViewGear` /
  `copyWith(canViewGear: v)`), and extended `_permissionsEqual` to compare
  `a.canViewGear == b.canViewGear`.
- Task 16 — Model unit test: Verified (already added in cycle-3 uncommitted
  work as `test/features/gear/gear_item_test.dart`). Re-run in T1.2: 5/5
  pass.
- Task 17 — `flutter analyze` + `flutter test` iterate to green: Completed.
  Analyzer clean at every severity across the T1.1 file list; feature tests
  green; full-suite failure is the single accepted deviation A.

Inherited from cycle-3 uncommitted work (unchanged this cycle):

- Task 1 — Base migration
  `supabase/migrations/20260905201000_create_band_gear.sql` (table, indexes,
  RLS enable, four RLS policies, `set_band_gear_updated_at` trigger).
- Task 5 — `lib/features/gear/models/gear_item.dart`.
- Task 6 — `lib/features/gear/gear_repository.dart`.
- Task 7 — `lib/features/gear/gear_controller.dart`.
- Task 8 — Cycle-3 `canViewGear` / `canManageGear` getters already present in
  `lib/features/members/permissions/band_permissions.dart` (task 10 above
  swaps `canViewGear`'s body only).
- Task 12 — `lib/features/gear/widgets/gear_empty_state.dart` and
  `lib/features/gear/widgets/gear_row.dart`.
- Task 13 — `lib/features/gear/widgets/gear_form_sheet.dart`.
- Task 14 — `lib/features/gear/gear_screen.dart`.
- Task 15 — Drawer + shell wiring in
  `lib/features/home/widgets/side_drawer.dart` and
  `lib/features/shell/app_shell.dart`.

## Files Created

Cycle 10 (new this cycle):

- supabase/migrations/20260906160214_add_is_used_to_band_gear.sql

Cycle 7: none.

Cycle 5: none.

Cycle 4 (new this cycle):

- supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql
- supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql
- supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql

Inherited from cycle-3 uncommitted work (byte-identical to cycle 3):

- supabase/migrations/20260905201000_create_band_gear.sql
- lib/features/gear/models/gear_item.dart
- lib/features/gear/gear_repository.dart
- lib/features/gear/gear_controller.dart
- lib/features/gear/gear_screen.dart
- lib/features/gear/widgets/gear_row.dart
- lib/features/gear/widgets/gear_form_sheet.dart
- lib/features/gear/widgets/gear_empty_state.dart
- test/features/gear/gear_item_test.dart
- docs/features/feature-band-gear-management/ENGINEER_REPORT.md

## Files Modified

Cycle 10 (new this cycle) — price min-width floor, New/Used column
(client + schema), Used form-sheet checkbox, and Owner Band/Member
relabel:

- lib/features/gear/gear_screen.dart — **Item 1**: after the existing
  max-scan loop over the visible rows' formatted prices in
  `_GearEntriesList.build`, added a fixed minimum so the Price column
  always fits `$9,999.99` even when no visible row is that large —
  `final minPriceWidth = _measureText('\$9,999.99', priceDataStyle);
  if (minPriceWidth > maxPricePx) maxPricePx = minPriceWidth;`
  — same style variable name (`priceDataStyle`) and same +16 padding
  buffer already applied downstream (`final priceColumnWidth =
  maxPricePx + 16;`). **Item 2 (table column)**: added
  `const _kNewUsedWidth = 72.0;` (compile-time const upper end of the
  Manager-specified 64–72 px range; fits `'Used'` at
  `AppTextStyles.callout` with buffer), included it in
  `_kFixedColumnsWidth` so the min-width calc reserves the new column
  space (`const _kFixedColumnsWidth = _kFromWidth + _kOwnerWidth +
_kNewUsedWidth;`), added a `_HeaderCell('New/Used', borderSide:
borderSide)` header cell between the Owner and Price header cells,
  and added a matching row cell rendering `item.isUsed ? 'Used' :
'New'` at the same `AppTextStyles.callout` shape as the peer Owner
  cell (left-aligned, single-line ellipsis). No cycle-8 modal owner
  filter, cycle-9 dynamic Purchased On width, or cycle-9 From label
  change is touched.

- lib/features/gear/models/gear_item.dart — **Item 2 (model)**: added
  `final bool isUsed` field to `GearItem` with `this.isUsed = false`
  default in the constructor, `isUsed: (json['is_used'] as bool?) ??
false` null-safe read in `fromJson`, and `'is_used': isUsed` write in
  `toJson`. Owner-shape invariant assert and `owner_type` /
  `owner_user_id` handling unchanged. `GearItem` has no `copyWith`
  method today, so there is nothing to wire `isUsed` into on that
  vector — see Deviations From Plan below for the intentional
  omission.

- lib/features/gear/widgets/gear_form_sheet.dart — **Item 3**: added
  `import 'package:bandroadie/components/ui/app_switch.dart';`, added
  `bool _isUsed = false;` state field to `_GearFormSheetState`,
  seeded `_isUsed = item?.isUsed ?? false;` in `initState` (edit mode
  pre-populates the switch from the existing item), added a
  `MainAxisAlignment.spaceBetween` `Row` with a `Text('Used', style:
AppTextStyles.callout.copyWith(color: context.colors.textPrimary))`
  on the left and an `AppSwitch(value: _isUsed, onChanged: _isReadOnly
|| _isSaving ? null : (v) => setState(() => _isUsed = v))` on the
  right — identical shape to the `is_1099_expected` toggle in
  `add_financial_entry_bottom_sheet.dart:717–725`. The Used row is
  placed "right after the `From` field, before the Owner control"
  per Manager Item 3 spec; the pre-cycle-10 form order was
  Name → Owner → From → Price → Purchased On, so satisfying that
  placement rule requires moving the `From` field up to sit
  immediately after `Name`. New form-sheet visual + source order:
  Name → From → Used → Owner (+ optional Member picker) → Price →
  Purchased On. **Item 4**: relabeled the existing
  `SegmentedButton<GearOwnerType>` segments — `'Band-owned'` →
  `'Band'` and `'Member-owned'` → `'Member'`. Widget unchanged
  (`SegmentedButton` is a Material two-segment button toggle and is
  already the peer button-toggle widget used in this file);
  `_ownerType` state, `_ownerUserId` state, the member-picker
  conditional (`if (_ownerType == GearOwnerType.member) ...`), the
  `_activeMembers()` source, and the form-side "member requires a
  selected member" validation in `_buildPayload` are all unchanged.
  `_buildPayload` extended with `'is_used': _isUsed` — so `is_used`
  flows into the same `Map<String, dynamic>` the repository already
  pass-throughs, and no repository-file edit is needed.

- test/features/gear/gear_item_test.dart — **Item 2 (model tests)**:
  extended the two existing `fromJson/toJson` round-trip tests to
  cover `is_used = true` (band-owned test) and `is_used = false`
  (member-owned test), and added a third new test
  `'fromJson defaults isUsed to false when is_used key is missing'`
  that constructs a source `Map` with no `is_used` key, verifies
  `item.isUsed == false`, and verifies `toJson()['is_used'] ==
false`. Total tests grow from 5 to 6.

- lib/features/gear/gear_repository.dart — **no edit needed**. The
  repo's `createGear({required String bandId, required Map<String,
dynamic> data})` and `updateGear({required String id, required
Map<String, dynamic> data})` methods take the payload as a
  `Map<String, dynamic>` pass-through and unpack every key in the
  map into the Supabase insert / update. `is_used` is added to the
  payload map by `_buildPayload` in the form sheet (see above) and
  flows through the repo unchanged. The cache-layer round-trip is
  unchanged shape-wise, matching Manager Item 2's directive: "The
  cache-layer round-trip is unchanged shape-wise."

Cycle 8+9 combined (previous cycle) — modal owner filter (cycle 8, landed on
disk without a QA pass) + Gear table column-width polish and cents-first
price input (cycle 9). Rolled together per Manager cycle-9 instruction so
QA validates both as a single evidence set:

- lib/features/gear/gear_controller.dart — **cycle 8**. Replaced the
  cycle-7 `GearOwnerFilter` enum + `ownerFilter` field with
  `Set<String> ownerSelection` (default `const <String>{}`) whose
  sentinel `'band'` matches band-owned items and every other entry is a
  `users.id` UUID matching a specific member-owned item's `ownerUserId`.
  `filteredItems` was rewritten to consult `ownerSelection` (empty set =
  no owner filter). `copyWith` extended with `Set<String>? ownerSelection`.
  Notifier methods: added `setOwnerSelection(Set<String>)` (wraps in
  `Set<String>.unmodifiable`) and `clearOwnerSelection()`; removed the
  cycle-7 `setOwnerFilter(GearOwnerFilter)`. No change to load / refresh /
  create / update / delete / reset / date-filter methods. No cycle 9 edit
  needed in this file.
- lib/features/gear/gear_screen.dart — **cycle 8** replaced
  `_OwnerFilterToggle` (3-segment segmented control) with a single
  `_FilterChip` inline at the front of `_FilterRow`, whose label is
  `_ownerChipLabel(state.ownerSelection, members)` (returns `'Owner'`
  when empty, `'Band'` or a member short label when one entry, `'N
  owners selected'` for 2+), and whose `onTap` opens
  `_openOwnerFilterModal()`. `_openOwnerFilterModal()` presents a full
  `showModalBottomSheet<Set<String>>` sheet (`_OwnerFilterModal` — a
  `ConsumerStatefulWidget`) with a drag handle, header, a Band
  `CheckboxListTile`, an active-members list of `CheckboxListTile`s, and
  a bottom row of Clear + Done `AppButton`s; selection is staged locally
  in `_pending` and committed to the controller only on Done (swipe-
  dismiss discards changes). **cycle 9** column widths + labels: bumped
  `_kMinNameWidth` `140.0` → `190.0` (adds 50 px to the Name column's
  min-width contribution so horizontal scroll kicks in 50 px earlier on
  the narrowest supported screens); dropped the fixed
  `const _kPurchasedOnWidth = 110.0` constant and replaced it with a
  dynamically-computed `purchasedOnColumnWidth` inside
  `_GearEntriesList.build` that measures the widest `MMM d, y` label
  across all rows at the row's `AppTextStyles.callout` style (plus the
  header `'Purchased On'` at `AppTextStyles.footnote` w600 letterSpacing
  0.5) and adds a 16 px padding buffer — the identical `_measureText`
  pattern the Price column already uses in this file, matched to the
  shape financials uses for its Amount column; renamed
  `_kPurchasedFromWidth` (`110.0`) → `_kFromWidth` (`160.0`, +50 px) so
  the From column is 50 px wider; changed the `_TableHeader` cell label
  `'Purchased From'` → `'From'`. `_TableHeader` and `_GearTableRow` both
  gained a `purchasedOnColumnWidth` required parameter alongside the
  existing `priceColumnWidth`; the Purchased On row cell also switched
  from `overflow: TextOverflow.ellipsis` to
  `softWrap: false, overflow: TextOverflow.visible` (dynamic width
  guarantees fit, so ellipsis is unreachable and would round-clip a
  measured-fit cell if hit). `_kFixedColumnsWidth` recomputed as
  `_kFromWidth + _kOwnerWidth`. Owner column width (`_kOwnerWidth =
  110.0`) unchanged. No API change to `GearFormSheet.show(...)`; no new
  provider; no new named route.
- lib/features/gear/widgets/gear_form_sheet.dart — **cycle 9** cents-first
  price input + "From" label. Added import
  `package:bandroadie/shared/widgets/currency_input_field.dart` so this
  file can reuse the same `CurrencyInputController` (int-cents
  `ValueNotifier<int>`) that financials' `add_financial_entry_bottom_sheet.dart`
  uses for its `amountCents` field — keeping Gear's `price_cents` field
  and financials' `amount_cents` field on the same in-memory storage
  convention. Field declarations: replaced
  `late TextEditingController _priceController` with two fields —
  `late CurrencyInputController _priceCents` (int cents state) and
  `late TextEditingController _priceTextController` (AppTextField display
  text). `initState` now seeds `_priceCents` from `item?.priceCents ?? 0`
  and seeds `_priceTextController.text` to
  `_formatPriceCentsDisplay(initialCents)` when `initialCents > 0`
  (existing item with a saved price renders `$  X.YZ` immediately on
  open) or `''` when zero/null (placeholder `$  0.00` shows via
  `hintText`). `dispose` disposes `_priceTextController` and
  `_priceCents` (dispose order preserved: unfocus all, dispose text
  controllers + cents notifier, dispose focus nodes, super.dispose).
  Price `AppTextField` swapped to `controller: _priceTextController`,
  `keyboardType: TextInputType.number`, `hintText: '\$  0.00'`,
  `inputFormatters: [FilteringTextInputFormatter.digitsOnly,
_GearCurrencyFormatter(_priceCents)]` — all non-digit keystrokes are
  silently rejected, digits POS-shift into cents from the right, and
  backspace divides by 10 (drops the rightmost cent digit) per Tony's
  spec. Purchased From `AppTextField` `labelText` renamed
  `'Purchased From'` → `'From'` to match the gear table header. Legacy
  `_parsePriceCents()` body (`double.tryParse` → `* 100`.round()) removed;
  new `_parsePriceCents()` returns `_priceCents.cents == 0 ? null :
_priceCents.cents` — preserves the cycle-3 optional-price contract
  (empty → `null` in payload, valid non-zero → int cents), which keeps
  the existing form-sheet validation state working unchanged. The
  "Price must be a valid non-negative amount" snackbar path is removed
  because the new formatter guarantees a valid non-negative int at all
  times (no free-text price paths remain). File-local additions:
  `_formatPriceCentsDisplay(int cents)` (renders `$  X.YZ` with
  `NumberFormat('#,##0')` thousands-grouping on dollars, reusing the
  existing `intl` import already in the file) and
  `_GearCurrencyFormatter extends TextInputFormatter` (mirrors the
  private `_CurrencyInputFormatter` in
  `lib/shared/widgets/currency_input_field.dart` line-for-line except
  it calls `_formatPriceCentsDisplay` instead of
  `controller.formattedValue` so the double-space display shape doesn't
  bleed into financials — `TextEditingValue.empty` used for the empty
  state to keep the redundant-argument-values lint clean).
  No change to `_buildPayload`'s `owner_type` / `owner_user_id` /
  `purchased_on` / `purchased_from` / `name` handling; `price_cents`
  is now sourced from `_priceCents.cents` (mapped 0 → null).

Cycle 7 (new this cycle) — Financials-parity rewrite:

- lib/features/gear/gear_screen.dart — rewritten as a table-based mirror of
  `lib/features/financials/financials_screen.dart`. New structural pieces:
  `BackOnlyAppBar` at top; title row with `'Gear'` on the left and
  `TextButton.icon` (`AppIcons.add`, `'Add'`) on the right when
  `canManageGear == true`; owner-filter toggle `_OwnerFilterToggle` (3
  segments: All / Band-owned / Member-owned) mirroring financials'
  `_ViewModeToggle`; date-filter row `_DateFilterRow` + `_FilterChip`
  (All Time / This Year / This Month / Custom Range…) mirroring financials'
  `_DateFilterRow`; entries table `_GearEntriesList` +
  `_TableHeader` + `_HeaderCell` + `_GearTableRow` mirroring financials'
  `_EntriesList` + `_TableHeader` + `_HeaderCell` + `_EntryTableRow` (with
  the same horizontal `SingleChildScrollView` outer wrapper and the same
  `_measureText` pattern for the dynamic-width Price column); empty state
  `_EmptyState` mirroring financials' `_EmptyState`; error state
  `_ErrorState` mirroring financials' `_ErrorState` verbatim. Gear column
  set (left-to-right): **Name** (`Expanded`), **Purchased On** (110px,
  `MMM d, y`), **Purchased From** (110px, single-line ellipsis),
  **Owner** (110px, single-line ellipsis — "Band" for band-owned, first
  name + last initial for member-owned), **Price** (dynamic width via
  `_measureText`, right-aligned, `NumberFormat.currency(locale: 'en_US',
symbol: '\$')`). Tap on a row opens the existing `GearFormSheet` bottom
  sheet in edit mode; no new details sheet introduced (cycle-3 form sheet
  already supports read-only + edit modes). Removed: `RefreshIndicator`
  pull-to-refresh, `AppButton` retry inside error state, `_buildContent`
  helper method, `_ownerLabel`/`_memberOwnedLabel` on state (moved to
  file-top helpers so the private `_GearTableRow` can call them), the
  `bandId == null` "No band selected" guard card (unreachable — screen is
  only pushed from Home Quick Actions when a band is active and
  `canViewGear` is true). No cycle-3 API on `gear_form_sheet.dart` was
  changed — the tap flow reuses `GearFormSheet.show(...)` verbatim.
- lib/features/gear/gear_controller.dart — extended `GearState` with:
  `ownerFilter` (`GearOwnerFilter` enum: `all`, `band`, `member`;
  default `all`), `dateFilter` (`GearDateFilter` enum: `allTime`,
  `thisYear`, `thisMonth`, `custom`; default `allTime`),
  `customStartDate` / `customEndDate` (nullable, default `null`), and
  derived getter `filteredItems` that applies owner + date filters and
  sorts newest-purchased first (nulls last). Added `copyWith` support
  for the four new fields plus `clearCustomDates: bool`. Added notifier
  methods `setOwnerFilter`, `setDateFilter`, `setCustomDateRange` —
  each mirrors the equivalent method on `FinancialsNotifier` exactly.
  `load`/`refresh`/`create`/`update`/`delete`/`reset` bodies unchanged
  from cycle 3.

  **null-date handling (documented per Manager cycle-7 note).** Items
  with `purchasedOn == null` are included ONLY when
  `dateFilter == GearDateFilter.allTime`; every date-bounded filter
  (This Year / This Month / Custom Range) drops them. This is the
  simplest behavior consistent with the intuitive expectation that a
  date-bounded filter shouldn't surface rows with no date, and it also
  mirrors financials' shape (financials' `FinancialEntry.entryDate` is
  non-nullable, so financials never has this problem to solve; the
  simplest mirror is "no date → no date-bounded surface"). Sort order:
  newest-purchased first; null-date items sort last within any bucket.

  **Filter-state resurrection note.** Manager cycle-7 message references
  "resurrection of cycle-3-then-removed-in-cycle-4 filter state". For
  full transparency: `git log` on `gear_controller.dart` on this branch
  shows exactly one commit (`26b5fed`, cycle-3 base), and its
  `GearState` had only `items` / `isLoading` / `error` — no filter
  state ever lived here before cycle 7. Cycle 4 did not remove any
  filter state (it never existed). Cycle 7 is the first time this file
  carries filter state, and — per Manager's intent — the state is
  consumed by the screen from the moment it lands (via
  `state.ownerFilter`, `state.dateFilter`, `state.filteredItems` inside
  `_GearEntriesList`).

- lib/features/home/widgets/quick_actions_row.dart — unchanged from cycle 5.
- lib/features/home/home_tab_content.dart — unchanged from cycle 5.

Cycle 6 (unchanged this cycle) — revert-only:

- lib/features/home/widgets/side_drawer.dart — **reverted to main tip**
  (`git checkout main -- lib/features/home/widgets/side_drawer.dart`).
  This removes the three `final VoidCallback? onGearTap;` fields on
  `SideDrawer` / `DrawerOverlay` / `DrawerOverlayContent`, the three
  matching constructor parameter additions, the
  `if (widget.onGearTap != null) ...[ DrawerNavItem ... ]` Gear nav block,
  and the `onGearTap` plumbing in the two `DrawerOverlay*` `child:` blocks.
  It also reverts the four cycle-3 collateral `Container(color:)` →
  `ColoredBox(color:)` scrim-overlay lint fixes on lines
  867 / 877 / 1086 / 1096 (of HEAD numbering). Per Manager cycle-6 note:
  "Reverting to main is the cleanest end state." Net cycle-6 diff vs main
  for this file: 0.
- lib/features/shell/app_shell.dart — **reverted to main tip**
  (`git checkout main -- lib/features/shell/app_shell.dart`). This removes
  `import '../gear/gear_screen.dart';`, the `onGearTap:` callback wiring
  block in `_MenuDrawerLayer`'s `DrawerOverlayContent` call, and the six
  narrow `// ignore: prefer_const_constructors` /
  `// ignore: avoid_redundant_argument_values` lint suppression comments
  cycle 3 added on lines 211 / 216 / 217 / 218 / 247 / 248 (of HEAD
  numbering). Confirmed pre-revert that no other symbol in `app_shell.dart`
  references `GearScreen` (`grep -n 'GearScreen\|gear_screen'` → the
  import line and the `_MenuDrawerLayer` push call were the only two
  matches). Net cycle-6 diff vs main for this file: 0.

Both reverted files are no longer feature-touched. The feature's cycle-6
end state carries **zero** diff-vs-main for either file. They remain in the
T1.1 file list this cycle to prove no regression, per Manager cycle-6 note.

Cycle 5 (unchanged, still modified — Quick Actions surfacing preserved):

- lib/features/home/widgets/quick_actions_row.dart — added `onGear`
  callback field, `showGear` bool field (default `true`), constructor
  parameters, extended `hasVisibleButtons` to include `|| showGear`, and
  appended a `Gear` button block after the Financials block using the same
  `_buildQuickActionButton` helper with matching `SizedBox(width: 12)`
  separator handling. Label is `'Gear'` (no `+` prefix — matches
  Financials style since it opens an existing screen rather than creates a
  new entity). Also removed pre-existing redundant `width: 1` on
  `BorderSide` inside `_buildQuickActionButton` (default is 1) — see
  Cycle 5 pre-existing lint sweep note below.
- lib/features/home/home_tab_content.dart — added `../gear/gear_screen.dart`
  import; added `_handleOpenGear` method next to `_handleOpenFinancials`
  pushing `GearScreen` via `MaterialPageRoute`; read `perms.canViewGear`
  alongside `canViewFinancials` in the `build` method; threaded `canViewGear`
  through `_buildContentState`'s `required` parameter list; extended the
  Quick Actions Builder's `hasAnyButton` check with `|| canViewGear`; passed
  `onGear: canViewGear ? _handleOpenGear : null` and `showGear: canViewGear`
  on the `QuickActionsRow` call. Also swept six pre-existing info-level
  lints in the same file — see Cycle 5 pre-existing lint sweep note below.

Cycle 4:

- lib/features/members/permissions/contributor_permissions.dart — added
  `canViewGear` field with `fromJson` / `toJson` / `copyWith` / `allEnabled`
  / `allDisabled` / `toString` parity to `canViewFinancials`.
- lib/features/members/permissions/band_permissions.dart — swapped the body
  of the existing `canViewGear` getter from unconditional
  `isAdmin || isMember || isContributor` to admin/member-always plus
  contributor-consults-sub-permission; `canManageGear` untouched.
- lib/features/members/widgets/role_management_sheet.dart — added one new
  "Can view gear" `_buildPermissionToggle` after the existing "Can view
  financials" toggle; extended `_permissionsEqual` with
  `a.canViewGear == b.canViewGear`.

Inherited from cycle-3 uncommitted work (byte-identical to cycle 3):

- lib/features/home/widgets/side_drawer.dart
- lib/features/shell/app_shell.dart

## Files Deleted

Cycle 7 (new this cycle):

- lib/features/gear/widgets/gear_row.dart — deleted. Cycle 7 inlines the
  row inside `gear_screen.dart` as a private `_GearTableRow` mirroring
  financials' inline `_EntryTableRow`. `GearRow` was used exactly once
  (from `gear_screen.dart`); no other file references it. Choice
  rationale (per Manager cycle-7 note "either rewrite … or delete it if
  you inline the row … Whichever keeps the diff clean"): deletion +
  inline matches financials' precedent 1:1 and is the smallest surface.
- lib/features/gear/widgets/gear_empty_state.dart — deleted. Cycle 7
  inlines the empty state inside `gear_screen.dart` as a private
  `_EmptyState` mirroring financials' inline `_EmptyState`.
  `GearEmptyState` was used exactly once (from `gear_screen.dart`); no
  other file references it. Choice rationale: same as `gear_row.dart` —
  matches financials' precedent 1:1 and is the smallest surface.

Pre-delete usage audit: `grep_search "GearRow|GearEmptyState"` on
`**/*.dart` returned only the definitions themselves plus their
consumers inside `gear_screen.dart`. No other file imports either
widget; deletion is safe.

## Cycle 10 revision — New/Used column + Band/Member owner toggle + price min width

**Trigger.** Tony's cycle-9 Step 6b test finding on the current PR
head: "The price column should be wide enough to display this number
'$9,999.99'. Include another column in the table for 'New/Used' and
in the New gear item, include a checkbox to denote if the item is
Used. In New Gear Item, under Owner, use a button toggle with the
labels 'Band' and 'Member'." Manager cycle-10 note authorized this as
an in-branch UX-polish + minor-additive-schema adjustment with all
product decisions pre-made and enumerated four required items in
scope.

**Scope classification.** Mostly in-branch UX-polish adjustment vs
the cycle-9 uncommitted PR head, with one minor additive schema
change: a new `is_used BOOLEAN NOT NULL DEFAULT FALSE` column on
`public.band_gear`. This column is a new in-branch scope addition
beyond the original `ARCHITECT_PLAN.md` (the base plan's table shape
in `20260905201000_create_band_gear.sql` does not include it), and
follows the same additive-column pattern cycle 4 used to add
`can_view_gear` to `contributor_permissions`
([supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql](../../../supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql))
— same one-statement `ALTER TABLE public.‹tbl› ADD COLUMN IF NOT
EXISTS ‹col› BOOLEAN NOT NULL DEFAULT FALSE;` shape, same fail-closed
default. The migration touches zero policies, zero triggers, zero
helper functions. No new architectural churn (no new provider, no new
named route, no new dependency, no new `SECURITY DEFINER` function,
no new RLS policy).

**Cycles 8 and 9 work rolled forward.** Cycles 8 (modal owner filter)
and 9 (column-width polish + cents-first price input) landed on disk
but have not been QA'd on their own passes. Cycle 10 keeps their disk
state intact and rolls both forward under the cycle-10 QA gate — QA
validates cycles 8+9+10 evidence together as one pass (see **Files
Modified → Cycle 10** for the pure cycle-10 diff on top of that
rolled state).

### Task breakdown (4 items)

**Item 1 — Price column min-width floor at `$9,999.99`.** In
`lib/features/gear/gear_screen.dart` inside `_GearEntriesList.build`
the Price column width is computed dynamically by scanning every
visible row's formatted price via `_measureText` and taking the max
against the `'Price'` header text. The bug Tony hit: when the current
filter yields no row ≥ `$9,999.99`, the column shrinks below what's
needed to render that placeholder-magnitude number. Fix: after the
existing max-scan loop, added a fixed minimum —

```dart
final minPriceWidth = _measureText('\$9,999.99', priceDataStyle);
if (minPriceWidth > maxPricePx) maxPricePx = minPriceWidth;
```

— same `priceDataStyle` local (`AppTextStyles.callout.copyWith(fontWeight:
FontWeight.w600)`) already used by the max-scan loop, and the
existing `+16` padding buffer at `final priceColumnWidth = maxPricePx
+ 16;` is preserved. Every other block in this file is untouched by
Item 1.

**Item 2 — New/Used column (client + schema).**

- **Migration.** New file
  `supabase/migrations/20260906160214_add_is_used_to_band_gear.sql`
  with a single `ALTER TABLE public.band_gear ADD COLUMN IF NOT
EXISTS is_used BOOLEAN NOT NULL DEFAULT FALSE;` statement plus a
  three-line comment header (`Migration: Add is_used to band_gear` /
  date / branch). Direct byte-for-shape mirror of
  `supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`
  (verified via structural `diff -u`; the only differences are the
  table name `contributor_permissions` → `band_gear` and the column
  name `can_view_gear` → `is_used`). Fail-closed default (`FALSE`
  = New) mirrors the `can_view_gear` precedent — no client can accidentally
  mark a gear item Used simply by omitting the field. Zero touches to
  RLS policies, triggers, or helper functions (T1.4 grep counts
  captured below in the T1.4 evidence section).

- **Model.** Added `final bool isUsed` field (default `false`) to
  `GearItem` in `lib/features/gear/models/gear_item.dart`, wired
  through the constructor (`this.isUsed = false,`), `fromJson`
  (`isUsed: (json['is_used'] as bool?) ?? false,`) with null-safe
  read that defaults to `false` when the `is_used` key is absent from
  the incoming payload, and `toJson` (`'is_used': isUsed,`). Owner
  shape invariant assert unchanged; `owner_type` / `owner_user_id` /
  `band_gear_owner_shape` handling unchanged. `GearItem` currently
  has no `copyWith` method and no consumer calls a `.copyWith(...)`
  on a `GearItem` instance anywhere in the codebase; adding one
  solely to wire `isUsed` when nothing reads it would violate the
  Engineer-mode anti-bloat guardrail ("A new model field, parameter,
  or `copyWith` entry nothing reads"). See Deviations From Plan for
  the intentional omission of the `copyWith` vector.

- **Repository.** No edit. `lib/features/gear/gear_repository.dart`'s
  `createGear` and `updateGear` methods take a `Map<String, dynamic>
data` payload and unpack every key into the Supabase insert /
  update; `is_used` flows through unchanged now that the form-sheet
  payload includes it. This matches Manager Item 2's own directive
  "The cache-layer round-trip is unchanged shape-wise."

- **Table column.** In `_GearEntriesList.build` / `_TableHeader` /
  `_GearTableRow` (`gear_screen.dart`):
  - Added `const _kNewUsedWidth = 72.0;` — compile-time const at the
    upper end of Manager's 64–72 px range. Fits the widest of `'New'`
    / `'Used'` at `AppTextStyles.callout` weight with the same +16
    px buffer other fixed columns use in this file. Chose 72 (over
    64–68) for a small safety margin on device-font-size overrides
    without pushing horizontal scroll boundary noticeably.
  - Included the new column in `_kFixedColumnsWidth` so the min-width
    calc reserves space for it:
    `const _kFixedColumnsWidth = _kFromWidth + _kOwnerWidth + _kNewUsedWidth;`.
  - Added a `SizedBox(width: _kNewUsedWidth, child: _HeaderCell(
    'New/Used', borderSide: borderSide))` header cell between the
    Owner and Price header cells in `_TableHeader.build`.
  - Added a matching row cell in `_GearTableRow.build` between the
    Owner cell and the Price cell, rendering `item.isUsed ? 'Used' :
    'New'` at `AppTextStyles.callout` with
    `context.colors.textSecondary` (identical style to the peer
    Owner cell), left-aligned, `maxLines: 1`, `overflow:
    TextOverflow.ellipsis`. Border side matches the other columns.

- **Model tests.** Extended
  `test/features/gear/gear_item_test.dart` with the three round-trip
  cases Manager specified: (a) `is_used = true` in the band-owned
  test source map, verifying `item.isUsed == true` and `json['is_used']
== true`; (b) `is_used = false` in the member-owned test source
  map, verifying `item.isUsed == false` and `json['is_used'] ==
  false`; (c) a new test
  `'fromJson defaults isUsed to false when is_used key is missing'`
  that constructs a source `Map` without any `is_used` key,
  constructs a `GearItem` via `GearItem.fromJson(source)`, and
  verifies both `item.isUsed == false` and
  `item.toJson()['is_used'] == false` — exercises the null-safe read
  path in `fromJson`. Total tests grow from 5 to 6.

**Item 3 — Used checkbox in the New / Edit Gear Item form.** In
`lib/features/gear/widgets/gear_form_sheet.dart`:

- Added `import 'package:bandroadie/components/ui/app_switch.dart';`.
- Added `bool _isUsed = false;` state field to `_GearFormSheetState`.
- Seeded `_isUsed = item?.isUsed ?? false;` in `initState`; in edit
  mode the switch pre-populates from the existing item's persisted
  value (Manager Item 3 spec: "Load-with-existing-value: when the
  sheet opens in edit mode with an existing `GearItem`, the checkbox
  pre-populates from `item.isUsed`").
- Rendered as a `Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [Text('Used', style: AppTextStyles.callout.copyWith(color:
context.colors.textPrimary)), AppSwitch(value: _isUsed, onChanged:
_isReadOnly || _isSaving ? null : (v) => setState(() => _isUsed =
v))])` block. Widget shape is a byte-for-shape match to the
  `is_1099_expected` toggle in
  `add_financial_entry_bottom_sheet.dart:717–725` — same `Row +
  MainAxisAlignment.spaceBetween`, same `Text(callout)` on the left,
  same `AppSwitch(value, onChanged)` on the right, same disable-on-
  saving / disable-on-read-only guard shape.
- **Placement note.** Manager Item 3 spec: "Placement: right after
  the `From` field, before the Owner control." The pre-cycle-10
  form-sheet order was Name → Owner → (optional Member picker) →
  From → Price → Purchased On — satisfying the specified placement
  requires moving the `From` field up so it sits immediately after
  `Name`, then inserting `Used` after `From` and before `Owner`.
  The new visual + source order is Name → From → Used → Owner (+
  optional Member picker) → Price → Purchased On. The reorder is
  a source-block move only — controllers, focus nodes, state, and
  payload logic for each field are unchanged; only the SizedBox
  spacers and the field blocks themselves shift.
- `_buildPayload()` extended with `'is_used': _isUsed`. All other
  payload keys (`name`, `purchased_on`, `purchased_from`,
  `price_cents`, `owner_type`, `owner_user_id`) unchanged.

**Item 4 — Owner control as Band/Member button toggle.** In
`lib/features/gear/widgets/gear_form_sheet.dart`, relabeled the two
existing `ButtonSegment<GearOwnerType>` labels in the existing
`SegmentedButton<GearOwnerType>`:

- `'Band-owned'` → `'Band'`
- `'Member-owned'` → `'Member'`

Did **not** replace the `SegmentedButton` widget itself, per
Manager Item 4's directive "use whichever button-toggle widget the
codebase already uses in similar form contexts — grep for
`SegmentedButton`, `ToggleButtons`, `CupertinoSegmentedControl`, or
any project-local `_ButtonToggle`/`_SegmentedToggle` widget first,
and reuse the same shape." and "Do NOT introduce a new custom toggle
widget if a peer already exists." `SegmentedButton` is Flutter's
built-in Material two-segment button toggle and is already the peer
widget used in this exact file (from cycle 3). `_SegmentedToggle` in
`lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
is a private (`_`-prefixed) file-local widget in that file and
cannot be reused directly from `gear_form_sheet.dart` without
extracting it into a shared component (which Manager did not
authorize as scope for a cycle-10 UX-polish pass).
`lib/components/ui/segmented_button_group.dart`'s
`SegmentedButtonGroup` is a display-only "label above value"
component without any selection-state concept and is not
appropriate for a discrete choice like Band/Member. Keeping
`SegmentedButton` gives the minimum-diff satisfaction of Tony's
"button toggle with the labels 'Band' and 'Member'" — the widget
content is unchanged; only the two segment labels change.

Owner-picker semantics unchanged: selecting `Band` clears
`_ownerUserId` (`if (_ownerType == GearOwnerType.band) { _ownerUserId
= null; }` fires inside the `onSelectionChanged` handler as before),
and the `_buildPayload` write path emits `'owner_user_id':
_ownerType == GearOwnerType.member ? _ownerUserId : null`. Selecting
`Member` reveals the existing member `DropdownButtonFormField<String>`
under the `if (_ownerType == GearOwnerType.member) ...` conditional
— verified reads from `_activeMembers()` → `membersProvider` with
the existing `status == 'active'` filter. The form-side "member
requires a selected member" validation in `_buildPayload`
(`showErrorSnackBar(context, message: 'Select a member when
ownership is set to member.')`) is unchanged. The DB
`band_gear_owner_shape` CHECK constraint from
`20260905201000_create_band_gear.sql` is unchanged.

**Off-limits list respected.** Cycle 10 touched only files inside
`lib/features/gear/`, `test/features/gear/`, and
`supabase/migrations/` — plus this doc report. No touch to
`lib/features/home/`, `lib/features/shell/`,
`contributor_permissions.dart`, `band_permissions.dart`,
`role_management_sheet.dart`, `.github/agents/*.md`, `PR_BODY.md`,
or `lib/shared/widgets/currency_input_field.dart` — matches the
Manager cycle-10 note's off-limits list byte-for-byte.

## Cycle 9 revision — column-width polish + cents-first price input

**Trigger.** Tony's cycle-8 Step 6b test finding on the current PR head:
"In Gear, make the table column width for Name 50 px wider, Purchased
on column should be wide enough to display the date without truncating,
change 'Purchased From' to 'From' and make that 50px wider. Also all
currency fields should have the decimal point built in. The placeholder
should be '$  0.00' and when typing, the first digit typed is displayed
like this '$  0.01', and the second number entered '$  0.12' and the
third '$  1.23' and so on." Manager cycle-9 note authorized this as an
in-branch UX-polish adjustment with all product decisions pre-made and
enumerated five required items in scope.

**Scope classification.** In-branch UX-polish adjustment vs the cycle-8
uncommitted PR head. No new architect decisions surfaced. No product /
UX choice the plan didn't anticipate. No architectural churn (no new
provider, no new named route, no new dependency, no new DB column, no
new migration, no JSON serialization change, no `GearItem` core-field
change, no rename of any DB column or Dart field \u2014 only the UI-visible
label `'Purchased From'` \u2192 `'From'` changed).

**Cycle 8 work rolled forward.** Cycle 8 landed the modal owner filter
on disk (`Set<String> ownerSelection` on `GearNotifier`,
`showModalBottomSheet<Set<String>>` in `gear_screen.dart`,
`_OwnerFilterModal` widget, `_ownerChipLabel` helper) but the pipeline
never called QA on cycle 8 as its own pass. Cycle 9 keeps cycle 8's
disk state intact and rolls it forward under the cycle-9 QA gate \u2014
QA validates both cycles' evidence together (see **Files Modified \u2192\nCycle 8+9 combined** and **Analyzer Results \u2192 Cycle 9 T1.1**).\n\n### Task breakdown (5 items)\n\n**Item 1 \u2014 Name column +50 px min width.** In\n`lib/features/gear/gear_screen.dart` bumped `_kMinNameWidth = 140.0`\n\u2192 `_kMinNameWidth = 190.0`. The Name column stays `Expanded` on wide\nscreens (unchanged `Expanded` semantics per Manager instruction); on\nthe narrowest supported screens where `constraints.maxWidth < minWidth`,\nthe extra 50 px pushes horizontal scroll to kick in 50 px earlier and\nlets Name occupy the extra reserved space. Matches the shape\nfinancials uses to shape its Category column (fixed contribution to\nthe min-width calc for a column that's `Expanded` on wide screens).\n\n**Item 2 \u2014 Purchased On column, dynamic width matching Price.** Dropped\nthe fixed `const _kPurchasedOnWidth = 110.0` constant. Replaced with a\ndynamically-computed `purchasedOnColumnWidth` inside\n`_GearEntriesList.build` using the identical `_measureText` block the\nPrice column already uses:\n\n```dart\ndouble maxPurchasedOnPx = _measureText('Purchased On', headerStyle);\nfor (final item in items) {\n  if (item.purchasedOn == null) continue;\n  final label = DateFormat('MMM d, y').format(item.purchasedOn!);\n  final w = _measureText(label, AppTextStyles.callout);\n  if (w > maxPurchasedOnPx) maxPurchasedOnPx = w;\n}\nfinal purchasedOnColumnWidth = maxPurchasedOnPx + 16;\n```\n\nMirrors\n[`lib/features/financials/financials_screen.dart` \u00a7\\_EntriesList](../../../lib/features/financials/financials_screen.dart)\nlines 668\u2013679 shape-for-shape. The 16 px buffer (`+16`) matches\nfinancials' exact buffer: `4 px cell padding \u00d7 2 sides + 8 px extra\nsafety margin`. Header style shared with the Price column\ncomputation via a new local `headerStyle` variable (previously\n`priceHeaderStyle`, renamed since both columns now consume it \u2014\nlocal variable, no API change). `_TableHeader` and `_GearTableRow`\nboth gained a required `purchasedOnColumnWidth` parameter alongside\nthe existing `priceColumnWidth`; the Purchased On row cell also\nswitched from `overflow: TextOverflow.ellipsis` to\n`softWrap: false, overflow: TextOverflow.visible` (dynamic width\nguarantees fit at all times, so ellipsis is unreachable and would only\nfire as a false-positive round-clip on a measured-fit cell).\n\n**Item 3 \u2014 \"Purchased From\" \u2192 \"From\" (+50 px wider).** Renamed the\nconstant `_kPurchasedFromWidth = 110.0` \u2192 `_kFromWidth = 160.0`\n(+50 px). Changed the `_TableHeader` cell label\n`_HeaderCell('Purchased From', ...)` \u2192 `_HeaderCell('From', ...)`.\nUpdated all references in `_GearTableRow` (`_kPurchasedFromWidth`\n\u2192 `_kFromWidth`). Updated the `_kFixedColumnsWidth` computation to\n`_kFromWidth + _kOwnerWidth` (no longer includes `_kPurchasedOnWidth`,\nwhich is now dynamic). Also renamed the form-sheet `AppTextField`\n`labelText: 'Purchased From'` \u2192 `labelText: 'From'` to keep the\nform label in sync with the table header. The underlying database\ncolumn `band_gear.purchased_from` and the Dart field\n`GearItem.purchasedFrom` are **not** renamed \u2014 UI label change only,\nas Manager instructed.\n\n**Item 4 \u2014 Cents-first price input.** Replaced the free-text\n`AppTextField` for Price in\n`lib/features/gear/widgets/gear_form_sheet.dart` with a POS-style\nformatter that reuses the shared `CurrencyInputController` (int-cents\nstorage) from `lib/shared/widgets/currency_input_field.dart`. New\nfield declarations:\n\n```dart\nlate CurrencyInputController _priceCents;\nlate TextEditingController _priceTextController;\n```\n\nSeeded in `initState` from `item?.priceCents ?? 0`:\n\n```dart\nfinal initialCents = item?.priceCents ?? 0;\n_priceCents = CurrencyInputController(initialCents);\n_priceTextController = TextEditingController(\n  text: initialCents > 0 ? _formatPriceCentsDisplay(initialCents) : '',\n);\n```\n\nEdit mode with an existing `priceCents` (> 0) renders `$  X.YZ`\nimmediately on open; empty state (0 or null) renders the placeholder\n`$  0.00` via `hintText`. The Price `AppTextField` now uses\n`keyboardType: TextInputType.number`,\n`hintText: '\\$  0.00'`, and\n`inputFormatters: [FilteringTextInputFormatter.digitsOnly,\n_GearCurrencyFormatter(_priceCents)]` \u2014 non-digit keystrokes are\nsilently rejected, and every digit shifts cents left. Backspace shifts\nright (divides by 10, drops the rightmost cent digit) per Tony's spec.\n\n`_GearCurrencyFormatter` is copied inline into `gear_form_sheet.dart`\nrather than reusing the shared `_CurrencyInputFormatter` because the\nshared class is `_`-private inside\n`lib/shared/widgets/currency_input_field.dart` and emits `$X.XX`\n(no double space) \u2014 financials' Amount column widths are calibrated\nagainst that exact output, and changing the shared display shape\nwould visibly shift financials' `_measureText` results. The Cycle 9\nplan explicitly authorizes this copy pattern: *\"copy the formatter\nclass inline in gear if financials keeps it private.\"* The copy\ndiffers from the shared class in exactly one respect \u2014 it calls the\nnew file-private helper\n\n```dart\nString _formatPriceCentsDisplay(int cents) {\n  final dollars = cents ~/ 100;\n  final centsPart = cents % 100;\n  final dollarStr = NumberFormat('#,##0').format(dollars);\n  return '\\$  $dollarStr.${centsPart.toString().padLeft(2, '0')}';\n}\n```\n\ninstead of `controller.formattedValue`. Digit-to-display trace matches\nTony's spec exactly:\n\n| Input digits | `_priceCents.cents` | Displayed |\n|--------------|---------------------|-----------|\n| (empty)      | 0                   | (placeholder `$  0.00`) |\n| `1`          | 1                   | `$  0.01` |\n| `12`         | 12                  | `$  0.12` |\n| `123`        | 123                 | `$  1.23` |\n| `1234`       | 1234                | `$  12.34` |\n| `12345`      | 12345               | `$  123.45` |\n| `123456`     | 123456              | `$  1,234.56` |\n| `1234567`    | 1234567             | `$  12,345.67` |\n\n**Item 5 \u2014 Validation compatibility.** The cycle-3 form validation\ncontract keeps working unchanged. Empty state (0 cents) is treated as\nno-price and maps to `null` in the payload:\n\n```dart\nint? _parsePriceCents() {\n  final cents = _priceCents.cents;\n  return cents == 0 ? null : cents;\n}\n```\n\nThe old \"Price must be a valid non-negative amount\" snackbar branch is\nremoved \u2014 the new formatter guarantees a valid non-negative int at all\ntimes (no free-text price path can produce an invalid value), so that\ncheck is now unreachable. Required/optional status of the field is\nunchanged (still optional). Save writes the int (or `null`) directly to\nthe payload's `price_cents` key. Load in edit mode with existing\n`priceCents` correctly renders `$  X.YZ`; load with `null` renders the\nplaceholder.\n\n### Files touched (Cycle 9)\n\n- `lib/features/gear/gear_screen.dart` \u2014 column widths + header label\n  (Items 1, 2, 3).\n- `lib/features/gear/widgets/gear_form_sheet.dart` \u2014 cents-first\n  price input (Item 4), `From` label rename (Item 3), validation\n  helper simplification (Item 5).\n\n### Files not touched (would have been in scope if the change had\nrequired them)\n\n- `lib/features/gear/models/gear_item.dart` \u2014 no pure-Dart display\n  helper needed. `priceCents` field already existed on the model since\n  cycle 3; no JSON serialization change.\n- `lib/features/gear/gear_controller.dart` \u2014 no filter-code helper\n  needed for the wider Name column; column widths live entirely in the\n  screen file.\n- `test/features/gear/gear_item_test.dart` \u2014 no new testable helper on\n  the model (per Manager cycle-9 instruction \"extend only if you add a\n  testable helper (e.g., a cents-formatter). Otherwise leave it alone\").\n  `_formatPriceCentsDisplay` and `_GearCurrencyFormatter` are\n  file-private to `gear_form_sheet.dart`; unit-testing them would\n  require widening their visibility, which the plan does not authorize.\n  Existing model tests re-run under T1.2: 5/5 pass.\n\n## Cycle 7 revision \u2014 Gear screen table + filters (Financials parity)

**Trigger.** Tony's cycle-7 Step 6b test finding on the current PR head:
"the gear screen should match the financials screen, including the
filters. Gear should be listed in a table to match financials instead
of cards." Manager cycle-7 note authorized this as an in-branch UX-scope
adjustment with all product decisions pre-made ("Product decisions are
already made by Tony — implement the mirror; don't second-guess it").

**Scope classification.** In-branch UX-scope adjustment vs the base
`ARCHITECT_PLAN.md`. The plan's Proposed Solution section 1 explicitly
called for a **list of cards** ("List UI, not a literal HTML table.
… Every peer feature (contacts, venues, songs, members) uses a
scrolling list of cards/rows; using the same idiom keeps the UI
consistent across screen widths and matches the design tokens already
in the codebase. Row content: name (primary), owner (secondary), price

- purchase date (tertiary). Purchased-from surfaces on the detail/edit
  sheet."). Cycle 7 supersedes that decision with a table-based screen
  mirroring `lib/features/financials/financials_screen.dart`, per Tony's
  review-time direction relayed by Manager cycle-7. All other plan
  sections (schema, RLS, RBAC, contributor visibility gate) roll forward
  unchanged.

**Precedent mirrored.** `lib/features/financials/financials_screen.dart`
(1210 lines). Section-for-section:

- Screen shell → same `Scaffold(backgroundColor: context.colors.background)
→ SafeArea → Stack → Column`, `BackOnlyAppBar` at top, title row
  `'Gear'` in `AppTextStyles.pageTitle` on the left and
  `TextButton.icon(icon: Icon(AppIcons.add), label: 'Add', style:
TextButton.styleFrom(foregroundColor: AppColors.primary))` on the
  right when `canManageGear == true`. Add button `onPressed` guards on
  `state.isLoading` matching financials.
- Filter 1 (owner type) → `_OwnerFilterToggle` — 3 segments (**All**,
  **Band-owned**, **Member-owned**) using the same sliding-indicator
  visual as financials' `_ViewModeToggle`, extended from 2 to 3 modes
  via the same `Alignment(-1.0 + (2.0 * currentIndex / (_modes.length -
1)), 0.0)` formula financials already uses (which handles N segments
  generically — 3 segments produce indices 0→-1.0, 1→0.0, 2→1.0). Same
  `context.colors.surface` outer background, same `AppColors.primary`
  sliding indicator, same `AppTextStyles`/`AppFontSizes.subhead`
  weights, same `HapticFeedback.selectionClick()` on tap.
- Filter 2 (date filter) → `_DateFilterRow` + `_FilterChip` copied from
  financials verbatim except `FinancialDateFilter → GearDateFilter`.
  Options set (**All Time**, **This Year**, **This Month**, **Custom
  Range…**) matches financials. Field being filtered = `purchased_on`.
- Table → `_GearEntriesList` mirroring financials' `_EntriesList`:
  `LayoutBuilder → SingleChildScrollView(horizontal) → SizedBox(width:
tableWidth) → Column(header + rows)`. Header via `_TableHeader` +
  `_HeaderCell`; rows via `_GearTableRow` reusing the same
  `IntrinsicHeight → Row(crossAxisAlignment: stretch)` +
  `BorderSide(color: context.colors.border)` right-borders financials
  uses. Column widths: **Name** = `Expanded` (variable), **Purchased
  On** = 110px, **Purchased From** = 110px, **Owner** = 110px, **Price**
  = dynamically-sized via the same `_measureText` pattern financials
  uses for its Amount column, right-aligned. `_kFixedColumnsWidth`
  calculation mirrors financials'.
- Empty state → inline `_EmptyState` mirroring financials'
  `_EmptyState` (icon + heading + subhead + primary CTA). CTA
  (`TextButton.icon` with `AppIcons.add`, label `Add Gear`) rendered
  only when `canManageGear && onAdd != null`. Icon: `AppIcons.library`
  in `context.colors.textMuted` matching financials' `AppIcons.music`
  weight/color slot.
- Loading state → `Center(child: CircularProgressIndicator(color:
AppColors.primary))` verbatim.
- Error state → inline `_ErrorState({required this.message})` mirroring
  financials' verbatim.

**Add / edit flow.** Tapping a table row calls
`_openForm(item: item, canManageGear: canManageGear)` which reuses the
existing cycle-3 `GearFormSheet.show(...)` bottom sheet. Verified the
form sheet already supports both edit mode (`item != null`) and
read-only mode (`canManageGear == false`) — cycle 3 shipped that. Per
Manager cycle-7 note "keep gear's single form sheet if it already
supports read-only + edit modes; do NOT introduce a new details sheet
as separate scope", no new details sheet was introduced.

**Bottom actions row.** Skipped per Manager cycle-7 note ("For gear v1
there is nothing analogous to add … Do NOT add a bottom actions row").

**Column set decision — Owner label copy.** Manager cycle-7 note:
"Label is 'Band' for band-owned, or the member's first name + last
initial for member-owned." The pre-cycle-7 `_ownerLabel` in
`gear_screen.dart` returned `'Band-owned'`; cycle 7 rewrites it to
return `'Band'` matching the terser Manager-specified copy. The
member branch is unchanged: `firstName + ' ' + lastName[0] + '.'`
with graceful fallback to first-only / last-only / full display name.

**Form-sheet not touched.** `lib/features/gear/widgets/gear_form_sheet.dart`
was not modified this cycle. Cycle 3 already shipped edit mode
(`_isEditMode = widget.item != null`) and read-only mode (`_isReadOnly
= !widget.canManageGear`) so the table-row tap flow works with zero
form-sheet changes.

**Off-limits list respected.** Cycle 7 touched only files inside
`lib/features/gear/` plus the doc-report update. No touch to
`lib/features/home/`, `lib/features/shell/`, `supabase/migrations/`,
`contributor_permissions.dart`, `band_permissions.dart`,
`role_management_sheet.dart`, `.github/agents/*.md`, or `PR_BODY.md` —
matches the Manager cycle-7 note's off-limits list byte-for-byte.

## Cycle 5 addition — Quick Actions surfacing

**Trigger.** Tony tested PR #261 and reported: "i don't see a button for
Gear under Quick actions." This is a REQUIRES CHANGES finding from the
Step 6b test.

**Scope classification.** In-branch, additive-only scope extension. The
base `ARCHITECT_PLAN.md` surfaced Gear only via the side drawer (Task 15
in `lib/features/home/widgets/side_drawer.dart` + `lib/features/shell/
app_shell.dart`); Quick Actions surfacing was not part of the original
plan. No architect re-diagnosis was required — the precedent is
already in-repo for Financials, and this cycle mirrors that precedent
exactly. Manager cycle-5 note authorizes this as the equivalent scope
addition, mirroring the Financials-precedent QuickActionsRow wiring.

**Financials precedent mirrored exactly.** In
`lib/features/home/home_tab_content.dart`, the shipped Financials wiring is:

- `_handleOpenFinancials` pushes `const FinancialsScreen()` via
  `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const
FinancialsScreen()))`.
- `canViewFinancials` is read from `permissionsAsync.when(...)` in the
  `build` method (fail-closed defaults `false`).
- `canViewFinancials` is threaded as a `required` parameter through
  `_buildContentState`.
- Inside the Quick Actions `Builder`, `hasAnyButton` includes the
  Financials-visibility term, and the `QuickActionsRow` is called with
  `onFinancials: canViewFinancials ? _handleOpenFinancials : null` and
  `showFinancials: canViewFinancials`.

Cycle 5 adds the identical shape for Gear:

- `_handleOpenGear` pushes `const GearScreen()` via `Navigator.of(context)
.push(MaterialPageRoute(builder: (_) => const GearScreen()))` — literal
  mirror.
- `canViewGear` read from `permissionsAsync.when(...)` immediately after
  `canViewFinancials`.
- `canViewGear` threaded as a `required` parameter through
  `_buildContentState` immediately after `canViewFinancials`.
- `hasAnyButton` extended with `|| canViewGear` so the section still
  renders for a contributor with only the gear toggle enabled.
- `QuickActionsRow` receives `onGear: canViewGear ? _handleOpenGear : null`
  and `showGear: canViewGear`.

**QuickActionsRow parity.** `lib/features/home/widgets/quick_actions_row.
dart` gains `onGear` / `showGear` alongside the existing
`onFinancials` / `showFinancials`, with the Gear button appended after
the Financials button in `build`. Constructor parameters follow the same
positional/named parity. `hasVisibleButtons` now includes `|| showGear`.
Label is `'Gear'` (no `+` prefix — matches Financials which opens an
existing screen rather than creating a new entity).

**Files NOT touched, per Manager cycle-5 note precedent.**
`lib/features/home/home_screen.dart` and
`lib/features/home/widgets/empty_home_state.dart` — verified via
`grep -F 'Financials'` on both files: neither wires Financials. Cycle 5
matches that precedent and does not introduce Gear wiring where
Financials has none. `lib/features/home/widgets/side_drawer.dart` and
`lib/features/shell/app_shell.dart` remain byte-identical to cycle 3 —
Gear drawer navigation is untouched.

**Off-limits list respected.** Per `ARCHITECT_PLAN.md#L656`,
`lib/features/home/` is not on the off-limits list; `pubspec.yaml`,
`main.dart`, `analysis_options.yaml`, `supabase/**`, and every platform
directory remain untouched. No new dependency, no new named route, no new
provider.

**Cycle 5 pre-existing lint sweep note.** The T1.1 expanded file list
(`home_tab_content.dart` + `quick_actions_row.dart`) surfaced 7 pre-
existing info-level lints that the cycle-4 T1.1 command did not run
against because those files were not in cycle 4's file list. Per the
Engineer mode instruction "pre-existing violation in a file you did touch
does — fix it if it's trivial, or report it if fixing it would exceed
scope," all 7 were fixed as trivial one-line no-op equivalents (each
analyzer suggestion is a provably-safe rewrite of semantically identical
code):

- `home_tab_content.dart` line 391 (was): `fullscreenDialog: false` on
  the `MaterialPageRoute` in `_handleOpenFinancials` — removed (matches
  default). Kept `_handleOpenGear` symmetric (also without
  `fullscreenDialog: false`) — that removal is my own cycle-5 self-audit
  fix.
- `home_tab_content.dart` line 730 (was): `Container(color:)` in
  `_buildLoadingState` → `ColoredBox(color:)`.
- `home_tab_content.dart` line 775 (was): `Container(color:)` in
  `_buildErrorState` → `ColoredBox(color:)`.
- `home_tab_content.dart` line 820 (was): `variant:
AppButtonVariant.primary` on `AppButton` in `_buildErrorState` — removed
  (verified default in `lib/components/ui/app_button.dart:36`).
- `home_tab_content.dart` line 852 (was): `Container(color:)` in
  `_buildContentState` → `ColoredBox(color:)`.
- `home_tab_content.dart` line 911 (was): `const Duration(milliseconds:
0)` on the first `_AnimatedCardEntrance.delay` → `Duration.zero`
  (canonical form; `_AnimatedCardEntrance.delay` is required so the arg
  itself cannot be removed).
- `quick_actions_row.dart` line 114 (was): `width: 1` on `BorderSide`
  inside `_buildQuickActionButton` — removed (default is 1).

All fixes documented here for QA to distinguish from the additive gear-
surfacing changes.

## Cycle 6 revision — drawer entry removed

**Trigger.** Tony reviewed the cycle-5 QA-APPROVED state (PR #261 6b
iteration) and directed via Manager cycle-6 note: "remove 'Gear' from the
menu. It should only be in the Quick Actions section." This is a
revert-only cycle: cycle 5's Quick Actions surfacing (the shipped answer
to Tony's earlier PR #261 6b test finding) stays exactly as it landed;
cycle 3's side-drawer surfacing is fully removed so Gear surfaces via
Quick Actions only.

**Scope classification.** In-branch, subtractive-only revert. No new
files created, no new code introduced. Manager cycle-6 note explicitly
authorized the file-list contraction and provided the two `git checkout
main -- ...` commands used to execute the revert.

**Reverts executed.**

- `lib/features/home/widgets/side_drawer.dart` restored to main tip via
  `GIT_OPTIONAL_LOCKS=0 git checkout main -- lib/features/home/widgets/side_drawer.dart`.
  Net cycle-6 diff vs main: 0. Removes cycle-3 additions listed in the
  Files Modified section above.
- `lib/features/shell/app_shell.dart` restored to main tip via
  `GIT_OPTIONAL_LOCKS=0 git checkout main -- lib/features/shell/app_shell.dart`.
  Net cycle-6 diff vs main: 0. Removes cycle-3 additions listed in the
  Files Modified section above.

**Files NOT touched this cycle, per Manager cycle-6 step 3.** All cycle-4
RBAC files (`contributor_permissions.dart`, `band_permissions.dart`,
`role_management_sheet.dart`), all cycle-5 Quick Actions files
(`home_tab_content.dart`, `quick_actions_row.dart`), all
`lib/features/gear/*`, `test/features/gear/*`, all four gear migrations,
and `.github/agents/*.md` are untouched by cycle 6.

**Cycle-6 T1.1 scope contraction — Manager Option D decision.** After
the reverts, `side_drawer.dart` and `app_shell.dart` carry 0 diff vs
main and are no longer feature-touched files. Per Manager Option D
decision (cycle-6 finalization note), T1.1 is now scoped to the 7 files
this feature actually touches, dropping `side_drawer.dart` and
`app_shell.dart` from the command. This matches the standard treatment
of every other unmodified file in the repo: pre-existing lints in files
a feature doesn't touch are not that feature's gate. Not a deviation —
it's the same rule QA applies to every other file the feature leaves
untouched. Not procedural overhead — recording an 8-lint baseline as a
Deviation C would have been overhead purely to keep an outdated 9-item
gate list intact; contracting the gate to match the actual touched-files
scope is the cleaner and correct end state.

**Cycle-6 end state, feature-touched files (diff-vs-main):**

- `lib/features/gear/**` — all cycle-3-created files (unchanged).
- `lib/features/home/home_tab_content.dart` — cycle-5 Quick Actions
  wiring + 5 pre-existing lint sweeps (unchanged from cycle 5).
- `lib/features/home/widgets/quick_actions_row.dart` — cycle-5
  `onGear` / `showGear` additions + 1 pre-existing lint sweep
  (unchanged from cycle 5).
- `lib/features/members/permissions/band_permissions.dart` — cycle-4
  `canViewGear` body swap (unchanged from cycle 4).
- `lib/features/members/permissions/contributor_permissions.dart` —
  cycle-4 `canViewGear` sub-permission field (unchanged from cycle 4).
- `lib/features/members/widgets/role_management_sheet.dart` — cycle-4
  "Can view gear" toggle + `_permissionsEqual` extension (unchanged from
  cycle 4).
- `supabase/migrations/20260905201000_create_band_gear.sql` — base gear
  migration (unchanged from cycle 3).
- `supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`
  — cycle-4 sub-permission column (unchanged from cycle 4).
- `supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql`
  — cycle-4 RPC fix (unchanged from cycle 4).
- `supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql`
  — cycle-4 RLS helper + SELECT policy swap (unchanged from cycle 4).
- `test/features/gear/gear_item_test.dart` — cycle-3 model tests
  (unchanged).

## Analyzer Results

### Cycle 10 T1.1 — clean (7-item scope per Manager Option D, preserved)

Command run:

```
flutter analyze lib/features/gear lib/features/home/home_tab_content.dart lib/features/home/widgets/quick_actions_row.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 7 items...
No issues found! (ran in 2.9s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`. Re-run post-`dart format` on the 4 cycle-10
touched Dart files (`gear_screen.dart`, `widgets/gear_form_sheet.dart`,
`models/gear_item.dart`, `test/features/gear/gear_item_test.dart` — all
0 files reformatted): `No issues found! (ran in 1.8s)`. `dart fix
--dry-run` on the full package: zero suggestions matching any
cycle-10 file (`lib/features/gear/**` and
`test/features/gear/gear_item_test.dart` do not appear in the
read-only preview's suggestions list). Migration SQL is not part of
`dart fix`.

### Cycle 9 T1.1 — clean (7-item scope per Manager Option D, preserved)

Command run:

```
flutter analyze lib/features/gear lib/features/home/home_tab_content.dart lib/features/home/widgets/quick_actions_row.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 7 items...
No issues found! (ran in 2.3s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`. Also re-run post-`dart format`: still
`No issues found!` (ran in 2.3s). `dart fix --dry-run` on the two
cycle-9-touched files (`gear_screen.dart`, `gear_form_sheet.dart`)
reports no matching entries.

**Intermediate lint sweep.** The first cycle-9 analyzer pass surfaced one
info-severity lint on the newly-added `_GearCurrencyFormatter`—
`avoid_redundant_argument_values` at `gear_form_sheet.dart:513:15` on
`return const TextEditingValue(text: '', selection:
TextSelection.collapsed(offset: 0));` (the default `text` value on
`TextEditingValue` is `''`). Fixed in place by swapping to the constant
`TextEditingValue.empty` static — semantically identical, one line
shorter, and passes the analyzer at every severity. Note: the shared
`_CurrencyInputFormatter` in `currency_input_field.dart` carries the
same no-op idiom, but that file is not on the cycle-9 T1.1 scope so its
violation isn't surfaced against Gear's gate; Gear's fresh-copy of the
formatter has to pass the analyzer independently.

### Cycle 7 T1.1 — clean (7-item scope per Manager Option D, preserved)

Command run:

```
flutter analyze lib/features/gear lib/features/home/home_tab_content.dart lib/features/home/widgets/quick_actions_row.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 7 items...
No issues found! (ran in 2.8s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`. `dart fix --dry-run` on both cycle-7-touched
files (`gear_controller.dart`, `gear_screen.dart`) reports
`Nothing to fix!`.

**Intermediate lint sweep.** The first analyzer pass after the rewrite
surfaced 5 info-severity lints in the newly-rewritten
`gear_screen.dart` (3 × `avoid_redundant_argument_values` on
`BorderSide(width: 1.0)` copied verbatim from financials, 1 ×
`avoid_redundant_argument_values` on `DateTime(now.year, now.month, 1)`
default `day = 1` copied from financials, 1 × `avoid_redundant_argument_values`
on `onSurface: Colors.white` inside `const ColorScheme.dark(...)`
copied from financials, 1 × `prefer_const_constructors` on
`_HeaderCell('Price', textAlign: TextAlign.right)` — that call site
has no non-const args). All 5 are provably-safe no-op equivalents.
Note: financials carries the identical lints in its own file, but
financials is not on the T1.1 file list this cycle (per Manager
Option D), so its violations aren't surfaced against gear's gate. My
gear rewrite is legally fresh to the analyzer, so I fixed every one
in-scope: dropped the redundant `width: 1.0`, dropped the redundant
`day: 1`, dropped the redundant `onSurface: Colors.white`, added
`const` to the Price header cell. Second analyzer pass:
`No issues found!`.

### Cycle 6 T1.1 — clean (7-item scope per Manager Option D)

Command run:

```
flutter analyze lib/features/gear lib/features/home/home_tab_content.dart lib/features/home/widgets/quick_actions_row.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 7 items...
No issues found! (ran in 2.9s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`. Scope reflects Manager Option D decision:
`side_drawer.dart` and `app_shell.dart` are byte-identical to main
(0 diff) and no longer feature-touched, so per the standard
"pre-existing lints in files a feature doesn't touch are not that
feature's gate" rule they are out of scope for this feature's T1.1.

### Cycle 6 T1.1 — earlier 9-item run (retained for evidence)

The earlier 9-item T1.1 run (executed before Manager's Option D
decision) surfaced 8 pre-existing info-severity lints resident on main
tip (`80bad0a`) in `side_drawer.dart` (2 × `use_colored_box`) and
`app_shell.dart` (3 × `prefer_const_constructors` + 3 ×
`avoid_redundant_argument_values`). Isolated audit against main-tip
content of both files returned identical output at the same locations,
confirming the lints pre-date the `feature/band-gear-management` branch
entirely. Manager Option D contracts the T1.1 command to the 7 files
this feature actually modifies, which resolves the gate cleanly without
introducing new suppression collateral or a new deviation.

### Cycle 5 T1.1 (retained for evidence, unchanged)

Command run:

```
flutter analyze lib/features/gear lib/features/home/widgets/side_drawer.dart lib/features/home/widgets/quick_actions_row.dart lib/features/home/home_tab_content.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart lib/features/shell/app_shell.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 9 items...
No issues found! (ran in 2.9s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`. `dart fix --dry-run` on both cycle-5-touched
files (`home_tab_content.dart`, `quick_actions_row.dart`) reports
`Nothing to fix!`.

### Cycle 4 T1.1 (retained for evidence)

Command run:

```
flutter analyze lib/features/gear lib/features/home/widgets/side_drawer.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart lib/features/shell/app_shell.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 7 items...
No issues found! (ran in 3.0s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`.

## Test Results

### Cycle 10 T1.2

Command run: `flutter test test/features/gear/gear_item_test.dart`

Output:

```
00:00 +0: loading /Users/tonyholmes/apps/bandroadie/test/features/gear/gear_item_test.dart
00:00 +0: GearOwnerType fromDbValue maps known values
00:00 +1: GearOwnerType fromDbValue falls back to band for unknown values
00:00 +2: GearItem fromJson/toJson round-trip for band-owned item
00:00 +3: GearItem fromJson/toJson round-trip for member-owned item
00:00 +4: GearItem fromJson defaults isUsed to false when is_used key is missing
00:00 +5: GearItem constructor enforces owner shape invariant
00:00 +6: All tests passed!
```

6/6 pass. Cycle 10 extended the two existing `fromJson/toJson`
round-trip tests to cover `is_used = true` (band-owned) and
`is_used = false` (member-owned), and added one new test
`'fromJson defaults isUsed to false when is_used key is missing'`
that verifies the null-safe read path in `fromJson` when the
`is_used` key is absent from the incoming JSON payload — tests grow
from 5 to 6 per Manager Item 2 spec.

### Cycle 10 T1.3 (not re-run)

Per Manager cycle-10 instruction: "Do NOT re-run T1.3 (accepted
Deviation A still applies)." Cycle 4's T1.3 result rolls forward.
No cycle-10 change touches the auth login screen or its test file.
No cycle-10 change adds any new widget test.

### Cycle 9 T1.2

Command run: `flutter test test/features/gear/gear_item_test.dart`

Output:

```
00:00 +0: loading /Users/tonyholmes/apps/bandroadie/test/features/gear/gear_item_test.dart
00:00 +0: GearOwnerType fromDbValue maps known values
00:00 +1: GearOwnerType fromDbValue falls back to band for unknown values
00:00 +2: GearItem fromJson/toJson round-trip for band-owned item
00:00 +3: GearItem fromJson/toJson round-trip for member-owned item
00:00 +4: GearItem constructor enforces owner shape invariant
00:00 +5: All tests passed!
```

5/5 pass. Cycle 9 did not change `models/gear_item.dart` (the only
model-level source under test), so the pre-existing model tests
exercise the unchanged `GearItem` shape. Per the Manager cycle-9
spec ("extend only if you add a testable helper (e.g., a cents-
formatter). Otherwise leave it alone"), no new tests added —
`_formatPriceCentsDisplay` and `_GearCurrencyFormatter` are file-
private to `gear_form_sheet.dart` and not exportable for a unit test
without widening their visibility, which the plan does not authorize.
(`CurrencyInputController` is already exported and used by financials;
its behavior is transitively exercised there.)

### Cycle 9 T1.3 (not re-run)

Per Manager cycle-9 instruction: "Do NOT re-run T1.3 (accepted
Deviation A still applies)." Cycle 4's T1.3 result rolls forward. No
cycle-9 change touches the auth login screen or its test file. No
cycle-9 change adds any new widget test.

### Cycle 7 T1.2

Command run: `flutter test test/features/gear/gear_item_test.dart`

Output: `00:00 +5: All tests passed!` — 5/5 pass. Cycle 7's controller

- screen rewrite did not change `models/gear_item.dart` or the model
  tests, so the pre-existing model-level tests exercise the unchanged
  `GearItem` shape. No new pure-Dart helper was added on the model, so
  no new test was added to `test/features/gear/gear_item_test.dart` this
  cycle (per Manager cycle-7 note: "extend with tests for any new
  pure-Dart helper you add on the model … Don't test the screen widget"
  — nothing new on the model to test). Filter logic lives on
  `GearState.filteredItems`, parallel to `FinancialsState.filteredEntries`;
  both are currently untested. Recorded here for QA traceability.

### Cycle 7 T1.3 (not re-run)

Per Manager cycle-7 note: "Do NOT re-run T1.3 (accepted Deviation A
still applies)." Cycle 4's T1.3 result rolls forward. No cycle-7 change
touches the auth login screen or its test file. No cycle-7 change adds
any new widget test.

### Cycle 6 T1.2

Command run: `flutter test test/features/gear/gear_item_test.dart`

Output: `00:00 +5: All tests passed!` — 5/5 pass. Cycle 6 introduced no
code change to `lib/features/gear/**` or to the test file, so this run
confirms the revert did not regress the model-level tests transitively.

### Cycle 5 T1.2 — retained for evidence (unchanged)

Command run: `flutter test test/features/gear/gear_item_test.dart`

Output: `00:02 +5: All tests passed!` — 5/5 pass. No cycle-5 code paths
regressed the gear model unit tests.

### Cycle 5 T1.3 (not re-run)

Per Manager cycle-5 note: "Do NOT re-run T1.3 unless something breaks —
the accepted Deviation A still applies." Cycle 4's T1.3 result rolls
forward. No cycle-5 change touches the auth login screen or its test
file. No cycle-5 change adds any new widget test.

### Cycle 4 T1.2 / T1.3 (retained for evidence)

Commands run:

- `flutter test test/features/gear/gear_item_test.dart` (T1.2)
- `flutter test` (T1.3)

Results:

- T1.2 `flutter test test/features/gear/gear_item_test.dart`:
  `00:01 +5: All tests passed!` — 5/5 pass.
- T1.3 `flutter test`: `00:26 +218 -1: Some tests failed.` The single
  failure is:

  ```
  /Users/tonyholmes/apps/bandroadie/test/features/auth/login_screen_demo_button_test.dart: Test A: "Check Out the Demo Band" button is visible on LoginScreen
  ```

  This is Deviation A — the pre-existing, unrelated typo mismatch pre-
  approved by Tony's cycle-3 review. `lib/features/auth/login_screen.dart:657`
  renders `'Check out the demo band'` (lowercase `out`) while the test
  asserts title case; both files were last touched together in commit
  `5cd1996` and are unmodified by `feature/band-gear-management`. All 218
  other tests pass, satisfying the T1.3 gate per the plan's accepted-
  deviation clause.

## T1.4 Static SQL Evidence

Commands run in `supabase/migrations/`.

### 20260906160214_add_is_used_to_band_gear.sql (cycle 10, new this cycle)

File contents (verified via `cat`):

```sql
-- Migration: Add is_used to band_gear
-- Date: 2026-09-06
-- Branch: feature/band-gear-management

ALTER TABLE public.band_gear
  ADD COLUMN IF NOT EXISTS is_used BOOLEAN NOT NULL DEFAULT FALSE;
```

Static grep counts (verified via BSD `grep`):

- `^ALTER TABLE public\.band_gear$` header line present: **1**
- `^  ADD COLUMN IF NOT EXISTS is_used BOOLEAN NOT NULL DEFAULT FALSE;$`
  clause line present: **1**
- Semicolons (SQL-statement terminators): **1**
- `CREATE POLICY` / `DROP POLICY` / `ALTER POLICY` occurrences: **0**
- `CREATE TRIGGER` / `DROP TRIGGER` occurrences: **0**
- `CREATE OR REPLACE FUNCTION` / `DROP FUNCTION` occurrences: **0**
- Non-blank, non-comment SQL lines: **2** (the `ALTER TABLE` header
  line + the `ADD COLUMN IF NOT EXISTS ...` clause line — together
  one SQL statement)

Structural equivalence check vs the cycle-4 precedent
`supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`
via `diff -u <(grep -Ev '^\s*(--|$)' precedent) <(grep -Ev '^\s*(--|$)' new)`:
the two files differ **only** in the table name
(`contributor_permissions` → `band_gear`) and the column name
(`can_view_gear` → `is_used`). Same one-statement `ALTER TABLE
public.‹tbl› ADD COLUMN IF NOT EXISTS ‹col› BOOLEAN NOT NULL DEFAULT
FALSE;` shape, same fail-closed default, same three-line comment
header (`-- Migration: Add ‹col› to ‹tbl›` / date / branch).

Satisfies Manager cycle-10 T1.4 spec verbatim: "grep-verify exactly
one `ALTER TABLE public.band_gear ADD COLUMN IF NOT EXISTS is_used
BOOLEAN NOT NULL DEFAULT FALSE;` and zero touches to policies /
triggers / helper functions."

### 20260905201000_create_band_gear.sql (base, unchanged from cycle 3)

- `^CREATE POLICY`: **4** (SELECT / INSERT / UPDATE / DELETE)
- `ENABLE ROW LEVEL SECURITY`: **1**
- `^CREATE TRIGGER set_band_gear_updated_at`: **1**
- `^CREATE INDEX idx_band_gear_`: **2** (`_band_id`, `_owner_user_id`)
- `CONSTRAINT band_gear_owner_shape CHECK`: **1**
- `price_cents.*CHECK`: **1** (`price_cents INTEGER CHECK (price_cents IS
NULL OR price_cents >= 0)`)
- `REFERENCES public.bands(id) ON DELETE CASCADE`: **1**
- `REFERENCES public.users(id) ON DELETE SET NULL`: **2**
- `SECURITY DEFINER`: **0**
- `^GRANT|^REVOKE`: **0** (base migration relies solely on RLS)

### 20260906120000_add_can_view_gear_to_contributor_permissions.sql

- `ADD COLUMN IF NOT EXISTS can_view_gear BOOLEAN NOT NULL DEFAULT FALSE`:
  **1**
- Body is a single `ALTER TABLE public.contributor_permissions` statement;
  no other DDL/DML.

### 20260906120001_fix_update_member_role_can_view_gear.sql

- `CREATE OR REPLACE FUNCTION public.update_member_role`: **1**
- `^GRANT EXECUTE`: **1** (`GRANT EXECUTE ON FUNCTION
public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;`)
- `can_view_gear = COALESCE`: **1** (single new SET-clause line
  `can_view_gear = COALESCE((p_sub_permissions->>'can_view_gear')::boolean,
FALSE),`)
- Header carries `LANGUAGE plpgsql / SECURITY DEFINER`; body opens with
  `SET search_path = public;` per Architect guardrail.

### 20260906120002_fix_band_gear_select_rbac.sql

- `CREATE OR REPLACE FUNCTION public.check_gear_view_permission`: **1**
- `SECURITY DEFINER`: **1**
- `SET search_path = public`: **1**
- `REVOKE ALL ON FUNCTION public.check_gear_view_permission(UUID) FROM
PUBLIC, anon`: **1**
- `GRANT EXECUTE ON FUNCTION public.check_gear_view_permission(UUID) TO
authenticated`: **1**
- `DROP POLICY IF EXISTS "Band members can view gear" ON public.band_gear`:
  **1**
- `CREATE POLICY "Band members can view gear" ON public.band_gear`: **1**
- `USING (public.check_gear_view_permission(band_id))`: **1**
- `FOR INSERT|FOR UPDATE|FOR DELETE`: **0** — INSERT / UPDATE / DELETE
  policies untouched, as required.

## T1.5 — Isolated Migration Apply-Check

**Deferred to Tier 2** per accepted Deviation B. The isolated apply-check
remains blocked by the repo-wide broken-migration-chain infra defect at
`073_fix_gig_responses_unique_constraint.sql` (see plan's KNOWN INFRA
BLOCKER section). Per the demo-band precedent
(`docs/features/interactive-demo-band-experience/QA_REPORT.md#L15`), Tony
runs the migration apply at production apply time as part of the Rollout
Strategy. This deferral is pre-approved and does not block APPROVED.

## Code Efficiency/Bloat Check

Cycle 9 additions kept minimal by direct reuse of the shipped shared
currency helper plus a scoped inline copy of one formatter class:

- Pre-add-helper search: `grep_search "CurrencyInputController|CurrencyTextField"`
  under `lib/` returned matches only inside
  `lib/shared/widgets/currency_input_field.dart` and
  `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`.
  Confirmed the shared `CurrencyInputController` already ships as the
  canonical POS-cents storage helper (int-cents `ValueNotifier<int>` with
  clamping, `formattedValue`, `clear()`, `isEmpty`/`isNotEmpty`, thousands
  grouping) — reused as-is for `_priceCents` in the Gear form sheet so
  storage stays on the same convention `financial_entries.amount_cents`
  and `band_gear.price_cents` use. No modification to the shared file
  (financials must not see a display-shape drift).
- Pre-add-helper search: `grep_search "_CurrencyInputFormatter|_GearCurrencyFormatter"`
  under `lib/` — the shared `_CurrencyInputFormatter` is `_`-private inside
  `currency_input_field.dart` and emits `$X.XX` (no double space); financials'
  Amount column widths are calibrated against that exact output. Tony's Gear
  spec calls for `$  X.XX` (two literal spaces) — a different display shape.
  Per the Cycle 9 plan's "copy the formatter class inline in gear if
  financials keeps it private" directive, added `_GearCurrencyFormatter`
  inline in `gear_form_sheet.dart`. The copy differs from the shared class
  in exactly one respect (calls `_formatPriceCentsDisplay(cents)` instead of
  `controller.formattedValue`); the state-update contract (int cents +
  clamp to `_maxCents`) is identical. Empty-state return uses
  `TextEditingValue.empty` (the const static) instead of the shared file's
  hand-rolled `const TextEditingValue(text: '', selection: ...)` — both are
  semantically identical; `TextEditingValue.empty` is one line and passes
  `avoid_redundant_argument_values` cleanly.
- Pre-add-helper search for a thousands-separator helper:
  `_formatWithCommas` on `CurrencyInputController` is private-static;
  `NumberFormat('#,##0')` from `package:intl` was already imported by
  `gear_form_sheet.dart` for the date label. Reused `NumberFormat` in
  `_formatPriceCentsDisplay` — no new dependency, no new file-private
  helper duplicating what `intl` already provides.
- No new provider added — `_priceCents` is a form-sheet-local state
  field, not lifted to a Riverpod provider. No new named route, no new
  dependency, no new barrel file. No new `_buildX()` single-use method.
  No new model field on `GearItem` (the `priceCents` field it already
  had is reused). No new column on any DB table. No touch to
  `gear_repository.dart` or any migration.
- Bug-fix-with-zero-deletions self-check: the cycle-9 diff on
  `gear_form_sheet.dart` and `gear_screen.dart` includes substantive
  deletions (`_priceController` field, legacy `_parsePriceCents` body
  with `double.tryParse` + `.round()`, the "Price must be a valid
  non-negative amount" snackbar branch, the free-text `[0-9.,]` input
  formatter, `_priceController.text` init string, the fixed
  `_kPurchasedOnWidth` constant, the fixed `_kPurchasedFromWidth`
  constant, the `'Purchased From'` header label, the
  `overflow: TextOverflow.ellipsis` on the Purchased On row cell). Not
  a layered-on-top fix.
- No `TODO` / `FIXME` / `debugPrint(` introduced. Grep of
  `lib/features/gear/**/*.dart` for those tokens returns zero matches.
- No `try/catch` re-thrown unchanged or catching what the call can't
  throw. The existing form-sheet `try { … } catch (_) { … }` on the
  save path is unchanged from cycle 3.
- `dart format` only the two changed files (`gear_screen.dart`,
  `gear_form_sheet.dart`); no other file touched by the formatter.

**File-size targets — pre-existing soft-exceeds, unchanged status.**
`gear_screen.dart` = 977 lines after `dart format` (was 966 pre-
cycle-9; the +11 lines net add is the second `_measureText` block +
the new `purchasedOnColumnWidth` parameter threading). Still exceeds
the 500-line target from cycle 7's 1:1 mirror of
`lib/features/financials/financials_screen.dart` — the same
justification already noted in cycle 7's Code Efficiency section
applies (breaking the mirror shape would create 6+ new one-off widget
files). Cycle 9 does not add any new widget class to this file; only
renames one constant, deletes another, and threads one required
parameter through two existing widgets. `gear_form_sheet.dart` = 546
lines after `dart format` (was 487 pre-cycle-9; the +59 lines are the
`_formatPriceCentsDisplay` helper + the `_GearCurrencyFormatter`
class, both scoped to the file and required by the cents-first spec).
Soft-exceeds the 400-line feature-widget target by 146 lines; the
increment over cycle 3 is entirely the price input change Tony's
spec calls for, and inlining the formatter into the `AppTextField`
call site is not possible (it must be a `TextInputFormatter`
subclass). Splitting the formatter to a sibling file would create a
new one-off `.dart` file for a class with exactly one call site,
which is the class of bloat the mode guardrails are protecting
against. `gear_controller.dart` = 215 lines, comfortably under every
size target (unchanged this cycle from cycle 8).

Cycle 8 additions kept minimal:

- No new provider added — the state swap (`GearOwnerFilter` enum →
  `Set<String> ownerSelection`) reuses the existing `gearProvider`,
  drops one enum + one field + one notifier method, and adds one field
  + two notifier methods. Net structural change is a shape swap, not
  an expansion.
- `_OwnerFilterModal` is a `ConsumerStatefulWidget` (not a
  `_buildX()` method) because it owns local staged-selection state
  (`_pending`) that must survive a `setState` — method-inlining would
  lose that boundary. It's used exactly once (via
  `showModalBottomSheet<Set<String>>`), which the mode guardrails allow
  when the widget owns state.
- `_ownerChipLabel` is a file-top helper mirroring the shape of the
  neighboring `_ownerLabel` / `_memberShortLabel` / `_priceLabel`
  helpers already in the file. Reuse of `_memberShortLabel` — no new
  member-formatting helper introduced.
- `dart format` on both cycle-8 files produced no changes at commit
  time (files already conforming).
- No `TODO` / `FIXME` / `debugPrint(` introduced in cycle-8 edits.

Cycle 7 additions kept minimal by direct 1:1 structural mirror of the
shipped Financials screen:

- `gear_screen.dart` gains a set of private classes that mirror
  `financials_screen.dart` section-for-section: `_OwnerFilterToggle`
  (mirrors `_ViewModeToggle`, extended from 2 → 3 segments),
  `_DateFilterRow`, `_FilterChip`, `_GearEntriesList` (mirrors
  `_EntriesList`), `_TableHeader`, `_HeaderCell`, `_GearTableRow`
  (mirrors `_EntryTableRow`), `_EmptyState`, `_ErrorState`. Every
  single-use private widget class is retained (not inlined into a
  `_buildX()` method) because Manager cycle-7 note explicitly directs
  a 1:1 mirror of financials — inlining any of these would break the
  section boundaries and diverge from the precedent. `_HeaderCell` and
  `_FilterChip` are used more than once (5 and 4 sites respectively) so
  they're multi-use even under the standard bloat rule.
- Pre-add-helper search: `grep_search "firstWhereOrNull"` on
  `lib/features/**` returned zero matches. The `_ownerLabel` helper
  keeps the same for-loop shape the cycle-3 gear code used and every
  other iterable-lookup site in the codebase uses; introducing a
  `package:collection` import for one 4-line loop would be net bloat.
- Pre-add-helper search: `grep_search "GearRow|GearEmptyState"` on
  `**/*.dart` returned only the definitions themselves plus their
  consumers in `gear_screen.dart`. Both widget files are single-use;
  deleting + inlining is the smallest-surface path and matches
  financials' precedent.
- No new provider added — extended the existing `gearProvider` with
  four new state fields, one derived getter, three notifier methods.
  Every added field is consumed by the screen; no dead code.
- No new named route, no new dependency, no new barrel file. No
  `_buildX()` single-use method. No new model field on `GearItem`.
- No `TODO` / `FIXME` / `debugPrint(` introduced.
- No `try/catch` re-thrown unchanged or catching what the call can't
  throw. Every existing `try/catch` on the notifier is unchanged from
  cycle 3.
- `dart fix --dry-run` on both changed files: `Nothing to fix!` (run
  per file — the CLI only accepts one path at a time).

**File-size targets — one soft-exceed with justification.**
`gear_screen.dart` = 816 lines after `dart format`. This exceeds the
500-line file-size target from mode guardrails. Justification: 1:1
structural mirror of `lib/features/financials/financials_screen.dart`
(1210 lines) directed by Manager cycle-7 note ("mirror precisely"). A
smaller gear file would require breaking the section-for-section
mirror shape or extracting the private classes to sibling files, which
would (a) diverge from the financials precedent Manager explicitly
directs and (b) create 6+ new one-off widget files under
`lib/features/gear/widgets/` for classes that have exactly one
consumer, which is the class of bloat the mode guardrails are
protecting against. `gear_controller.dart` = 215 lines, comfortably
under every size target.

**Deletions offset the additions.** Two widget files removed
(`gear_row.dart` = 94 lines, `gear_empty_state.dart` = 72 lines = 166
deleted lines), net cycle-7 code diff on `lib/features/gear/**` is
`+860 -168` (screen) + `+88 -0` (controller) − `-166` (widgets) ≈ `+614`
insertions total. The bulk of the insertion is the mirrored table
implementation (header + rows) that financials also carries as ~400
lines of similar structure.

Cycle 5 additions (unchanged this cycle) kept minimal by direct mirror
of the shipped Financials Quick Actions precedent:

- `quick_actions_row.dart` gains exactly one new field (`onGear`), one
  new bool field (`showGear` with default `true`), the corresponding
  constructor entries, one new term in `hasVisibleButtons`, and one new
  `_buildQuickActionButton` call block for the Gear button reusing the
  existing helper. No new helper, no new widget class, no new state, no
  duplicated helper. Searched `lib/` for pre-existing "quick action
  button" helpers before adding: `_buildQuickActionButton` inside
  `quick_actions_row.dart` is the sole helper and remains private;
  reusing it in place is the least-bloat option.
- `home_tab_content.dart` gains exactly: one new import
  (`../gear/gear_screen.dart`), one new `_handleOpenGear` method (7
  lines mirroring `_handleOpenFinancials`), one new `canViewGear` read
  from `permissionsAsync.when` (5 lines mirroring `canViewFinancials`),
  one new `canViewGear: canViewGear` argument at the `_buildContentState`
  call site, one new `required bool canViewGear,` parameter on
  `_buildContentState`, one new `|| canViewGear` term on `hasAnyButton`,
  and two new arguments (`onGear`, `showGear`) on the `QuickActionsRow`
  call. Searched `lib/` for pre-existing "open gear screen" navigation
  helpers before adding: no equivalent existed; `_handleOpenFinancials`
  is the closest sibling, and `_handleOpenGear` mirrors it exactly.
- Cycle-5 diff totals `+43` insertions, `-9` deletions across only the
  two files, well under any file-size target from the mode guardrails.
- Cycle-5 pre-existing lint sweep: 7 provably-safe no-op equivalents,
  each documented under the Cycle-5 pre-existing lint sweep note above.
  Every fix is what the analyzer literally suggests, not a discretionary
  rewrite.
- `dart fix --dry-run` on both cycle-5-touched files: `Nothing to fix!`.
- No `TODO` / `FIXME` / `debugPrint(` introduced in cycle-5 edits.
- No new provider, no new notifier, no new named route, no new helper,
  no new barrel file, no new `_buildX()` single-use method, no new model
  field, no new imports beyond the required `gear_screen.dart`.

Cycle 4 additions kept minimal by direct mirror of already-shipped
precedent files:

- Migration 1 mirrors
  `20260604000001_add_can_view_financials_to_contributor_permissions.sql`
  verbatim except `financials → gear`. No new helper, no rewrite.
- Migration 2 mirrors
  `20260711120000_fix_update_member_role_can_view_financials.sql` verbatim
  with the single new SET-clause line for `can_view_gear`. `CREATE OR
REPLACE` is used because the RPC already exists; not a fresh function
  definition.
- Migration 3 mirrors
  `20260814120001_fix_financial_entries_select_rbac.sql` for shape; the
  `REVOKE ALL FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated`
  pattern is inline in the same file (avoids the two-step pattern the
  financials feature had to ship later per
  `20260822120001_revoke_anon_batch_2_rls_helpers.sql`).
- `contributor_permissions.dart` edit reuses the existing field-parity
  pattern (`canViewFinancials`); no new helper, no new `copyWith` layout —
  one field added per method / static.
- `band_permissions.dart` change is a body swap on the existing
  `canViewGear` getter matching the exact shape of `canViewSetlists` /
  `canViewCalendar` / `canViewMembers` / `canViewFinancials`. No new
  getter, no removal, `canManageGear` untouched.
- `role_management_sheet.dart` change is one extra
  `_buildPermissionToggle` call reusing the existing helper, and one extra
  boolean AND in `_permissionsEqual`. No new widget, no new state field.
- Searched `lib/` for pre-existing "contributor toggle" or "permissions-
  equal" helpers before adding: the existing `_permissionsEqual` in
  `role_management_sheet.dart` is the only such helper and remains
  private; extending it in place is the least-bloat option.
- `dart fix --dry-run` executed against the changed files; no automated
  fixes applicable.
- No `TODO` / `FIXME` / `debugPrint(` introduced in cycle-4 edits.
- No new helpers, no barrel files, no new providers, no `_buildX()` single-
  use methods, no dead SQL grants.

## Verification (manual steps performed)

Cycle 9:

- Read the current cycle-8 uncommitted `gear_screen.dart` end-to-end,
  confirmed the constant block (`_kMinNameWidth`, `_kPurchasedOnWidth`,
  `_kPurchasedFromWidth`, `_kOwnerWidth`, `_kFixedColumnsWidth`), the
  `_measureText` pattern and Price column dynamic-width block inside
  `_GearEntriesList.build`, and the two consumer widgets
  (`_TableHeader`, `_GearTableRow`) all match the cycle-7 shape. Mapped
  the exact `_measureText` financials uses for its Amount column
  (`lib/features/financials/financials_screen.dart` lines 668–679) so
  the cycle-9 Purchased On block mirrors the same shape byte-for-shape.
- Read `lib/shared/widgets/currency_input_field.dart` end-to-end —
  confirmed `CurrencyInputController` API (int cents, `clamp(0,
99999999)`, `formattedValue` uses `$X.XX` no-space format,
  `_formatWithCommas` is private) and confirmed `_CurrencyInputFormatter`
  is a `_`-private `TextInputFormatter` inside the same file. Verified
  financials'
  `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
  consumes both classes at 4 sites (main amount field, disbursement
  splits, deposit-to-savings field) so any change to the shared display
  shape would cascade into financials.
- Confirmed cycle-9 in-scope files match Manager's allow-list:
  `lib/features/gear/gear_screen.dart` (edited) +
  `lib/features/gear/widgets/gear_form_sheet.dart` (edited). Did not
  touch `models/gear_item.dart`, `gear_controller.dart`,
  `gear_repository.dart`, or `test/features/gear/gear_item_test.dart`
  (no new testable helper introduced).
- Ran T1.1 (7-item scope) → first pass surfaced 1 info-severity lint
  (`avoid_redundant_argument_values` on the empty-state
  `TextEditingValue` inside `_GearCurrencyFormatter`); fixed to
  `TextEditingValue.empty`; second pass `No issues found!` at every
  severity.
- Ran T1.2 → 5/5 pass.
- Ran `dart format lib/features/gear/gear_screen.dart
lib/features/gear/widgets/gear_form_sheet.dart` — one file reformatted
  (`gear_screen.dart`); re-ran T1.1 to confirm `No issues found!` still
  holds post-format.
- Ran `dart fix --dry-run 2>&1 | grep -E "gear_screen|gear_form_sheet|gear_controller|gear_item_test" | head -20`
  — zero matching lines, i.e. no dart-fix-applicable suggestions on any
  cycle-8- or cycle-9-touched Gear file.
- Self-audit of the cycle-9 diff against the AI-shaped-code checklist:
  no single-use `_buildX()` method introduced, no new provider,
  `_GearCurrencyFormatter` and `_formatPriceCentsDisplay` are single-
  use by necessity (a `TextInputFormatter` cannot be inlined into the
  `AppTextField` call site), no `first-match-or-null` loop
  hand-rolled (used `NumberFormat` from the existing `intl` import
  for commas), no `try/catch` that logs+rethrows, no dead model
  field/param, no barrel file, no config/flags/enum "for future use",
  no TODO/FIXME/debugPrint, and the diff on both files includes
  substantive deletions (not just additions) so this is not a
  layered-on-top bug fix.

Cycle 8:

- Read `lib/features/members/members_controller.dart` and
  `lib/features/members/member_vm.dart` — confirmed
  `membersProvider` exposes `MemberVM` with `userId`, `name`, `firstName`,
  `lastName`, `status`, `isActive`, matching the shape needed by
  `_OwnerFilterModal` (active-members filter + name display + userId
  key) and by `_ownerChipLabel` (single-vs-multi formatting).
- Confirmed `_openOwnerFilterModal()` uses
  `showModalBottomSheet<Set<String>>` and reads the current
  `state.ownerSelection` for the `initialSelection`, so re-opening the
  modal restores the last-committed state (not the last-staged state,
  which is intentional — swipe-dismiss discards).
- Confirmed Clear button on the modal uses `_pending = <String>{}` (not
  `_pending.clear()`) so the setState boundary is triggered explicitly
  and the Done handler returns a fresh set on the next tap.

Cycle 7:

- Read Manager cycle-7 note in full; confirmed cycle 7 is an in-branch
  UX-scope adjustment driven by Tony's cycle-7 6b test finding, that
  Manager preserved the Cycle Number at 7 (not reset), and that
  Manager holds `pipeline.lock` for this cycle
  (`manager|feature/band-gear-management|2026-09-06T13:56:17Z`).
- Ran `GIT_OPTIONAL_LOCKS=0 git branch --show-current` →
  `feature/band-gear-management`, and `GIT_OPTIONAL_LOCKS=0 git status`
  → only the two expected doc drifts (`ENGINEER_REPORT.md`,
  `QA_REPORT.md`) with no other tracked-file drift and no orphaned
  untracked work.
- Read `lib/features/financials/financials_screen.dart` in full (1210
  lines) before touching anything on gear — that's the mirror
  precedent, and getting section boundaries right depends on
  understanding the shipped shape.
- Read cycle-3 `lib/features/gear/gear_screen.dart`,
  `gear_controller.dart`, `gear_form_sheet.dart`, `gear_row.dart`,
  `gear_empty_state.dart`, and `models/gear_item.dart` before edits.
  Confirmed `GearFormSheet` cycle-3 already supports both edit
  (`_isEditMode = widget.item != null`) and read-only
  (`_isReadOnly = !widget.canManageGear`) modes; per Manager cycle-7
  note, form sheet not touched this cycle.
- Pre-delete usage audit for `GearRow` and `GearEmptyState`
  (`grep_search "GearRow|GearEmptyState|gear_row\.dart|gear_empty_state\.dart"`
  on `**/*.dart`): returned 8 matches across 3 files — the two widget
  definition files themselves plus the two import + call sites inside
  `gear_screen.dart`. No other file imports either widget; deletion
  is safe.
- Rewrote `gear_screen.dart` as a section-for-section mirror of
  `financials_screen.dart`. Deleted `widgets/gear_row.dart` and
  `widgets/gear_empty_state.dart`. Extended `gear_controller.dart`
  with filter state + methods.
- Ran T1.1 first pass; surfaced 5 info-severity lints on
  `gear_screen.dart` (mirror-inherited from financials, which is out
  of scope for T1.1 per Manager Option D so financials isn't flagged
  in the run). Fixed all 5 as trivial no-op equivalents (dropped
  `width: 1.0` on 2 `BorderSide` local vars, dropped `day = 1` default
  arg on `DateTime(now.year, now.month)`, dropped `onSurface:
Colors.white` default in `const ColorScheme.dark`, added `const` to
  the Price header cell). Re-ran T1.1: `No issues found!`.
- Ran `flutter test test/features/gear/gear_item_test.dart` → 5/5
  pass, no regression from the rewrite (the model file was not
  touched).
- Ran `dart fix --dry-run lib/features/gear/gear_controller.dart` →
  `Nothing to fix!`; `dart fix --dry-run lib/features/gear/gear_screen.dart`
  → `Nothing to fix!`.
- Ran `dart format` on both changed files — 1 file (`gear_screen.dart`)
  reformatted, `gear_controller.dart` already canonical. Re-ran T1.1
  post-format → `No issues found!` still.
- Self-audit sweep for AI-shaped code on the diff, per Engineer mode
  guardrails: no `_buildX()` method used once (retained multi-use
  private classes matching the mirror), no unused import (the removed
  `AppButton`/`GearRow`/`GearEmptyState`/`RefreshIndicator` imports
  were dropped when the code paths were removed), no dead field (every
  new `GearState` field is consumed by `filteredItems` or the screen),
  no `try/catch` retrofit (existing `try/catch` unchanged), no
  `TODO`/`FIXME`/`debugPrint(`, no barrel file, no new provider, no
  new model field, no new named route, no new dependency.
- Confirmed cycle-4 RBAC files
  (`contributor_permissions.dart`, `band_permissions.dart`,
  `role_management_sheet.dart`) and all cycle-5 Quick Actions files
  (`home_tab_content.dart`, `quick_actions_row.dart`) are untouched
  by cycle 7 via `GIT_OPTIONAL_LOCKS=0 git status --short` — they
  don't appear in the modified-file list.
- Confirmed no `supabase/migrations/**` file touched by cycle 7 via
  `git status --short`; all four gear migrations byte-identical to
  cycle 4.
- Confirmed no `.github/agents/*.md` or `PR_BODY.md` touched by
  cycle 7 via `git status --short`.
- Confirmed `pipeline.lock` shows Manager holds the lock; cycle 7 did
  not acquire or release the lock (Manager cycle-7 note: "do NOT
  acquire your own lock"). Cycle 7 will not run any `git` write
  command — Manager owns every git write in this pipeline.

Cycle 6:

- Read Manager cycle-6 note in full; confirmed cycle 6 is a revert-only
  cycle driven by Tony's cycle-5 QA-APPROVED review directive ("remove
  'Gear' from the menu. It should only be in the Quick Actions section")
  and that Manager preserved the cycle-6 Cycle Number at 6 (not reset).
- Confirmed pipeline.lock is held by Manager (`manager|feature/band-gear-management|2026-09-06T12:47:32Z`);
  cycle 6 did not acquire or release the lock (Manager cycle-6 note:
  "do NOT acquire your own lock").
- Ran `GIT_OPTIONAL_LOCKS=0 git branch --show-current` →
  `feature/band-gear-management`, and `GIT_OPTIONAL_LOCKS=0 git status
--short` → four cycle-5 uncommitted files as expected (`docs/features/feature-band-gear-management/ENGINEER_REPORT.md`,
  `.../QA_REPORT.md`, `lib/features/home/home_tab_content.dart`,
  `lib/features/home/widgets/quick_actions_row.dart`) with no other
  tracked-file drift and no orphaned untracked work outside
  `docs/features/feature-band-gear-management/`.
- Verified main tip sha (`GIT_OPTIONAL_LOCKS=0 git rev-parse main` →
  `80bad0a9a1384919c8b939900ed842d27415d636`) matches the Manager
  cycle-6-stated `80bad0a`; HEAD sha (`26b5fed`) matches the Manager
  cycle-6-stated commit.
- Pre-revert grep in `lib/features/shell/app_shell.dart`
  (`grep -n 'GearScreen\|gear_screen'`) returned exactly two matches:
  the cycle-3 import on line 18 and the `_MenuDrawerLayer` push call on
  line 306. Confirmed no other symbol in `app_shell.dart` references
  `GearScreen`, so reverting to main removes both cleanly.
- Executed the two Manager-provided reverts:
  `GIT_OPTIONAL_LOCKS=0 git checkout main -- lib/features/home/widgets/side_drawer.dart`
  and
  `GIT_OPTIONAL_LOCKS=0 git checkout main -- lib/features/shell/app_shell.dart`.
  Post-revert `GIT_OPTIONAL_LOCKS=0 git diff --stat main` no longer lists
  either file — both are byte-identical to main tip.
- Ran T1.1 with Manager cycle-6's 9-item file list against the post-
  revert worktree — output surfaced 8 info-severity lints in
  `side_drawer.dart` and `app_shell.dart` (details in the **Analyzer
  Results** section above).
- Isolated-state audit to confirm the 8 lints are main-baseline, not
  Engineer-introduced: (i) `git stash push -u` the 6 modified files;
  (ii) `git checkout main -- side_drawer.dart app_shell.dart` (idempotent
  — they were already at main state); (iii)
  `flutter analyze lib/features/home/widgets/side_drawer.dart
lib/features/shell/app_shell.dart` → identical 8-lint output at same
  locations. Then restored worktree via `git checkout HEAD -- ...` +
  `git stash pop`, verified `git diff --stat main` still shows the two
  files at zero net diff (post-revert state preserved).
- Ran T1.2 (`flutter test test/features/gear/gear_item_test.dart`) —
  5/5 pass, no regression from the revert.
- Did NOT re-run T1.3 per Manager cycle-6 step 6 (accepted Deviation A
  still applies; cycle 6 does not touch the auth login screen or its
  test file).
- Confirmed cycle-5 uncommitted files (`home_tab_content.dart`,
  `quick_actions_row.dart`) are untouched by cycle 6 — `git diff` on
  those two files matches the cycle-5 shape reported in cycle-5's
  ENGINEER_REPORT.md verbatim.
- Confirmed all cycle-4 RBAC files
  (`contributor_permissions.dart`, `band_permissions.dart`,
  `role_management_sheet.dart`) and all cycle-3 gear files
  (`lib/features/gear/*`, `test/features/gear/*`, all four gear
  migrations) are untouched by cycle 6.
- Confirmed `.github/agents/*.md` and `PR_BODY.md` are untouched by
  cycle 6.
- Ran final `GIT_OPTIONAL_LOCKS=0 git diff --stat main` — 20 files
  total changed vs main, all matching the pre-cycle-6 (cycle-5-shipped)
  set except that `side_drawer.dart` and `app_shell.dart` no longer
  appear in the diff list. Cycle 6's net change to the worktree is
  entirely subtractive.

Cycle 5:

- Read Manager cycle-5 note in full; confirmed the scope extension is
  in-branch, additive-only, and mirrors the shipped Financials Quick
  Actions precedent exactly.
- Confirmed `lib/features/home/` is not on `ARCHITECT_PLAN.md#L656`'s
  Files Off-Limits list.
- Verified via `grep -F 'Financials'` that neither
  `lib/features/home/home_screen.dart` nor
  `lib/features/home/widgets/empty_home_state.dart` wires Financials —
  cycle 5 matches that precedent and does not introduce Gear wiring
  where Financials has none.
- Confirmed `GearScreen` is exported by
  `lib/features/gear/gear_screen.dart:20` and is const-constructible
  (`class GearScreen extends ConsumerStatefulWidget { const
GearScreen({super.key}); ... }`), matching `FinancialsScreen`'s shape
  so `MaterialPageRoute(builder: (_) => const GearScreen())` compiles.
- Confirmed `perms.canViewGear` is defined in
  `lib/features/members/permissions/band_permissions.dart:157` (cycle-4
  work) so the new `canViewGear = permissionsAsync.when(...)` read has
  a defined getter to hit.
- Ran `flutter analyze` on the cycle-5 expanded file list — clean at
  every severity, `No issues found!`.
- Ran `flutter test test/features/gear/gear_item_test.dart` — 5/5 pass;
  no cycle-5 code path regresses the model-level tests.
- Ran `dart fix --dry-run` on `home_tab_content.dart` and
  `quick_actions_row.dart` — `Nothing to fix!` on both.
- Ran `dart format` on `home_tab_content.dart` and
  `quick_actions_row.dart` — 0 files changed.
- Confirmed `git diff --stat` shows exactly two files touched
  (`lib/features/home/home_tab_content.dart +33 -9`,
  `lib/features/home/widgets/quick_actions_row.dart +19 -0`); no other
  file changed.
- Confirmed `pipeline.lock` shows Manager holds the lock; this cycle did
  not acquire or release the lock (Manager cycle-5 note: "do NOT acquire
  your own lock").

Cycle 4:

- Read the Architect cycle-3 revision in full; confirmed the scope
  addition targets only the six files this cycle actually touches (three
  new migrations + three modified Dart files) and does not require any
  edit to files off-limits.
- Confirmed the three modified Dart files still compile clean via T1.1.
- Confirmed `_permissionsEqual` covers all seven contributor sub-permission
  fields (`canCreateGigs`, `canCreatePotentialGigsOnly`, `canViewSetlists`,
  `canViewCalendar`, `canViewMembers`, `canViewFinancials`, `canViewGear`)
  so dirty-detection tracks the new toggle.
- Confirmed the new "Can view gear" toggle in `role_management_sheet.dart`
  sits immediately after the existing "Can view financials" toggle and
  uses the same `_buildPermissionToggle` shape.
- Confirmed migration 3 does not include any `FOR INSERT` / `FOR UPDATE`
  / `FOR DELETE` policy statements — INSERT / UPDATE / DELETE gates
  remain the base migration's admin-and-member-only policies (`grep -Ec
"FOR INSERT|FOR UPDATE|FOR DELETE"` returned 0).
- Confirmed T1.4 static counts against all four migrations (evidence
  block above).
- Confirmed `pipeline.lock` shows Manager holds the lock; this cycle did
  not acquire or release the lock.
- Confirmed working tree carries only the six expected cycle-4 code
  additions/modifications plus untracked doc/gear scaffolding from cycle
  3; no out-of-plan file changed.

## Deviations From Plan

- **Cycle 7 in-branch UX-scope adjustment (authorized by Manager
  cycle-7 note).** The base `ARCHITECT_PLAN.md` Proposed Solution
  section 1 explicitly directed a list-of-cards UI ("List UI, not a
  literal HTML table … a scrolling list of cards/rows … Row content:
  name (primary), owner (secondary), price + purchase date
  (tertiary). Purchased-from surfaces on the detail/edit sheet.").
  Tony's cycle-7 6b test finding on the current PR head reverses that
  decision: "the gear screen should match the financials screen,
  including the filters. Gear should be listed in a table to match
  financials instead of cards." Cycle 7 rewrites `gear_screen.dart`
  as a section-for-section mirror of
  `lib/features/financials/financials_screen.dart` (1210 lines) with
  a table of five columns (Name, Purchased On, Purchased From, Owner,
  Price) plus an owner-type filter toggle (All / Band-owned /
  Member-owned) and a date filter row (All Time / This Year / This
  Month / Custom Range). Manager cycle-7 note explicitly authorizes
  this as an in-branch UX-scope adjustment ("Product decisions are
  already made by Tony — implement the mirror; don't second-guess
  it") and specifies precise mirror boundaries (title row, filter
  rows, table columns, empty state, error state, no bottom actions
  row). This is a subtractive change to the ARCHITECT_PLAN's cards UI
  and an additive change to the ARCHITECT_PLAN's controller state
  (adds filter state that the plan did not require).
- **Cycle 7 subtractive file-set change: two widget files deleted
  (authorized by Manager cycle-7 note).** `lib/features/gear/widgets/
gear_row.dart` and `lib/features/gear/widgets/gear_empty_state.dart`
  were cycle-3-created files in the base plan (Task 12). Cycle 7
  deletes both and inlines their behavior into `gear_screen.dart` as
  private `_GearTableRow` and `_EmptyState` classes, mirroring
  financials' precedent (which inlines `_EntryTableRow` and
  `_EmptyState` in `financials_screen.dart` directly). Manager
  cycle-7 note authorizes this: "either rewrite to be the table row
  (`_GearTableRow` shape) or delete it if you inline the row inside
  `gear_screen.dart` like financials does. Whichever keeps the diff
  clean; document your choice." Choice documented under
  [Files Deleted](#files-deleted) above.
- **Cycle 7 `gear_screen.dart` exceeds the 500-line file-size target
  (justified in Code Efficiency/Bloat Check).** Post-`dart format`
  the file is 816 lines, over the 500-line target. Justified: 1:1
  structural mirror of `financials_screen.dart` (1210 lines) that
  Manager cycle-7 note directs ("mirror precisely"). Splitting into
  helper files would (a) diverge from the precedent and (b) create
  6+ one-off widget files under `widgets/` for classes each used
  exactly once. Recorded per mode instruction ("exceeding one
  requires a one-line justification in ENGINEER_REPORT.md").
- **Cycle 7 null-date handling for `purchased_on` documented, not
  deviated.** Manager cycle-7 note explicitly delegated the choice:
  "pick the simplest behavior that mirrors how financials handles
  missing dates and document your choice in the report." Chosen:
  items with `purchasedOn == null` are included ONLY when
  `dateFilter == GearDateFilter.allTime`; every date-bounded filter
  drops them. Rationale: financials' `FinancialEntry.entryDate` is
  non-nullable so financials never has to answer this — the simplest
  mirror is "no date → no date-bounded surface", which also matches
  user intuition. Documented in the [Files Modified](#files-modified)
  cycle-7 subsection under `gear_controller.dart`.
- **Cycle 6 revert-only in-branch scope contraction (authorized by
  Manager cycle-6 note).** The base `ARCHITECT_PLAN.md` Task 15 wired
  Gear surfacing via the side drawer (`side_drawer.dart` +
  `app_shell.dart`). Tony's cycle-5 QA-APPROVED state review directed
  removal of that surface: "remove 'Gear' from the menu. It should only
  be in the Quick Actions section." Cycle 6 reverts both files
  byte-identical to main tip. This subtracts Task 15 from the shipped
  feature surface; Gear now surfaces exclusively via the cycle-5 Quick
  Actions wiring. Manager cycle-6 note explicitly authorizes this scope
  contraction and provided the `git checkout main -- ...` commands used.
- **Cycle 6 T1.1 scope contraction to touched-files-only (authorized by
  Manager Option D cycle-6 finalization decision).** After the reverts,
  `side_drawer.dart` and `app_shell.dart` carry 0 diff vs main and are
  no longer feature-touched. T1.1 is now scoped to the 7 files this
  feature actually modifies. This is not a deviation from the
  ARCHITECT_PLAN — the plan's T1.1 command was updated in the same
  Manager cycle-6 finalization pass to reflect the actual touched-files
  scope. It's the same rule QA applies to every other file the feature
  leaves untouched: pre-existing lints in a file the feature doesn't
  modify are not that feature's gate. Recorded here for QA traceability
  because earlier cycles ran T1.1 against a broader 9-item list.
- **Cycle 5 in-branch scope extension (authorized by Manager cycle-5
  note).** The base `ARCHITECT_PLAN.md` did not list Quick Actions
  surfacing for Gear — Task 15 surfaced Gear only via the side drawer.
  Cycle 5 adds Quick Actions surfacing as an additive scope extension
  driven by Tony's PR #261 6b test finding, mirroring the shipped
  Financials Quick Actions precedent exactly. Manager cycle-5 note
  authorizes this: "The scope addition mirrors the existing Financials
  precedent — no architect re-diagnosis needed, but Engineer MUST
  document this as an in-branch cycle-5 additive scope extension in
  ENGINEER_REPORT.md and note that the base ARCHITECT_PLAN.md did not
  list Quick Actions surfacing." Files touched:
  `lib/features/home/widgets/quick_actions_row.dart` and
  `lib/features/home/home_tab_content.dart`. Neither is on the
  ARCHITECT_PLAN's Files Off-Limits list.
- **Cycle 5 pre-existing lint sweep in touched files (authorized by
  Engineer mode instruction).** The T1.1 expanded file list surfaced 7
  pre-existing info-level lints in
  `home_tab_content.dart` + `quick_actions_row.dart` that the cycle-4
  T1.1 command did not run against because those files were not in
  cycle 4's file list. Per the Engineer mode instruction "pre-existing
  violation in a file you did touch does — fix it if it's trivial, or
  report it if fixing it would exceed scope," all 7 were fixed as
  provably-safe no-op equivalents (documented under the Cycle 5
  pre-existing lint sweep note above). This is the minimum work
  necessary to satisfy Manager's cycle-5 T1.1 outcome directive of
  `No issues found`.
- **Deviation A (pre-approved by Tony's cycle-3 review).** Tier 1.3 full-
  suite regression carries exactly one failure at
  `test/features/auth/login_screen_demo_button_test.dart` Test A. Root
  cause: `lib/features/auth/login_screen.dart:657` renders `'Check out the
demo band'` (lowercase `out`) but the test asserts title-case
  `'Check Out the Demo Band'`. Both files were last touched together in
  commit `5cd1996` and are unmodified by `feature/band-gear-management`.
  Filed as a separate one-line typo/bug fix. Per the plan's accepted-
  deviation clause, this failure does not block Ready For QA; all 218
  other tests pass. Cycle 5 did not re-run T1.3 per Manager cycle-5 note
  ("Do NOT re-run T1.3 unless something breaks — the accepted Deviation
  A still applies"). Nothing in cycle 5 touches the auth login screen or
  its test.
- **Deviation B (pre-approved by Tony's cycle-3 review).** Tier 1.5
  isolated migration-apply check remains deferred to Tier 2 owner-run
  checks under the repo-wide broken-migration-chain infra blocker
  precedent used for
  `docs/features/interactive-demo-band-experience/QA_REPORT.md#L15`. Tony
  runs the migration apply at production apply time. This deferral does
  not block Ready For QA.

## Blockers Encountered

**Cycle 7 — none.** T1.1 clean at first-fix pass (5 mirror-inherited
info lints in the newly-rewritten `gear_screen.dart`, all trivially
fixed as no-op equivalents). T1.2 gear tests 5/5 pass. `dart fix
--dry-run` clean on both changed files. `dart format` applied. No
blockers.

**Cycle 6 — none at finalization.** The cycle-6 T1.1 scope question
(originally raised as Options A / B / C / D against the earlier 9-item
gate list) was resolved by Manager's cycle-6 finalization decision:
Option D — contract T1.1 to the 7 files this feature actually modifies.
Rationale (Manager, verbatim in the cycle-6 finalization note): since
`side_drawer.dart` and `app_shell.dart` are now byte-identical to main,
they are no longer feature-touched files; T1.1 is a gate on files this
feature actually modifies, not a broader baseline audit — the same rule
QA applies to every other file the feature leaves untouched. The
ARCHITECT_PLAN's T1.1 command was updated in the same finalization pass
to the 7-item scope. The 7-item T1.1 command returned `No issues found`
at every severity (see **Analyzer Results** above); T1.2 gear tests
5/5 pass. No open blockers.

Cycle 5: none.

Cycle 4: none.

## Ready For QA

Yes. Cycle 9 T1.1 (7-item scope per Manager Option D, preserved from
cycle 6) returned `No issues found!` at every severity (0 errors, 0
warnings, 0 infos) — command and output captured under **Analyzer
Results → Cycle 9 T1.1**. Cycle 9 T1.2 gear tests 5/5 pass — output
captured under **Test Results → Cycle 9 T1.2**. T1.3 not re-run per
Manager cycle-9 instruction "Do NOT re-run T1.3 (accepted Deviation A
still applies)". Cycle 4 T1.4 static SQL evidence unchanged. Cycle 4
T1.5 remains deferred to Tier 2 per accepted Deviation B. Cycle 9
net worktree diff scoped to two Dart files inside `lib/features/gear/`
(`gear_screen.dart` column-width polish + header rename;
`widgets/gear_form_sheet.dart` cents-first price input + `From` label
rename); cycle 8's uncommitted `gear_screen.dart` + `gear_controller.dart`
rolled into the same evidence set per Manager instruction. No touch to
off-limits files (`home/`, `shell/`, `supabase/migrations/`,
`contributor_permissions.dart`, `band_permissions.dart`,
`role_management_sheet.dart`, `.github/agents/*.md`, `PR_BODY.md`,
`gear_repository.dart`, `models/gear_item.dart`). Cycle 5
modifications (`home_tab_content.dart`, `quick_actions_row.dart`) and
cycle 4 RBAC files preserved unchanged.
