# ARCHITECT PLAN

## Feature: deposit-to-savings-toggle

**Branch:** `feature/deposit-to-savings-toggle`
**Type:** feature
**Status:** APPROVED — ready for Engineer

---

## Summary

Add a "Deposit to Savings" boolean toggle to the financial entry add/edit flow. The toggle is income-only, independent of (and not mutually exclusive with) the existing "Disburse to Band" toggle, and persists as a new nullable boolean column `deposit_to_savings` on `financial_entries`.

---

## Root Cause / Design Gap

The `financial_entries` table and its associated Dart model, repository, controller, and UI have no concept of "deposit to savings." The "Disburse to Band" toggle is the only per-entry flag of this kind. The new toggle follows the same pattern end-to-end.

Root cause confidence: **HIGH** — confirmed by direct inspection of all relevant files.

---

## Files to Modify

| #   | File                                                                                 | Change                                                              |
| --- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------- |
| 1   | `supabase/migrations/20260603000000_add_deposit_to_savings_to_financial_entries.sql` | **NEW** — add `deposit_to_savings` column                           |
| 2   | `lib/features/financials/models/financial_entry.dart`                                | Add `depositToSavings: bool?` field                                 |
| 3   | `lib/features/financials/financial_entry_repository.dart`                            | Add `depositToSavings` param to `insertEntry` and `updateEntry`     |
| 4   | `lib/features/financials/financials_controller.dart`                                 | Add `depositToSavings` param to `addEntry` and `updateEntry`        |
| 5   | `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`              | Add toggle UI + state + save wiring                                 |
| 6   | `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`          | Display the field; update edit callback signature                   |
| 7   | `lib/features/financials/financials_screen.dart`                                     | Add "Savings" indicator column to table; update FAB `onSave` lambda |

**Do not modify:**

- `financial_entry_repository.dart → upsertGigPayEntry` (gig pay flow is out of scope)
- Any file in the `GigPayBottomSheet` flow
- `financials_pdf_preview_screen.dart` (does not render per-entry boolean flags)

---

## Database Impact

### Migration file

**Path:** `supabase/migrations/20260603000000_add_deposit_to_savings_to_financial_entries.sql`

**Content:**

```sql
ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS deposit_to_savings BOOLEAN DEFAULT FALSE;
```

- No new RLS policies required. Existing `check_band_member` helper covers the table.
- No new RPC functions.
- No trigger changes.
- No new indexes.
- `DEFAULT FALSE` ensures all existing rows are backfilled to `false` (PostgreSQL 11+ fast column addition behaviour).

---

## Implementation Tasks (in dependency order)

---

### Task 1 — Migration

Create `supabase/migrations/20260603000000_add_deposit_to_savings_to_financial_entries.sql` with the single `ALTER TABLE` statement shown above. Follow the exact format of `20260601000002_add_disbursements_to_financial_entries.sql`.

---

### Task 2 — `FinancialEntry` model (`financial_entry.dart`)

**Add field to class:**

```dart
final bool? depositToSavings;
```

**Add to constructor** (after `disbursements`):

```dart
this.depositToSavings,
```

**Add to `fromJson`** (after `disbursements` line):

```dart
depositToSavings: json['deposit_to_savings'] as bool?,
```

**Add to `toJson`** (after `'disbursements'` entry):

```dart
'deposit_to_savings': depositToSavings,
```

No other changes to this file.

---

### Task 3 — Repository (`financial_entry_repository.dart`)

**`insertEntry` method — add parameter:**

```dart
bool? depositToSavings,
```

(after `Map<String, int>? disbursements,`)

**`insertEntry` method — add to payload map** (after `'disbursements': disbursements,`):

```dart
'deposit_to_savings': depositToSavings,
```

**`updateEntry` method — add parameter:**

```dart
bool? depositToSavings,
```

(after `Map<String, int>? disbursements,`)

**`updateEntry` method — add to update map** (after `'disbursements': disbursements,`):

```dart
'deposit_to_savings': depositToSavings,
```

Do **not** modify `upsertGigPayEntry`.

---

### Task 4 — Controller (`financials_controller.dart`)

**`addEntry` method — add parameter:**

```dart
bool? depositToSavings,
```

(after `Map<String, int>? disbursements,`)

**`addEntry` method — pass through to `repo.insertEntry`** (after `disbursements: disbursements,`):

```dart
depositToSavings: depositToSavings,
```

**`updateEntry` method — add parameter:**

```dart
bool? depositToSavings,
```

(after `Map<String, int>? disbursements,`)

**`updateEntry` method — pass through to `repo.updateEntry`** (after `disbursements: disbursements,`):

```dart
depositToSavings: depositToSavings,
```

---

### Task 5 — Add Entry Bottom Sheet (`add_financial_entry_bottom_sheet.dart`)

#### 5a — `_SaveCallback` typedef

Add named optional parameter at the end (after `Map<String, int>? disbursements,`):

```dart
bool? depositToSavings,
```

#### 5b — State variable

In `_AddFinancialEntryBottomSheetState`, add after `bool _disburse = false;`:

```dart
bool _depositToSavings = false;
```

#### 5c — `initState` pre-fill

In the `if (entry != null)` branch, after `_is1099Expected = entry.is1099Expected ?? false;`, add:

```dart
_depositToSavings = entry.depositToSavings ?? false;
```

#### 5d — `_setIsIncome` reset

In `_setIsIncome`, inside the existing `if (!isIncome && _disburse)` block, add after resetting `_disburse`:

```dart
if (!isIncome && _depositToSavings) {
  _depositToSavings = false;
}
```

#### 5e — Toggle UI

In the `build` method's `Column` children, **directly after** the closing `],` of the
`if (_isIncome && widget.members.isNotEmpty)` block (the "Disburse to Band" block),
add a new block:

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
  const SizedBox(height: Spacing.space16),
],
```

> **Note on placement when members list is empty:** The "Disburse to Band" block is
> guarded by `_isIncome && widget.members.isNotEmpty`. When members is empty, that
> block is entirely absent. "Deposit to Savings" is guarded only by `_isIncome`,
> so it will always appear for income entries, immediately after wherever the
> Disburse block would be.

#### 5f — `_save()` pass-through

In `_save()`, in the `widget.onSave(...)` call, add after `disbursements: disbursements,`:

```dart
depositToSavings: _isIncome ? _depositToSavings : null,
```

---

### Task 6 — Entry Details Bottom Sheet (`financial_entry_details_bottom_sheet.dart`)

#### 6a — Display the field

In `_FinancialEntryDetailsSheet.build()`, in the detail rows section, after the
`if (entry.description != null && entry.description!.isNotEmpty)` block, add:

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

#### 6b — Edit callback signature

In the Edit button's `onSave` lambda (inside the `onPressed` callback), update the
function signature to add `depositToSavings` after `disbursements`:

```dart
bool? depositToSavings,
```

Then pass it through to `notifier.updateEntry(...)` (after `disbursements: disbursements,`):

```dart
depositToSavings: depositToSavings,
```

---

### Task 7 — Financials Screen (`financials_screen.dart`)

#### 7a — New column width constant

After the existing column-width constants, add:

```dart
const _kSavingsWidth = 64.0;
```

Update `_kFixedColumnsWidth` to include the new width:

```dart
const _kFixedColumnsWidth = _kDateWidth +
    _kTypeWidth +
    _kFromWidth +
    _kPaidToWidth +
    _kDisbursedWidth +
    _kSavingsWidth +
    _k1099Width;
```

#### 7b — `_TableHeader`

In `_TableHeader.build()`, between the `_kDisbursedWidth` cell and the `_k1099Width`
cell, add:

```dart
SizedBox(
  width: _kSavingsWidth,
  child: _HeaderCell('Savings',
      textAlign: TextAlign.center, borderSide: borderSide),
),
```

#### 7c — `_EntryTableRow`

In `_EntryTableRow.build()`, between the "Disbursed" cell and the "1099" cell, add:

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

#### 7d — `_TotalRow` spacer

Update the trailing `SizedBox` to include the new column width:

```dart
SizedBox(width: _kDisbursedWidth + _kSavingsWidth + _k1099Width),
```

#### 7e — FAB `onSave` lambda

In the FAB's `onSave` lambda, add `depositToSavings` to both the lambda parameter
list (after `disbursements,`) and the `notifier.addEntry(...)` call (after
`disbursements: disbursements,`):

```dart
// Lambda parameter
bool? depositToSavings,

// Pass-through
depositToSavings: depositToSavings,
```

---

## System Impact

| System                                                  | Impact                                               |
| ------------------------------------------------------- | ---------------------------------------------------- |
| Financials — entry add/edit                             | **Affected** — new field throughout the stack        |
| Financials — table view                                 | **Affected** — new "Savings" column                  |
| Financials — entry details view                         | **Affected** — new detail row                        |
| Financials — PDF export                                 | Unaffected (does not render per-entry boolean flags) |
| Gig Pay flow (`GigPayBottomSheet`, `upsertGigPayEntry`) | **Unaffected** — explicitly out of scope             |
| Gigs                                                    | Unaffected                                           |
| Rehearsals                                              | Unaffected                                           |
| Setlists / Catalog                                      | Unaffected                                           |
| Members / RBAC                                          | Unaffected                                           |
| Auth / Session                                          | Unaffected                                           |
| Routing                                                 | Unaffected                                           |
| Notifications                                           | Unaffected                                           |

---

## Guardrail Compliance

- No new RLS policies → no recursion risk.
- No `catch (e) { return []; }` masking.
- No new global color definitions — uses `AppColors.primary` from `design_tokens.dart`.
- No new architecture introduced — all changes follow the existing `disbursements` pattern.
- `upsertGigPayEntry` not modified.
- `GigPayBottomSheet` not modified.
- No initialization order changes.
- No new config loaders.
- Nullable `bool?` in model → no parse failure on rows predating the migration.

---

## Validation Checklist (for QA)

- [ ] `flutter analyze` passes with 0 errors after all changes.
- [ ] New migration file exists and matches the naming convention.
- [ ] `FinancialEntry.fromJson` correctly reads `deposit_to_savings` from JSON.
- [ ] `FinancialEntry.toJson` emits `deposit_to_savings`.
- [ ] "Deposit to Savings" toggle appears on the Add Entry sheet for income entries.
- [ ] "Deposit to Savings" toggle does **not** appear for expense entries.
- [ ] "Deposit to Savings" toggle is independent of "Disburse to Band" — both can be on simultaneously.
- [ ] Toggle state resets to `false` when switching from Income to Expense.
- [ ] Edit flow pre-fills `_depositToSavings` from `entry.depositToSavings ?? false`.
- [ ] `insertEntry` and `updateEntry` in repository include `deposit_to_savings` in their payloads.
- [ ] `upsertGigPayEntry` is unchanged.
- [ ] Details sheet shows "Deposit to Savings: Yes" row only when the flag is `true`.
- [ ] Financials table shows a savings icon in the new "Savings" column when `depositToSavings == true`.
- [ ] `_TotalRow` spacer accounts for the new column width.
- [ ] FAB `onSave` lambda passes `depositToSavings` through to `notifier.addEntry`.
- [ ] Details sheet edit callback passes `depositToSavings` through to `notifier.updateEntry`.
