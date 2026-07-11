# Engineer Report

## Feature Slug

expense-delete-drawer

## Feature Title

Add Delete Capability to Edit Expense Drawer

## Goal

Enable users to delete financial entries (expenses/income) from the Edit Entry drawer flow. The delete action requires confirmation and is available to all active band members (same permission model as edit).

## Architect Tasks Completed

- [x] Task 1 — Add `deleteEntry(String entryId)` to `FinancialsNotifier`
- [x] Task 2 — Update `add_financial_entry_bottom_sheet.dart` with optional `onDelete` callback, new Save/Cancel side-by-side + Delete-below layout, and `_handleDelete()` method with confirmation dialog
- [x] Task 3 — Update `financial_entry_details_bottom_sheet.dart` to pass `onDelete` callback wired to `notifier.deleteEntry()` + pop details sheet
- [x] Task 4 — Run `flutter analyze` — 0 errors achieved
- [x] Task 5 — Format changed files with `dart format`

## Files Created

- none

## Files Modified

- `lib/features/financials/financials_controller.dart`
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
- `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 4 pre-existing deprecation warnings in unrelated setlist files (not introduced by this implementation)

## Test Results

Not run — requires manual testing per Architect plan

## Verification

Manual testing required (per Architect plan Verification Plan section):

**Test 1 — Delete regular expense**

- Create test expense entry (type: "Equipment", $100)
- Tap entry → Details sheet opens
- Tap "Edit Entry" → Edit drawer opens
- Verify button layout: Save and Cancel side by side, "Delete expense" below
- Tap "Delete expense" → Confirmation dialog appears
- Tap "Cancel" → Dialog closes, Edit drawer remains open
- Tap "Delete expense" again → Confirmation dialog appears
- Tap "Delete" → Entry deleted, drawer closes, entry removed from Financials screen

**Test 2 — Delete income entry**

- Create test income entry (type: "Merch Sale", $50)
- Follow same flow as Test 1
- Verify confirmation message shows "income" (not "expense")

**Test 3 — Delete gig_pay entry**

- Create gig with pay amount via Gigs screen
- Verify financial entry created (type: "Gig Pay")
- Delete financial entry via Financials screen
- Navigate to Gigs → verify gig.gig_pay is now null (cleared by trigger)

**Test 4 — Add mode has no delete button**

- On Financials screen, tap "+" to add new entry
- Verify button layout: only Save and Cancel (no delete button)

**Test 5 — Permission check**

- As band Owner, delete an entry → succeeds
- As band Contributor, delete an entry → succeeds (same permission as edit)

**Test 6 — Cross-platform**

- Test on macOS
- Test on web (localhost or deployed)
- Test on iOS simulator (if available)
- Verify button layout and delete flow work identically

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes — Implementation complete, all Architect tasks executed, 0 analyzer errors. Ready for manual testing and QA verification.

---

# Commit 2: RBAC Enforcement for Financial Entries

**Date:** 2026-07-11  
**Trigger:** Post-QA requirement clarification — Contributors must be view-only for financials  
**Scope:** Tasks 6-9 from ARCHITECT_PLAN.md "REVISION — Financials RBAC Fix" section

## Pre-Migration Check

**Query Executed:**

```sql
SELECT COUNT(*)
FROM financial_entries fe
JOIN band_members bm ON bm.band_id = fe.band_id AND bm.user_id = fe.created_by
WHERE bm.role = 'contributor';
```

**Result:** count = 0  
**Conclusion:** No Contributors have created financial entries in production. Migration is safe to proceed.

## Architect Tasks Completed

- [x] Task 6 — Create migration file `supabase/migrations/20260711081810_tighten_financial_entries_rbac.sql` to tighten INSERT, UPDATE, and DELETE RLS policies on `financial_entries` to admin & member only
- [x] Task 7 — Add `canCreateFinancials` and `canDeleteFinancials` getters to `lib/features/members/permissions/band_permissions.dart`
- [x] Task 8 — Hide FloatingActionButton in `lib/features/financials/financials_screen.dart` for users without `canCreateFinancials`
- [x] Task 9 — Hide Delete button in `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` for users without `canDeleteFinancials`
- [x] Run `flutter analyze` — 0 errors achieved
- [x] Format changed files with `dart format`

## Files Created

- `supabase/migrations/20260711081810_tighten_financial_entries_rbac.sql`

## Files Modified (This Commit)

- `lib/features/members/permissions/band_permissions.dart`
- `lib/features/financials/financials_screen.dart`
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`

## Migration Details

**Migration NOT Applied:** Per project guardrails, the migration file has been created but NOT executed against any environment (including staging). Tony will apply the migration manually using `supabase db push` or `supabase db query` after verifying the project-ref configuration.

**What the migration does:**

1. Replaces `financial_entries_insert` policy — requires `role IN ('admin', 'member')`
2. Replaces `financial_entries_delete` policy — requires `role IN ('admin', 'member')`
3. Replaces `financial_entries_update` policy — requires `role IN ('admin', 'member')`
4. SELECT policy unchanged — Contributors with `can_view_financials = true` can still view entries

**Breaking Change:** Contributors lose create/edit/delete access to financial entries. They retain view-only access if `can_view_financials` is enabled. This aligns with the RBAC pattern used for gigs and setlists.

## UI Permission Guards

### Task 7: BandPermissions Getters

Added two new getters to `band_permissions.dart`:

```dart
bool get canCreateFinancials => isAdmin || isMember;
bool get canDeleteFinancials => isAdmin || isMember;
```

### Task 8: Hide Add Button

Wrapped `floatingActionButton` in `financials_screen.dart` with a conditional check:

```dart
final permissionsAsync = ref.watch(currentUserPermissionsProvider);
final canCreate = permissionsAsync.when(
  data: (p) => p.canCreateFinancials,
  loading: () => false,  // Fail-closed during loading
  error: (_, __) => false,
);
if (!canCreate) return null;
```

### Task 9: Hide Delete Button

Wrapped delete button in `add_financial_entry_bottom_sheet.dart` with a `Consumer` that checks `canDeleteFinancials`:

```dart
Consumer(
  builder: (context, ref, _) {
    final permissionsAsync = ref.watch(currentUserPermissionsProvider);
    final canDelete = permissionsAsync.when(
      data: (p) => p.canDeleteFinancials,
      loading: () => false,  // Fail-closed during loading
      error: (_, __) => false,
    );
    if (!canDelete) return const SizedBox.shrink();
    // ... delete button ...
  },
)
```

## Analyzer Results

Command: `flutter analyze`  
Result: 0 errors, 4 pre-existing deprecation warnings in unrelated setlist files (not introduced by this implementation)

## Implementation Notes

**AsyncValue Pattern:** Used `.when(data:, loading:, error:)` pattern to access `AsyncValue<BandPermissions>` from `currentUserPermissionsProvider`, consistent with existing codebase conventions. The `.valueOrNull` API is not available in flutter_riverpod 3.0.3.

**Fail-Closed Strategy:** During permission loading or error states, both `canCreateFinancials` and `canDeleteFinancials` default to `false`. This ensures Contributors never briefly see admin/member UI affordances before permissions resolve.

## Deviations From Architect Plan

None — Tony confirmed UPDATE should be included in the migration (admin & member only). All 4 tasks executed as specified.

## Blockers Encountered

None

## Ready For QA

**Migration:** NOT APPLIED. Tony must apply the migration to staging/production manually.  
**Flutter Code:** Yes — 0 analyzer errors, all UI guards implemented. Ready for QA verification per the revised Verification Plan (Tests 1-9) in ARCHITECT_PLAN.md.

**QA Scope for This Commit:**

- Test 5 (revised): Admin/Member can create/delete; Contributor cannot (RLS enforced)
- Test 7 (new): Contributor with `can_view_financials = true` can view entries but cannot see Add or Delete buttons
- Test 8 (new): Direct repository call by Contributor fails with RLS error
- Tests 1-4, 6, 9: Re-verify no regression in delete UI feature from Commit 1
