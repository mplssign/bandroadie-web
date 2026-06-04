# QA Report

## Feature Slug

`deposit-to-savings-amount`

## Feature Title

Deposit to Savings: Amount Field + Gate Financials Behind Contributor Sub-Permission

## Final Verdict

**REQUIRES CHANGES**

---

## Validation Summary

All 14 Architect-defined tasks are functionally implemented and `flutter analyze` reports 0 issues. However, five out-of-scope modifications were made: both SQL migration files are untracked (not in `git diff main` and not committed), one non-feature config file was modified, a version bump was applied to two files not in the plan, and opportunistic renaming and formatting churn were introduced across existing code. Validation was performed exclusively by code-path analysis; runtime behavior was not exercised.

---

## Architect Scope Review

- **Scope adherence:** violated — see out-of-scope modifications below
- **Files modified as expected:** all 11 plan-approved Dart/SQL files modified correctly
- **Files off-limits violations:**
  - `dart_defines.json` — modified (removal of `DEMO_PASSWORD` key); not in Architect plan
  - `pubspec.yaml` — version bump (1.2.17+167 → 1.2.18+168); not in Architect plan
  - `web/version.json` — version bump; not in Architect plan

---

## Completeness Check

- **All Architect tasks implemented:** yes
- **Missing tasks:** none — B-1 through B-5 and A-1 through A-9 all have corresponding code changes

> **CRITICAL — migration files not committed to git:**
> Both SQL migration files exist on disk but are `??` (untracked) in `git status`. Neither appears in `git diff main`. They will not be included in a push or merge without being staged and committed. This is the most severe issue in this review.
>
> - `supabase/migrations/20260604000000_add_deposit_to_savings_cents_to_financial_entries.sql` — untracked
> - `supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql` — untracked

---

## Behavior Verification

**Validation method:** code-path analysis only.

### Feature A — Deposit to Savings Amount

| Check                                                                                                                                         | Result       |
| --------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| `AnimatedSize` uses `duration: const Duration(milliseconds: 200)` and `curve: Curves.easeInOut`                                               | ✅ Confirmed |
| `_depositToSavingsController` initialised in both edit and new-entry branches of `initState`                                                  | ✅ Confirmed |
| `_depositToSavingsController.dispose()` called in `dispose()` before `super.dispose()`                                                        | ✅ Confirmed |
| `_save()` passes `null` for `depositToSavingsCents` when toggle is off or entry is expense                                                    | ✅ Confirmed |
| `formattedDepositToSavings` getter lives in `FinancialEntry` (not in details sheet)                                                           | ✅ Confirmed |
| Details sheet shows formatted amount when `depositToSavingsCents != null`; falls back to `'Yes'` for legacy rows                              | ✅ Confirmed |
| Savings column: formatted dollar text when cents present, `AppIcons.dollar` icon fallback when bool true but cents null, empty otherwise      | ✅ Confirmed |
| `_kSavingsWidth` = 80.0 (new constant)                                                                                                        | ✅ Confirmed |
| `_kFixedColumnsWidth` sum expression updated to include `_kSavingsWidth`                                                                      | ✅ Confirmed |
| `_TotalRow` spacer `SizedBox` width updated to include `_kSavingsWidth`                                                                       | ✅ Confirmed |
| `upsertGigPayEntry` untouched                                                                                                                 | ✅ Confirmed |
| `_setIsIncome`: two-line form `_depositToSavings = false; _depositToSavingsController.cents = 0` inside `if (!isIncome && _depositToSavings)` | ✅ Confirmed |

> **Context note:** `main` does not contain the `feature/deposit-to-savings-toggle` changes. As a result, `depositToSavings` (bool) was added alongside `depositToSavingsCents` in model, repository, and controller. The Architect Plan was written under the assumption the toggle PR had already merged. The implementation is functionally correct for the actual branch state.

### Feature B — Contributor Financials Permission

| Check                                                                                                                                          | Result       |
| ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| `canViewFinancials` declared once in `build()` via `.when()`, fail-closed                                                                      | ✅ Confirmed |
| `canViewFinancials` threaded as `required bool` named parameter into `_buildContentState()`                                                    | ✅ Confirmed |
| `onFinancials:` guard uses `canViewFinancials` (not `!isContributor`)                                                                          | ✅ Confirmed |
| `showFinancials:` guard uses `canViewFinancials` (not `!isContributor`)                                                                        | ✅ Confirmed |
| `isContributor` variable still present and used elsewhere in file                                                                              | ✅ Confirmed |
| No duplicate `_handleOpenFinancials` method                                                                                                    | ✅ Confirmed |
| `ContributorPermissions.allEnabled` explicitly sets `canViewFinancials: true`                                                                  | ✅ Confirmed |
| `ContributorPermissions.allDisabled` explicitly sets `canViewFinancials: false`                                                                | ✅ Confirmed |
| `_permissionsEqual` in `role_management_sheet.dart` includes `a.canViewFinancials == b.canViewFinancials`                                      | ✅ Confirmed |
| `'Can view financials'` toggle in contributor sub-permissions section via `_buildPermissionToggle`                                             | ✅ Confirmed |
| `BandPermissions.canViewFinancials` returns `true` for admin/member, delegates to `subPermissions?.canViewFinancials ?? false` for contributor | ✅ Confirmed |

---

## Regression Check

- **Risk level:** MEDIUM
- **Systems reviewed:** Financials (model, repository, controller, form, details sheet, table), Home (permissions guard), Members (contributor permissions model, computed getter, management sheet)
- **Regressions found:**
  1. **`home_tab_content.dart` — opportunistic rename of 11 error handler callbacks** (GUARDRAILS §7: "Never refactor opportunistically"):
     All pre-existing `error: (__, _) =>` closures in `build()` were renamed to numbered parameter names: `(e1, stack1)`, `(e2, stack2)` … `(e12, stack12)`. None of these changes are part of B-4. This produces a style inconsistency because the new `canViewFinancials` error handler (added as part of B-4) retains the old `(_, __)` pattern — matching the Architect Plan — while the 11 surrounding handlers now use numbered names.

  2. **`financials_screen.dart` — formatting churn on existing lines** (GUARDRAILS §7, QA Phase 10):
     Multiple pre-existing lines were reformatted (code style rewraps of `AppTextStyles.pageTitle.copyWith(...)`, `onChanged` arrow chains, and a `separatorBuilder` parameter rename from `(_, __)` to `(context, index)`). These are not part of A-7 or A-9.

---

## Database Safety

- **Migration A-1** (`20260604000000_add_deposit_to_savings_cents_to_financial_entries.sql`): SQL verified on disk. Adds `deposit_to_savings_cents INTEGER` with `IF NOT EXISTS`, no DEFAULT (nullable). Correct per Architect specification. **Not committed to git.**
- **Migration B-1** (`20260604000001_add_can_view_financials_to_contributor_permissions.sql`): SQL verified on disk. Adds `can_view_financials BOOLEAN NOT NULL DEFAULT FALSE` with `IF NOT EXISTS`. Correct per Architect specification. **Not committed to git.**
- RLS policies: unaffected (column additions only)
- No self-referencing policies, no privilege escalation, no destructive behaviour
- `upsertGigPayEntry` RPC: unmodified — confirmed

> **Both migration files must be staged (`git add`) and committed before this branch can be merged. Without committed migrations, the schema changes cannot be deployed.**

---

## Analyzer Results

**Command:** `flutter analyze`
**Result:** No issues found. (ran in 4.3s — confirmed by QA run)

---

## Out-of-Scope Modifications Summary

| File                               | Change                                       | In Architect Plan? | GUARDRAILS   |
| ---------------------------------- | -------------------------------------------- | ------------------ | ------------ |
| `dart_defines.json`                | `DEMO_PASSWORD: ""` key removed              | No                 | §7 violation |
| `pubspec.yaml`                     | Version bump 1.2.17+167 → 1.2.18+168         | No                 | §7 violation |
| `web/version.json`                 | Version bump 1.2.17 → 1.2.18                 | No                 | §7 violation |
| `home_tab_content.dart` (11 hunks) | Error handler param renames unrelated to B-4 | No                 | §7 violation |
| `financials_screen.dart` (3 hunks) | Line reformats unrelated to A-7/A-9          | No                 | §7 violation |

---

## Required Actions Before Re-Review

1. **Stage and commit both migration files:**

   ```
   git add supabase/migrations/20260604000000_add_deposit_to_savings_cents_to_financial_entries.sql
   git add supabase/migrations/20260604000001_add_can_view_financials_to_contributor_permissions.sql
   git commit -m "feat(financials): add deposit_to_savings_cents and can_view_financials migrations"
   ```

2. **Revert `dart_defines.json`** — restore `DEMO_PASSWORD: ""` key (or get explicit Architect approval to remove it).

3. **Revert `pubspec.yaml` and `web/version.json`** version bumps, or obtain explicit Architect approval.

4. **Revert the 11 opportunistic error handler renames in `home_tab_content.dart`** — restore `(e1, stack1)` … `(e12, stack12)` back to `(__, _)` or `(_, __)` to match the file's pre-existing style.

5. **Revert formatting churn in `financials_screen.dart`** — restore the three reformatted pre-existing hunks.

After all five items are resolved, re-run `flutter analyze` and resubmit for QA.
