# QA REPORT

## Feature: deposit-to-savings-toggle

**Branch:** `feature/deposit-to-savings-toggle`
**QA Agent:** Copilot QA Agent
**Date:** 2026-06-04
**Engineer Report reviewed:** `docs/features/deposit-to-savings-toggle/ENGINEER_REPORT.md`

---

## Verdict: APPROVED

---

## Method

- Read `docs/agents/QA.md`, `docs/agents/GUARDRAILS.md`, `ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md` in full.
- Ran `git branch --show-current` and `git status` to verify workspace state.
- Ran `git diff main` and read every hunk of every changed file.
- Read current file content for all modified source files to cross-check diff.
- Ran `flutter analyze` independently — confirmed 0 issues.
- All validation is **code path analysis**. No device or runtime testing was performed.

---

## Workspace State

- Branch: `feature/deposit-to-savings-toggle` ✅
- Working tree: 6 feature files modified + 1 migration created. Pre-existing changes to `dart_defines.json`, `pubspec.yaml`, `web/version.json` were present before Engineer work (confirmed by prior session terminal context — they are out of Engineer scope). ✅

---

## Validation Checklist

### ✅ `flutter analyze` passes with 0 errors after all changes

Independently confirmed. Output: `No issues found! (ran in 4.5s)`

### ✅ New migration file exists and matches the naming convention

File: `supabase/migrations/20260603000000_add_deposit_to_savings_to_financial_entries.sql`  
Content matches plan exactly:

```sql
ALTER TABLE public.financial_entries
  ADD COLUMN IF NOT EXISTS deposit_to_savings BOOLEAN DEFAULT FALSE;
```

Format matches `20260601000002_add_disbursements_to_financial_entries.sql`.

### ✅ `FinancialEntry.fromJson` correctly reads `deposit_to_savings` from JSON

Confirmed in code: `depositToSavings: json['deposit_to_savings'] as bool?,`  
Positioned after `disbursements` line, as specified.

### ✅ `FinancialEntry.toJson` emits `deposit_to_savings`

Confirmed in code: `'deposit_to_savings': depositToSavings,`  
Positioned after `'disbursements'` entry, as specified.

### ✅ "Deposit to Savings" toggle appears on the Add Entry sheet for income entries

Toggle block is guarded by `if (_isIncome) ...[...]`. Confirmed in both diff and current file.

### ✅ "Deposit to Savings" toggle does NOT appear for expense entries

The `if (_isIncome)` guard ensures the block is absent when `_isIncome == false`. Confirmed.

### ✅ Both toggles are independent — "Disburse to Band" and "Deposit to Savings" can be on simultaneously

The two toggles have separate state variables (`_disburse`, `_depositToSavings`), separate `Switch` widgets, and separate reset logic. No code path mutually excludes them. `_onDisburseToggle` does not touch `_depositToSavings`; the Deposit to Savings `onChanged` does not touch `_disburse`. ✅

### ✅ Toggle state resets to `false` when switching from Income to Expense

`_setIsIncome` contains:

```dart
if (!isIncome && _depositToSavings) {
  _depositToSavings = false;
}
```

This unconditionally resets `_depositToSavings` on switch to expense.

> **Minor deviation from plan wording (non-blocking):** The plan specified placing this block _inside_ the existing `if (!isIncome && _disburse)` block. The Engineer placed it as a parallel sibling `if` block at the same level. This is the semantically correct approach — resetting `_depositToSavings` unconditionally rather than only when `_disburse` was also true. The observable behavior matches the checklist item ("resets to `false` when switching from Income to Expense") and is strictly safer. Not a defect.

### ✅ Edit flow pre-fills `_depositToSavings` from `entry.depositToSavings ?? false`

Confirmed in `initState`:

```dart
_depositToSavings = entry.depositToSavings ?? false;
```

Positioned after `_is1099Expected = entry.is1099Expected ?? false;`, as specified.

### ✅ `insertEntry` and `updateEntry` in repository include `deposit_to_savings` in their payloads

Both methods have `bool? depositToSavings,` parameter added after `disbursements` and `'deposit_to_savings': depositToSavings,` in the respective payload maps. Confirmed in diff and current file.

### ✅ `upsertGigPayEntry` is unchanged

Confirmed by direct inspection. The method signature, payload map, and logic are identical to main. No `deposit_to_savings` key anywhere in this method. ✅

### ✅ Details sheet shows "Deposit to Savings: Yes" row only when the flag is `true`

Confirmed: `if (entry.depositToSavings == true)` guards the `_DetailRow` block. Row uses `AppIcons.dollar`, label `'Deposit to Savings'`, value `'Yes'`.

### ✅ Financials table shows a savings icon in the new "Savings" column when `depositToSavings == true`

`_EntryTableRow` contains a new `_kSavingsWidth` cell between Disbursed and 1099. Shows `AppIcons.dollar` with `color: AppColors.primary` when `entry.depositToSavings == true`; otherwise `SizedBox.shrink()`. Confirmed.

### ✅ `_TotalRow` spacer accounts for the new column width

Confirmed: `SizedBox(width: _kDisbursedWidth + _kSavingsWidth + _k1099Width)`

### ✅ `_kFixedColumnsWidth` includes `_kSavingsWidth`

Confirmed:

```dart
const _kFixedColumnsWidth = _kDateWidth +
    _kTypeWidth +
    _kFromWidth +
    _kPaidToWidth +
    _kDisbursedWidth +
    _kSavingsWidth +
    _k1099Width;
```

### ✅ FAB `onSave` lambda passes `depositToSavings` through to `notifier.addEntry`

Lambda parameter list includes `depositToSavings,` and the `notifier.addEntry(...)` call includes `depositToSavings: depositToSavings,`. Confirmed in diff and current file.

### ✅ Details sheet edit callback passes `depositToSavings` through to `notifier.updateEntry`

The `onSave` lambda in the Edit button's `onPressed` includes `depositToSavings,` in its named parameters and `depositToSavings: depositToSavings,` in the `notifier.updateEntry(...)` call. Confirmed.

---

## Files Outside Architect Scope

The diff shows changes to three files not listed in the plan:

| File                | Change                                 | Origin                                      |
| ------------------- | -------------------------------------- | ------------------------------------------- |
| `dart_defines.json` | Removed `DEMO_PASSWORD: ""` entry      | Pre-existing on branch before Engineer work |
| `pubspec.yaml`      | Version bump `1.2.17+167 → 1.2.18+168` | Pre-existing on branch (version tool)       |
| `web/version.json`  | Version bump matching pubspec          | Pre-existing on branch (version tool)       |

These changes were present in the working tree before the Engineer started (confirmed by prior session terminal output). The Engineer did not introduce them. They do not affect the feature under review.

The `financials_screen.dart` diff includes minor whitespace reformatting of two pre-existing lines (text style and `onChanged` lambda line wraps). These changes are within a plan-listed file, do not alter code behavior, and `flutter analyze` passes. Not a defect.

---

## Guardrail Compliance

| Guardrail                                                  | Status                                    |
| ---------------------------------------------------------- | ----------------------------------------- |
| Initialization order unchanged                             | ✅ Confirmed                              |
| No new config loaders                                      | ✅ Confirmed                              |
| No service_role key usage                                  | ✅ Confirmed                              |
| No new RLS policies                                        | ✅ Confirmed                              |
| No SECURITY DEFINER added                                  | ✅ N/A                                    |
| `mounted` guards on async setState                         | ✅ No new async setState paths introduced |
| No controller disposal issues                              | ✅ No new controllers added               |
| `upsertGigPayEntry` untouched                              | ✅ Confirmed by direct inspection         |
| GigPayBottomSheet untouched                                | ✅ No diff on any GigPay file             |
| No new dependencies                                        | ✅ Confirmed                              |
| Nullable `bool?` model field — safe for pre-migration rows | ✅ Confirmed                              |

---

## Summary

All 16 checklist items from the Architect plan are satisfied. The implementation correctly follows the `disbursements` pattern end-to-end. One minor deviation from the plan's literal wording in `_setIsIncome` is actually the semantically correct implementation and introduces no defect. `flutter analyze` passes independently. No out-of-scope Engineer changes detected.

**Verdict: APPROVED**
