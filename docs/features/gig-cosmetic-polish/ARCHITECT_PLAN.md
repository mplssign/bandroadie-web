# Architect Plan

## Feature Slug
`feature/gig-cosmetic-polish`

## Feature Title
Rose border on ViewGigDrawer navigate button + comma-formatted currency values

---

## Problem Summary

Two independent, low-risk display-only fixes bundled into one pipeline:

**Item A — Navigate button missing border**
The Navigate `IconButton` in `ViewGigDrawer` renders without a rose border outline.
The fix was specified in the view-gig-drawer-polish plan (PR #44) but was never
applied to the merged code. Confirmed absent via direct inspection of main.

**Item B — formattedPay missing thousands separator**
`Gig.formattedPay` produces `"$1500.00"` instead of `"$1,500.00"` for values ≥
$1,000. No thousands comma is inserted. All financials screens already use
`NumberFormat('#,##0')` from `intl` and are correctly formatted; the defect is
isolated to this single getter.

---

## Root Cause

**Item A** — `HIGH confidence` (direct code observation)
`view_gig_drawer.dart:169–175`: the `IconButton` has no `style:` property. The
`style: IconButton.styleFrom(...)` block with `BorderSide` and `RoundedRectangleBorder`
was never added. All required constants (`AppColors.primary`, `BrandButton.borderWidth`,
`Spacing.buttonRadius`) exist in `design_tokens.dart`, which is already imported.

**Item B** — `HIGH confidence` (direct code observation)
`gig.dart:195–199`: `formattedPay` constructs the dollar string as
`'\$$dollars.${cents.toString().padLeft(2, '0')}'` using plain integer-to-string
conversion. No thousands separator logic is applied. Every other currency formatter in
the codebase uses `NumberFormat('#,##0').format(dollars)` (financials) or a custom
`_formatWithCommas` helper (currency input field) — `formattedPay` was never updated
to match.

---

## Reference Docs Consulted
None applicable — this is a pure UI/presentation feature with no notification or
backend domain involvement.

---

## Existing System Analysis

### Item A — Navigate button
`view_gig_drawer.dart` is a `StatelessWidget` bottom sheet. The Navigate button lives
in the header block (location row):

```
// Location row + Navigate button (lines 157–177)
Row(
  children: [
    Expanded(child: Text(gig.location, ...)),
    IconButton(                               // ← no style: here
      icon: const Icon(LucideIcons.navigation2),
      color: AppColors.primary,
      iconSize: 20,
      onPressed: () => _openNavigation(context),
      tooltip: 'Navigate',
    ),
  ],
),
```

Adding `style: IconButton.styleFrom(...)` is a pure presentation change. No state,
navigation, or repository code is affected. The `color:` and `iconSize:` properties
remain; `style:` adds a border and shape around the button.

### Item B — Currency display landscape (full audit)

| Site | File | Current formatting | Status |
|------|------|--------------------|--------|
| `Gig.formattedPay` | `lib/app/models/gig.dart:195` | `'\$$dollars.${cents...}'` — no comma | **NEEDS FIX** |
| `FinancialEntry.formattedAmount` | `lib/features/financials/models/financial_entry.dart:150` | `NumberFormat('#,##0').format(dollars)` | Already correct |
| `FinancialEntry.formattedDepositToSavings` | `lib/features/financials/models/financial_entry.dart:158` | `NumberFormat('#,##0').format(dollars)` | Already correct |
| `GigPayDetails.formattedAmount` | `lib/features/financials/models/financial_entry.dart:219` | `NumberFormat('#,##0').format(dollars)` | Already correct |
| `_fmt(int cents)` | `lib/features/financials/financials_screen.dart:242` | `NumberFormat('#,##0').format(dollars)` | Already correct |
| Total display | `lib/features/financials/financials_screen.dart:1078` | `NumberFormat('#,##0').format(dollars)` | Already correct |
| PDF preview | `lib/features/financials/financials_pdf_preview_screen.dart:85` | `NumberFormat.currency(symbol: '\$', decimalDigits: 2)` | Already correct |
| `_formatSavingsCents` | `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart:90` | `NumberFormat('#,##0').format(dollars)` | Already correct |
| `CurrencyInputController.formattedValue` | `lib/shared/widgets/currency_input_field.dart:39` | Custom `_formatWithCommas` helper | Already correct |

**Conclusion:** Only one site needs fixing (`Gig.formattedPay`). No shared utility is
warranted — a single-site fix does not justify a new abstraction. The fix is applied
inline to the getter.

### Reference branch check (feat/gig-address-field)
The reference branch has this fix applied to `formattedPay`. The regex used is:
```dart
dollars.toString().replaceAllMapped(
  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
)
```
Architect verified correctness independently:
- `0` → `"0"` (no match, correct)
- `500` → `"500"` (no match, correct)
- `1000` → `"1,000"` (matches `1` before `000`, correct)
- `15000` → `"15,000"` (matches `15` before `000`, correct)
- `1000000` → `"1,000,000"` (matches `1` before `000000`, then `000` before `000`, correct)

The regex is correct. Because only one site needs fixing and `gig.dart` has no existing
`intl` import, the regex approach is preferred over introducing a new import.

### Pre-existing analyzer errors (noted for QA)
`main` currently has 2 pre-existing `flutter analyze` errors in `view_gig_drawer.dart`
(lines 13 and 245): `uri_does_not_exist` and `undefined_identifier` for
`gig_notes_sheet.dart` / `GigNotesSheet`. These are unrelated to this feature and will
be present on the `feature/gig-cosmetic-polish` branch as well. QA must confirm zero
**new** errors — the 2 pre-existing errors are expected.

---

## Proposed Solution

**Item A:** Add `style: IconButton.styleFrom(...)` to the existing Navigate `IconButton`
in `view_gig_drawer.dart`. Use `BrandButton.borderWidth` (1.5) and
`Spacing.buttonRadius` (8.0) from `design_tokens.dart` (already imported). No other
changes to the widget.

**Item B:** Update `Gig.formattedPay` in `gig.dart` to insert thousands commas using
the regex from the reference branch. No new imports. No changes to any other method
or field.

---

## Database Impact
Not applicable. No database reads, writes, migrations, RLS policies, RPCs, or triggers
are involved.

---

## Flutter Architecture Changes

- No state changes
- No provider changes
- No repository changes
- No navigation changes
- No new widgets or files
- Changes are confined to: one widget property (`style:`) and one model getter

---

## Files to Create
None.

---

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/gigs/widgets/view_gig_drawer.dart` | Add `style: IconButton.styleFrom(...)` to Navigate `IconButton` at lines 169–175 |
| `lib/app/models/gig.dart` | Update `formattedPay` getter (lines 195–199) to insert thousands commas using regex |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/financials/models/financial_entry.dart` | All currency formatters already correct; no changes needed |
| `lib/features/financials/financials_screen.dart` | All currency formatters already correct; no changes needed |
| `lib/features/financials/financials_pdf_preview_screen.dart` | Already uses `NumberFormat.currency`; no changes needed |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | Already correct; no changes needed |
| `lib/shared/widgets/currency_input_field.dart` | Input display field; already has `_formatWithCommas`; no changes needed |
| `lib/features/financials/financial_entry_repository.dart` | Separate pipeline (upsert bug); not touched |
| `lib/features/events/widgets/event_editor_drawer.dart` | Out of scope; not touched |
| `supabase/migrations/` | No migration required |
| `lib/main.dart` | Initialization order must not change |

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | **affected** — `view_gig_drawer.dart` (border style), `gig.dart` (formattedPay display) |
| Financials | unaffected — display already correct; repository untouched |
| Rehearsals | unaffected — no shared code path |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | all platforms affected equally — pure Dart/Flutter UI |

---

## Regression Risk
**LOW**

Both changes are pure presentation:
- Item A adds a `style:` to an existing `IconButton` — no logic, no state, no callbacks affected.
- Item B changes string formatting in a single computed getter — no database writes, no state mutations, no navigation.
- Neither change touches auth, session, routing, initialization order, or any shared controller.
- The only regression surface is visual: incorrect display on the navigate button or a currency value that was previously displaying without commas now displaying with them — both are correct, not regressions.

---

## Engineer Task Breakdown

### Task 1 — Add rose border to Navigate IconButton

**File:** `lib/features/gigs/widgets/view_gig_drawer.dart`

Locate the `IconButton` at approximately line 169. Replace:

```dart
IconButton(
  icon: const Icon(LucideIcons.navigation2),
  color: AppColors.primary,
  iconSize: 20,
  onPressed: () => _openNavigation(context),
  tooltip: 'Navigate',
),
```

With:

```dart
IconButton(
  icon: const Icon(LucideIcons.navigation2),
  color: AppColors.primary,
  iconSize: 20,
  onPressed: () => _openNavigation(context),
  tooltip: 'Navigate',
  style: IconButton.styleFrom(
    side: const BorderSide(
      color: AppColors.primary,
      width: BrandButton.borderWidth,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    ),
  ),
),
```

No import changes required. `AppColors`, `BrandButton`, and `Spacing` are all defined
in `design_tokens.dart`, which is already imported at line 7.

No other changes to this file.

---

### Task 2 — Add thousands comma to Gig.formattedPay

**File:** `lib/app/models/gig.dart`

Locate `formattedPay` getter at approximately line 195. Replace:

```dart
/// Formatted gig pay (e.g., "$150.00")
/// Returns null if no pay is specified.
String? get formattedPay {
  if (gigPayCents == null) return null;
  final dollars = gigPayCents! ~/ 100;
  final cents = gigPayCents! % 100;
  return '\$$dollars.${cents.toString().padLeft(2, '0')}';
}
```

With:

```dart
/// Formatted gig pay (e.g., "$1,500.00")
/// Returns null if no pay is specified.
String? get formattedPay {
  if (gigPayCents == null) return null;
  final dollars = gigPayCents! ~/ 100;
  final cents = gigPayCents! % 100;
  final dollarsStr = dollars.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '\$$dollarsStr.${cents.toString().padLeft(2, '0')}';
}
```

No import changes required. The regex is pure Dart with no external dependencies.

No other changes to this file.

---

### Task 3 — flutter analyze

Run `flutter analyze` after both tasks are complete. Confirm:
- Exactly 2 errors (the pre-existing `uri_does_not_exist` and `undefined_identifier`
  in `view_gig_drawer.dart` for `gig_notes_sheet.dart` / `GigNotesSheet`)
- Zero new errors or warnings introduced by this diff

---

## Verification Plan

### Tier 1 — Pre-deployment (static / no runtime required)

These verify the implementation is correct before any device testing.

**Tier 1 Test 1 — formattedPay regex correctness**

Verify the regex produces correct output for representative cent values by tracing or
running a minimal Dart snippet (no Flutter device needed):

| Input (cents) | Expected output |
|---------------|----------------|
| 0             | `$0.00`        |
| 50            | `$0.50`        |
| 100           | `$1.00`        |
| 99900         | `$999.00`      |
| 100000        | `$1,000.00`    |
| 150000        | `$1,500.00`    |
| 10000000      | `$100,000.00`  |
| 100000000     | `$1,000,000.00`|

**Tier 1 Test 2 — formattedPay null guard**

Confirm `formattedPay` returns `null` when `gigPayCents == null`. The null guard at the
top of the getter is unchanged; this is a smoke check.

**Tier 1 Test 3 — flutter analyze**

Run `flutter analyze`. Expected: exactly 2 errors (both pre-existing, in
`view_gig_drawer.dart`, both referencing `gig_notes_sheet.dart` / `GigNotesSheet`).
Zero new errors or warnings.

**Tier 1 Test 4 — diff scope check**

Run `git diff main --name-only`. Confirm only these files appear:
```
docs/features/gig-cosmetic-polish/ARCHITECT_PLAN.md
lib/features/gigs/widgets/view_gig_drawer.dart
lib/app/models/gig.dart
```
(plus `ENGINEER_REPORT.md` once the Engineer has committed it)

No unexpected files in the diff.

---

### Tier 2 — Post-deployment (on-device / visual verification)

**Tier 2 Test 1 — Navigate button border (primary)**

1. Open any confirmed gig on the Home or Calendar screen.
2. Tap the gig to open `ViewGigDrawer`.
3. Observe the Navigate icon button in the location row.
4. **Expected:** a rose (#BE123C) rounded-rectangle border is visible around the
   navigate icon, matching the rose accent used on the "Done" button and other brand
   elements.

**Tier 2 Test 2 — Navigate button functionality unchanged**

1. From the same `ViewGigDrawer`, tap the Navigate button.
2. **Expected:** Maps app opens with correct address / venue query. No error snackbar.
   Navigation behavior is unchanged.

**Tier 2 Test 3 — formattedPay display with four-digit dollar amount**

1. Open or create a confirmed gig with a pay amount of $1,500 or more.
2. Open `ViewGigDrawer` for that gig.
3. Observe the "Gig pay" detail row.
4. **Expected:** pay displays as e.g., `$1,500.00` with comma. Previously would have
   shown `$1500.00`.

**Tier 2 Test 4 — formattedPay display with three-digit dollar amount (no comma)**

1. Open a confirmed gig with a pay amount under $1,000 (e.g., $750).
2. Open `ViewGigDrawer`.
3. **Expected:** pay displays as `$750.00` — no comma, no regression.

**Tier 2 Test 5 — Financials screen unchanged**

1. Open the Financials tab.
2. Verify dollar amounts on financial entries are still correctly comma-formatted
   (they were already correct and must not regress).

---

## QA Regression Areas

- **Navigate button border:** must be visible (rose, rounded rect) — was absent
- **Navigate button tap behavior:** must still open Maps — must not regress
- **Gig pay display:** `$1,500.00` not `$1500.00` for large values — primary Item B fix
- **Gig pay display for small values:** `$500.00` unchanged — no regression
- **Financials screen currency display:** unchanged — already correct, must not regress
- **Pre-existing flutter analyze errors:** expect exactly 2 (both in `view_gig_drawer.dart`,
  both pre-existing); zero new errors

---

## Rollout / Migration Strategy
Not applicable. Pure client-side display changes. No data migration, no backend deploy,
no edge function update required.

---

## Out of Scope

- `financial_entry_repository.dart` upsert bug — separate pipeline (`gig-pay-upsert-duplicate-key`)
- `ViewGigDrawer` wiring / routing — already shipped
- Any other `ViewGigDrawer` visual changes beyond the navigate button border
- Financials currency display — already correct, no changes required
- `CurrencyInputField` display — already correct, no changes required
- `gig_notes_sheet.dart` missing file — tracked on `bug/wire-view-gig-drawer-to-gig-tap`
