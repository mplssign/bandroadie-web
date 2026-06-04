# ARCHITECT_PLAN.md
**Branch:** `bug/deposit-to-savings-amount`
**Date:** 2026-06-04
**Covers:** Feature A (bug/deposit-to-savings-amount) + Feature B (feature/contributor-financials-permission)

---

## Feature A — Deposit to Savings: Amount Field

### Problem Statement

The `deposit_to_savings` bool toggle was shipped without a corresponding amount input. When the toggle is on, there is no way to capture how much was deposited to savings. The `financial_entries` table has no `deposit_to_savings_cents` column. The full stack — DB, model, repository, controller, form, details sheet, and list table — must be updated.

### Root Cause

The `feature/deposit-to-savings-toggle` PR added only the boolean column and toggle UI. The cents amount, which is semantically required to make the toggle meaningful, was omitted from the schema, model, and UI.

### Root Cause Confidence: HIGH — confirmed by direct code inspection.

---

### Database Impact

| Area | Impact |
|---|---|
| `financial_entries` table | **Affected** — new `deposit_to_savings_cents INTEGER` column required |
| RLS policies on `financial_entries` | Unaffected — column-level addition only |
| `upsertGigPayEntry` RPC | Explicitly **excluded** from scope per constraints |
| Other RPCs | Unaffected |
| `contributor_permissions` table | Unaffected (Feature B scope) |

**New migration required:**
```sql
-- supabase/migrations/20260604000000_add_deposit_to_savings_cents_to_financial_entries.sql
ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS deposit_to_savings_cents INTEGER;
```

- No DEFAULT — nullable integer. `NULL` means "no amount specified" (toggle was off or not set).
- Must coexist with `deposit_to_savings` (bool). They are separate columns.
- No RLS change required.

---

### System Impact

| System | Impact |
|---|---|
| Financials — DB schema | Affected — new column |
| Financials — `FinancialEntry` model | Affected — new field `depositToSavingsCents` |
| Financials — `FinancialEntryRepository` | Affected — `insertEntry` + `updateEntry` payloads |
| Financials — `FinancialsController` | Affected — `addEntry` + `updateEntry` method signatures |
| Financials — `_SaveCallback` typedef | Affected — new `depositToSavingsCents` named param |
| Financials — `add_financial_entry_bottom_sheet.dart` | Affected — new controller, `AnimatedSize` expand, `_save()` |
| Financials — `financial_entry_details_bottom_sheet.dart` | Affected — display amount when flag is true |
| Financials — `financials_screen.dart` | Affected — Savings column shows formatted amount |
| Gigs / Rehearsals / Setlists / Members / Auth | Unaffected |

---

### Implementation Tasks

#### Task A-1 — Database Migration
**File:** `supabase/migrations/20260604000000_add_deposit_to_savings_cents_to_financial_entries.sql`

Create the file with:
```sql
-- Migration: Add deposit_to_savings_cents to financial_entries
-- Date: 2026-06-04
-- Branch: bug/deposit-to-savings-amount

ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS deposit_to_savings_cents INTEGER;
```

---

#### Task A-2 — `FinancialEntry` Model
**File:** `lib/features/financials/models/financial_entry.dart`

1. Add `final int? depositToSavingsCents;` to the class fields (after `depositToSavings`).
2. Add `this.depositToSavingsCents,` to the constructor (after `this.depositToSavings`).
3. In `FinancialEntry.fromJson`: add  
   `depositToSavingsCents: json['deposit_to_savings_cents'] as int?,`  
   (after the `depositToSavings` parse line).
4. In `toJson()`: add  
   `'deposit_to_savings_cents': depositToSavingsCents,`  
   (after the `deposit_to_savings` entry).

No other changes to the model. `disbursements` is the pattern to follow for a nullable typed field.

---

#### Task A-3 — `_SaveCallback` typedef
**File:** `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`

Add `int? depositToSavingsCents,` as a named optional parameter to the `_SaveCallback` typedef, after `bool? depositToSavings`.

---

#### Task A-4 — `FinancialEntryRepository`
**File:** `lib/features/financials/financial_entry_repository.dart`

**`insertEntry`:**
- Add `int? depositToSavingsCents,` to the named parameters (after `bool? depositToSavings`).
- In the `payload` map, add: `'deposit_to_savings_cents': depositToSavingsCents,`

**`updateEntry`:**
- Add `int? depositToSavingsCents,` to the named parameters (after `bool? depositToSavings`).
- In the update map, add: `'deposit_to_savings_cents': depositToSavingsCents,`

`upsertGigPayEntry` must **not** be modified.

---

#### Task A-5 — `FinancialsController`
**File:** `lib/features/financials/financials_controller.dart`

**`addEntry`:**
- Add `int? depositToSavingsCents,` to the named parameters (after `bool? depositToSavings`).
- Pass `depositToSavingsCents: depositToSavingsCents,` to `repo.insertEntry(...)`.

**`updateEntry`:**
- Add `int? depositToSavingsCents,` to the named parameters (after `bool? depositToSavings`).
- Pass `depositToSavingsCents: depositToSavingsCents,` to `repo.updateEntry(...)`.

---

#### Task A-6 — Add Financial Entry Bottom Sheet (Form UI)
**File:** `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`

This is the largest change. Follow the `AnimatedSize` + `CurrencyTextField` pattern used by "Disburse to Band" exactly.

**State additions** (in `_AddFinancialEntryBottomSheetState`):

```dart
late final CurrencyInputController _depositToSavingsController;
```

Add after the `_splitControllers` declaration.

**`initState` changes:**

In the `if (entry != null)` branch, after `_depositToSavings = entry.depositToSavings ?? false;`:
```dart
_depositToSavingsController = CurrencyInputController(
  entry.depositToSavingsCents ?? 0,
);
```

In the `else` branch, after the other `CurrencyInputController()` initialisations:
```dart
_depositToSavingsController = CurrencyInputController();
```

**`dispose` additions:**

```dart
_depositToSavingsController.dispose();
```

Add before `super.dispose()`.

**`_setIsIncome` change:**

After the existing block that sets `_depositToSavings = false` when switching to expense:
```dart
if (!isIncome) {
  _depositToSavingsCentsController.cents = 0;  // reset on income→expense flip
}
```

Wait — the controller is `_depositToSavingsController`. Correct form:

```dart
if (!isIncome && _depositToSavings) {
  _depositToSavings = false;
  _depositToSavingsController.cents = 0;
}
```

Replace the existing `if (!isIncome && _depositToSavings)` block with this two-line version.

**`_save` changes:**

The `_save` method currently passes `depositToSavings: _isIncome ? _depositToSavings : null`.

Add after `disbursements` resolution and before the `widget.onSave(...)` call:

```dart
final depositToSavingsCents =
    (_isIncome && _depositToSavings && _depositToSavingsController.cents > 0)
        ? _depositToSavingsController.cents
        : null;
```

Then in the `widget.onSave(...)` call, add:
```dart
depositToSavingsCents: depositToSavingsCents,
```
after the `depositToSavings` argument.

**UI — Animated expand below the toggle:**

Replace the current "Deposit to Savings" section (which is only the toggle row + spacer) with:

```dart
// Deposit to Savings toggle (income only)
if (_isIncome) ...[
  Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        'Deposit to Savings',
        style: AppTextStyles.callout
            .copyWith(color: context.colors.textPrimary),
      ),
      Switch(
        value: _depositToSavings,
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: context.colors.surfaceOverlay,
        inactiveThumbColor: context.colors.textSecondary,
        onChanged: (v) => setState(() => _depositToSavings = v),
      ),
    ],
  ),
  AnimatedSize(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeInOut,
    child: _depositToSavings
        ? Padding(
            padding: const EdgeInsets.only(top: Spacing.space12),
            child: CurrencyTextField(
              controller: _depositToSavingsController,
              label: 'Savings Amount',
              hint: r'$0.00',
              clearOnFocus: true,
            ),
          )
        : const SizedBox.shrink(),
  ),
  const SizedBox(height: Spacing.space16),
],
```

The `AnimatedSize` parameters (`duration`, `curve`, `child`) are identical to the Disburse to Band pattern — do not deviate.

**`_SaveCallback` wiring in `_save`:**

The `onSave` call must pass the new `depositToSavingsCents` parameter. The complete parameter list for `onSave` inside `_save()` becomes:

```dart
await widget.onSave(
  entryType: ...,
  category: ...,
  amountCents: ...,
  entryDate: ...,
  description: ...,
  is1099Expected: ...,
  payerName: ...,
  paidToUserId: ...,
  paidToName: ...,
  disbursements: disbursements,
  depositToSavings: _isIncome ? _depositToSavings : null,
  depositToSavingsCents: depositToSavingsCents,
);
```

---

#### Task A-7 — `FinancialsScreen` call sites
**File:** `lib/features/financials/financials_screen.dart`

Two call sites invoke `notifier.addEntry(...)` / `notifier.updateEntry(...)` via the `onSave` callback. Both are in the `floatingActionButton.onPressed` lambda and do not need changes to accept the new parameter — they already pass `depositToSavings:` through. However the `_SaveCallback` they satisfy now requires `depositToSavingsCents` as a parameter too.

Update both `onSave` closures to:
1. Accept `depositToSavingsCents,` in the named param list.
2. Forward `depositToSavingsCents: depositToSavingsCents,` to `notifier.addEntry` / `notifier.updateEntry`.

There is **one** call site in `financials_screen.dart` (FAB `onPressed`) and **one** in `financial_entry_details_bottom_sheet.dart` (the Edit button).

---

#### Task A-8 — `financial_entry_details_bottom_sheet.dart`
**File:** `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`

**Display row:** Replace the existing `depositToSavings == true` detail row from:
```dart
if (entry.depositToSavings == true) ...[
  const SizedBox(height: Spacing.space12),
  _DetailRow(
    icon: AppIcons.dollar,
    label: 'Deposit to Savings',
    value: 'Yes',
  ),
],
```

With:
```dart
if (entry.depositToSavings == true) ...[
  const SizedBox(height: Spacing.space12),
  _DetailRow(
    icon: AppIcons.dollar,
    label: 'Deposit to Savings',
    value: entry.depositToSavingsCents != null
        ? entry.formattedDepositToSavings
        : 'Yes',
  ),
],
```

Add a computed getter to `FinancialEntry` (Task A-2 file):
```dart
/// Formatted savings amount (e.g., "$250.00"). Returns null if cents is null.
String? get formattedDepositToSavings {
  final c = depositToSavingsCents;
  if (c == null) return null;
  final dollars = c ~/ 100;
  final cents = c % 100;
  final dollarsFormatted = NumberFormat('#,##0').format(dollars);
  return '\$$dollarsFormatted.${cents.toString().padLeft(2, '0')}';
}
```

**Edit onSave closure:** The existing `onSave` closure in `_FinancialEntryDetailsSheet` passes all params through to `notifier.updateEntry(...)`. Add `depositToSavingsCents,` to both the closure parameter list and the `notifier.updateEntry(...)` call, following the same pattern as `depositToSavings`.

---

#### Task A-9 — `financials_screen.dart` Savings column
**File:** `lib/features/financials/financials_screen.dart`

The Savings column currently shows an icon when `depositToSavings == true`. Replace with a formatted dollar amount when `depositToSavingsCents` is non-null, falling back to icon-only when the bool is true but cents is null (backwards compat for existing rows).

Replace the current Savings cell in `_EntryTableRow.build`:
```dart
// Savings
SizedBox(
  width: _kSavingsWidth,
  child: Container(
    decoration: BoxDecoration(
        border: Border(
            right: BorderSide(
                color: context.colors.border, width: 0.5))),
    child: Center(
      child: entry.depositToSavings == true
          ? const Icon(
              AppIcons.dollar,
              size: 16,
              color: AppColors.primary,
            )
          : const SizedBox.shrink(),
    ),
  ),
),
```

With:
```dart
// Savings
SizedBox(
  width: _kSavingsWidth,
  child: Container(
    decoration: BoxDecoration(
        border: Border(
            right: BorderSide(
                color: context.colors.border, width: 0.5))),
    child: Center(
      child: entry.depositToSavings == true
          ? entry.depositToSavingsCents != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    entry.formattedDepositToSavings!,
                    style: AppTextStyles.footnote.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              : const Icon(
                  AppIcons.dollar,
                  size: 16,
                  color: AppColors.primary,
                )
          : const SizedBox.shrink(),
    ),
  ),
),
```

**Column width:** `_kSavingsWidth` is currently `64.0`. This may be tight for dollar amounts. Widen to `80.0`:
```dart
const _kSavingsWidth = 80.0;
```
Update `_kFixedColumnsWidth` accordingly (it is a sum expression and will update automatically if the constant is updated in place).

---

### Feature A — Files Modified

| File | Change |
|---|---|
| `supabase/migrations/20260604000000_add_deposit_to_savings_cents_to_financial_entries.sql` | **CREATE** |
| `lib/features/financials/models/financial_entry.dart` | Add `depositToSavingsCents` field + `formattedDepositToSavings` getter |
| `lib/features/financials/financial_entry_repository.dart` | Add `depositToSavingsCents` to `insertEntry` + `updateEntry` |
| `lib/features/financials/financials_controller.dart` | Add `depositToSavingsCents` to `addEntry` + `updateEntry` |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | New controller, `AnimatedSize` expand, `_save()` logic |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | Display amount; pass `depositToSavingsCents` in edit closure |
| `lib/features/financials/financials_screen.dart` | Savings column; pass `depositToSavingsCents` in FAB onSave |

---

---

## Feature B — Gate Financials Behind Contributor Sub-Permission

### Problem Statement

The Financials quick action is hard-gated with `!isContributor` in `home_tab_content.dart`. This prevents any contributor from ever accessing Financials, with no admin override. The permission must be made configurable via a new `can_view_financials` sub-permission, defaulting to `false`, wired end-to-end through DB → model → computed permission → UI guard → management sheet.

### Root Cause

The original contributor permissions table (`20260302000000_band_user_roles.sql`) did not include a `can_view_financials` column. The home screen guard hardcodes the role string rather than consulting `BandPermissions`.

### Root Cause Confidence: HIGH — confirmed by direct code inspection.

---

### Database Impact

| Area | Impact |
|---|---|
| `contributor_permissions` table | **Affected** — new `can_view_financials` column |
| Existing RLS policies on `contributor_permissions` | Unaffected — column addition only |
| `band_members` table | Unaffected |
| `financial_entries` table | Unaffected |

**New migration required:**
```sql
-- supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql
ALTER TABLE public.contributor_permissions
  ADD COLUMN IF NOT EXISTS can_view_financials BOOLEAN NOT NULL DEFAULT FALSE;
```

- `DEFAULT FALSE`: new and existing contributor rows default to no financials access.
- `NOT NULL`: consistent with all other columns in the table.
- No RLS change required.

---

### System Impact

| System | Impact |
|---|---|
| Members — `ContributorPermissions` model | Affected — new `canViewFinancials` field |
| Members — `BandPermissions` | Affected — new `canViewFinancials` computed getter |
| Members — `role_management_sheet.dart` | Affected — new `SwitchListTile` toggle |
| Home — `home_tab_content.dart` | Affected — replace `!isContributor` guard with `perms.canViewFinancials` |
| Financials | Unaffected (Feature A covers its own changes) |
| Gigs / Rehearsals / Setlists / Auth | Unaffected |

---

### Implementation Tasks

#### Task B-1 — Database Migration
**File:** `supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql`

```sql
-- Migration: Add can_view_financials to contributor_permissions
-- Date: 2026-06-04
-- Branch: bug/deposit-to-savings-amount

ALTER TABLE public.contributor_permissions
  ADD COLUMN IF NOT EXISTS can_view_financials BOOLEAN NOT NULL DEFAULT FALSE;
```

---

#### Task B-2 — `ContributorPermissions` Model
**File:** `lib/features/members/permissions/contributor_permissions.dart`

Follow the exact pattern of the five existing fields.

1. **Field declaration** — add after `canViewMembers`:
   ```dart
   final bool canViewFinancials;
   ```

2. **Constructor** — add after `this.canViewMembers = true`:
   ```dart
   this.canViewFinancials = false,
   ```
   Default is `false` — differs from the other fields (which default `true`). This is intentional and specified in the constraints.

3. **`allEnabled`** — the existing `allEnabled` constant uses `ContributorPermissions()` (all defaults). Since `canViewFinancials` defaults to `false`, `allEnabled` must be updated to explicitly include it:
   ```dart
   static const ContributorPermissions allEnabled = ContributorPermissions(
     canViewFinancials: true,
   );
   ```
   All other fields remain at their defaults (`true`). The existing `allEnabled` declaration is `ContributorPermissions()` which will now implicitly have `canViewFinancials: false` — this is wrong for `allEnabled`. It must be explicit.

4. **`allDisabled`** — add `canViewFinancials: false,` to the existing list of fields.

5. **`fromJson`** — add after `canViewMembers` parse:
   ```dart
   canViewFinancials: json['can_view_financials'] as bool? ?? false,
   ```
   Fallback `false` matches DB default.

6. **`toJson`** — add:
   ```dart
   'can_view_financials': canViewFinancials,
   ```

7. **`copyWith`** — add parameter and return value:
   ```dart
   bool? canViewFinancials,
   ```
   and:
   ```dart
   canViewFinancials: canViewFinancials ?? this.canViewFinancials,
   ```

8. **`toString`** — add `canViewFinancials=$canViewFinancials` to the string.

---

#### Task B-3 — `BandPermissions` Computed Getter
**File:** `lib/features/members/permissions/band_permissions.dart`

Add the following getter after `canViewMembers`, following the identical pattern:

```dart
/// Whether this user can view the financials screen.
/// Admin & member: always. Contributor: only if canViewFinancials sub-permission is set.
bool get canViewFinancials {
  if (isAdmin || isMember) return true;
  if (isContributor) {
    return subPermissions?.canViewFinancials ?? false;
  }
  return false;
}
```

---

#### Task B-4 — `home_tab_content.dart`
**File:** `lib/features/home/home_tab_content.dart`

**Add `canViewFinancials` derived variable** alongside the existing `canCreateGig`, `canCreateSetlist`, `isContributor` derivations (lines ~491–507):

```dart
final canViewFinancials = permissionsAsync.when(
  data: (perms) => perms.canViewFinancials,
  loading: () => false,
  error: (_, __) => false,
);
```

**Replace the two `!isContributor` guards** for Financials (lines ~942 and ~947):

Line ~942: Replace:
```dart
onFinancials: !isContributor
    ? _handleOpenFinancials
    : null,
```
With:
```dart
onFinancials: canViewFinancials
    ? _handleOpenFinancials
    : null,
```

Line ~947: Replace:
```dart
showFinancials: !isContributor,
```
With:
```dart
showFinancials: canViewFinancials,
```

**Do not** leave the `isContributor` variable or either `!isContributor` reference for the financials guard in place. The `isContributor` variable itself may still be needed elsewhere (it is used on lines ~380, ~608, ~642, ~780, ~876, ~909, ~912) — **do not remove it**.

---

#### Task B-5 — `role_management_sheet.dart`
**File:** `lib/features/members/widgets/role_management_sheet.dart`

**`_permissionsEqual`:** Add `canViewFinancials` comparison:
```dart
a.canViewFinancials == b.canViewFinancials &&
```
Add as the last condition before the closing `;`.

**Contributor sub-permissions section:** Add the new `SwitchListTile` after the `'Can view members'` toggle, following the exact `_buildPermissionToggle` pattern:

```dart
_buildPermissionToggle(
  label: 'Can view financials',
  value: _subPermissions.canViewFinancials,
  onChanged: (v) => setState(() {
    _subPermissions =
        _subPermissions.copyWith(canViewFinancials: v);
  }),
),
```

Default display is `false` (off) — consistent with DB and model default.

---

### Feature B — Files Modified

| File | Change |
|---|---|
| `supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql` | **CREATE** |
| `lib/features/members/permissions/contributor_permissions.dart` | Add `canViewFinancials` field end-to-end |
| `lib/features/members/permissions/band_permissions.dart` | Add `canViewFinancials` computed getter |
| `lib/features/home/home_tab_content.dart` | Replace `!isContributor` financials guards |
| `lib/features/members/widgets/role_management_sheet.dart` | Add toggle + equality check |

---

---

## Combined Constraints Checklist

- [ ] `AnimatedSize` uses `duration: const Duration(milliseconds: 200)` and `curve: Curves.easeInOut` — identical to Disburse to Band.
- [ ] `deposit_to_savings_cents` is a separate column from `deposit_to_savings`. Both coexist.
- [ ] `_save()` passes `null` for `depositToSavingsCents` when `_depositToSavings` is false **or** entry is an expense.
- [ ] `canViewFinancials` defaults to `false` in: DB column (`DEFAULT FALSE`), `ContributorPermissions` constructor, `BandPermissions.canViewFinancials` fallback.
- [ ] `!isContributor` financials guard in `home_tab_content.dart` is fully replaced — not supplemented.
- [ ] `catch (e) { return []; }` pattern is not used anywhere in new code.
- [ ] No new global color definitions — all color references use `AppColors` from `design_tokens.dart`.
- [ ] `upsertGigPayEntry` is not modified.
- [ ] Every new `CurrencyInputController` is disposed in `dispose()`.
- [ ] `ContributorPermissions.allEnabled` explicitly sets `canViewFinancials: true`.
- [ ] `ContributorPermissions.allDisabled` explicitly sets `canViewFinancials: false`.

---

## Execution Order for Engineer

The two features are independent except that both must be present before QA can validate the full build. Suggested sequential order:

1. **B-1** → DB migration for `can_view_financials`
2. **B-2** → `ContributorPermissions` model
3. **B-3** → `BandPermissions` getter
4. **B-4** → `home_tab_content.dart` guard swap
5. **B-5** → `role_management_sheet.dart` toggle
6. **A-1** → DB migration for `deposit_to_savings_cents`
7. **A-2** → `FinancialEntry` model + getter
8. **A-3** → `_SaveCallback` typedef
9. **A-4** → Repository
10. **A-5** → Controller
11. **A-6** → Bottom sheet form UI (largest change)
12. **A-7** → `financials_screen.dart` FAB call site
13. **A-8** → Details sheet display + edit closure
14. **A-9** → Savings column in table

After all tasks: run `flutter analyze` — must pass with 0 errors before QA.
