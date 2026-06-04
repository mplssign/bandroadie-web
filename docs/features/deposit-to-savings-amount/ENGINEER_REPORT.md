# ENGINEER_REPORT.md

**Branch:** `bug/deposit-to-savings-amount`
**Date:** 2026-06-04
**Engineer:** AI (GitHub Copilot / Claude Sonnet 4.6)

---

## Summary

All 14 tasks from `ARCHITECT_PLAN.md` implemented in full. `flutter analyze` passes with **0 errors**.

---

## Tasks Completed

### Feature B — Gate Financials Behind Contributor Sub-Permission

| Task | File                                                                                        | Status      |
| ---- | ------------------------------------------------------------------------------------------- | ----------- |
| B-1  | `supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql` | ✅ Created  |
| B-2  | `lib/features/members/permissions/contributor_permissions.dart`                             | ✅ Modified |
| B-3  | `lib/features/members/permissions/band_permissions.dart`                                    | ✅ Modified |
| B-4  | `lib/features/home/home_tab_content.dart`                                                   | ✅ Modified |
| B-5  | `lib/features/members/widgets/role_management_sheet.dart`                                   | ✅ Modified |

**B-1:** Created SQL migration adding `can_view_financials BOOLEAN NOT NULL DEFAULT FALSE` to `contributor_permissions`.

**B-2:** Added `canViewFinancials` field (default `false`) to `ContributorPermissions` class. Updated: field declaration, constructor, `allEnabled` (explicit `canViewFinancials: true`), `allDisabled` (explicit `canViewFinancials: false`), `fromJson`, `toJson`, `copyWith`, `toString`.

**B-3:** Added `canViewFinancials` computed getter to `BandPermissions` — returns `true` for admin/member, delegates to `subPermissions?.canViewFinancials ?? false` for contributor.

**B-4:** Added `canViewFinancials` derived variable (`.when()` pattern, fail-closed) inside `build()`. Added `required bool canViewFinancials` parameter to `_buildContentState()` signature and passed it at the call site. Replaced two `!isContributor` financials guards with `canViewFinancials` inside `_buildContentState`. The `isContributor` variable was preserved — it is still used elsewhere. Also removed a duplicate `_handleOpenFinancials` method that had been introduced by an earlier edit session.

> **Note — Session 2 correction:** The B-4 edit was not persisted to disk during Session 1 (VS Code's `read_file` cache returned a stale in-memory view, masking the failure). The missing file was detected by an Implementation Gate review (`git diff main --name-only` showed `home_tab_content.dart` absent). The changes were applied and verified on disk in Session 2.

**B-5:** Added `a.canViewFinancials == b.canViewFinancials` to `_permissionsEqual`. Added `_buildPermissionToggle` for `'Can view financials'` after the `canViewMembers` toggle.

---

### Feature A — Deposit to Savings: Amount Field

| Task | File                                                                                       | Status      |
| ---- | ------------------------------------------------------------------------------------------ | ----------- |
| A-1  | `supabase/migrations/20260604000000_add_deposit_to_savings_cents_to_financial_entries.sql` | ✅ Created  |
| A-2  | `lib/features/financials/models/financial_entry.dart`                                      | ✅ Modified |
| A-3  | `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`                    | ✅ Modified |
| A-4  | `lib/features/financials/financial_entry_repository.dart`                                  | ✅ Modified |
| A-5  | `lib/features/financials/financials_controller.dart`                                       | ✅ Modified |
| A-6  | `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`                    | ✅ Modified |
| A-7  | `lib/features/financials/financials_screen.dart`                                           | ✅ Modified |
| A-8  | `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`                | ✅ Modified |
| A-9  | `lib/features/financials/financials_screen.dart`                                           | ✅ Modified |

**A-1:** Created SQL migration adding `deposit_to_savings_cents INTEGER` (nullable, no default) to `financial_entries`.

**A-2:** Added `final int? depositToSavingsCents` field, constructor parameter, `fromJson` parse (`json['deposit_to_savings_cents'] as int?`), `toJson` entry, and `formattedDepositToSavings` getter to `FinancialEntry`.

**A-3:** Added `int? depositToSavingsCents,` named parameter to `_SaveCallback` typedef.

**A-4:** Added `int? depositToSavingsCents` to `insertEntry` parameters and payload; added to `updateEntry` parameters and update map. `upsertGigPayEntry` was not touched.

**A-5:** Added `int? depositToSavingsCents` to `addEntry` and `updateEntry` in `FinancialsController`; forwarded to repository calls.

**A-6:**

- Added `late final CurrencyInputController _depositToSavingsController` state field.
- In `initState` edit branch: `_depositToSavingsController = CurrencyInputController(entry.depositToSavingsCents ?? 0)`.
- In `initState` new branch: `_depositToSavingsController = CurrencyInputController()`.
- In `dispose`: `_depositToSavingsController.dispose()` before `super.dispose()`.
- In `_setIsIncome`: replaced single-line reset with two-line corrected form (`_depositToSavings = false; _depositToSavingsController.cents = 0`) inside `if (!isIncome && _depositToSavings)`.
- In `_save`: added `depositToSavingsCents` local variable (null when toggle off or expense), passed to `widget.onSave`.
- In `build`: replaced the `Deposit to Savings` section's `SizedBox(height: Spacing.space16)` spacer after the toggle with `AnimatedSize` + `CurrencyTextField` expand, matching the Disburse to Band pattern exactly (`duration: 200ms`, `curve: Curves.easeInOut`).

**A-7:** Updated FAB `onSave` closure in `financials_screen.dart` to accept and forward `depositToSavingsCents`.

**A-8:**

- Updated `depositToSavings == true` detail row to show `entry.formattedDepositToSavings!` when cents is non-null, fallback `'Yes'` for legacy rows.
- Updated edit `onSave` closure to accept and forward `depositToSavingsCents`.

**A-9:** Changed `_kSavingsWidth` from `64.0` to `80.0`. Replaced icon-only Savings cell with conditional: shows formatted dollar text (primary color, w600, ellipsis) when `depositToSavingsCents != null`, falls back to `AppIcons.dollar` icon when bool is true but cents is null (backwards compatibility), shows `SizedBox.shrink()` otherwise.

---

## Constraints Checklist

- [x] `AnimatedSize` uses `duration: const Duration(milliseconds: 200)` and `curve: Curves.easeInOut`
- [x] `deposit_to_savings_cents` is a separate column from `deposit_to_savings`. Both coexist.
- [x] `_save()` passes `null` for `depositToSavingsCents` when `_depositToSavings` is false or entry is an expense
- [x] `canViewFinancials` defaults to `false` in DB column, `ContributorPermissions` constructor, `BandPermissions.canViewFinancials` fallback
- [x] `!isContributor` financials guard fully replaced — not supplemented
- [x] No `catch (e) { return []; }` pattern in new code
- [x] No new global color definitions — all colors use `AppColors` / `context.colors`
- [x] `upsertGigPayEntry` not modified
- [x] Every new `CurrencyInputController` disposed in `dispose()`
- [x] `ContributorPermissions.allEnabled` explicitly sets `canViewFinancials: true`
- [x] `ContributorPermissions.allDisabled` explicitly sets `canViewFinancials: false`

---

## Validation

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 4.4s)
```

_(Session 2 re-run after B-4 disk fix and duplicate method removal)_

---

## Session 3 — QA-Requested Reverts

QA review identified out-of-scope changes introduced in Session 2. Both were reverted:

**`home_tab_content.dart`** — 12 pre-existing `error:` closures in `build()` and helper methods had been opportunistically renamed from `(__, _)` / `(_, __)` to numbered parameter names (`e1, stack1` through `e12, stack12`). All were reverted to their original forms. The `separatorBuilder` on the `allPotentialEvents` `ListView.separated` had also been renamed from `(_, __)` to `(context, index)` — reverted.

**`financials_screen.dart`** — Three pre-existing code blocks had been reformatted: `AppTextStyles.pageTitle.copyWith(...)` line break, and two `onChanged` arrow-chain rewraps (`setViewMode`, `setDateFilter`). All three were reverted to their original formatting.

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 4.4s)
```

_(Session 3 re-run after out-of-scope revert)_
