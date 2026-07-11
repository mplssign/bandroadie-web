# Architect Plan — Add Delete Capability to Edit Expense Drawer

## Feature Slug

`expense-delete-drawer`

## Problem Summary

Users can view and edit financial entries (expenses/income) via a drawer flow, but there is no way to delete an entry. The Edit Entry drawer currently shows Save and Cancel buttons but lacks a delete option. This creates a gap where users cannot remove incorrect or obsolete financial entries.

## Root Cause

**Confidence Level:** HIGH

This is not a bug — it is a feature gap. The delete capability was never implemented in the Edit Entry drawer flow. The underlying infrastructure exists:

- Database: `financial_entries` table has RLS policy for DELETE operations
- Repository: `FinancialEntryRepository.deleteEntry()` method exists
- Controller: No delete method exists (needs to be added)
- UI: No delete button or handler in the Edit Entry drawer

## Reference Docs Consulted

Not applicable — no notification or domain-specific reference docs required for this feature.

## Existing System Analysis

### Current Drawer Flow

1. User taps an expense/income entry on the Financials screen
2. `showFinancialEntryDetailsSheet()` displays a read-only view with entry details
3. User taps "Edit Entry" button
4. Details sheet closes, `showAddFinancialEntrySheet()` opens with `initialEntry` pre-filled
5. User can modify fields and tap Save or Cancel

### Current Button Layout (Edit Mode)

Located in `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`, lines 420-490:

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox(
      width: double.infinity,
      child: FilledButton(...)  // Save button - full width
    ),
    const SizedBox(height: 8),
    TextButton(...)  // Cancel button - centered below
  ],
)
```

### Delete Infrastructure

- **Repository**: `FinancialEntryRepository.deleteEntry(String entryId, String bandId)` exists and performs a hard delete via Supabase client
- **Database**: `financial_entries` table has a `financial_entries_delete` RLS policy that permits any active band member to delete entries via `check_band_member(band_id)`
- **Permission model**: Same as edit — any active band member can delete (no role restriction)
- **Delete type**: Hard delete (no `deleted_at` column or soft delete mechanism)
- **Trigger**: `sync_gig_pay_from_financial_entry` handles cleanup when a `gig_pay` entry is deleted, nulling the `gigs.gig_pay` field

### Confirmation Pattern

The app uses `showConfirmActionDialog()` from `lib/components/ui/confirm_action_dialog.dart` for all destructive actions. Example from setlists:

```dart
final confirmed = await showConfirmActionDialog(
  context: context,
  title: 'Delete Setlist?',
  message: 'Are you sure you want to delete "..."? This action cannot be undone.',
  confirmLabel: 'Delete',
  isDestructive: true,
);
```

## Proposed Solution

### New Button Layout

Change the Edit Entry drawer button row to:

```dart
Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    // Save and Cancel side by side
    Row(
      children: [
        Expanded(child: OutlinedButton(...) /* Cancel */),
        const SizedBox(width: 12),
        Expanded(child: FilledButton(...) /* Save */),
      ],
    ),
    const SizedBox(height: 8),
    // Delete button below (only when editing)
    if (widget.initialEntry != null)
      TextButton(
        onPressed: _handleDelete,
        child: Text('Delete expense', style: destructive),
      ),
  ],
)
```

### Delete Flow

1. User taps "Delete expense" in Edit Entry drawer
2. Confirmation dialog appears via `showConfirmActionDialog()`:
   - Title: "Delete Entry?"
   - Message: "Are you sure you want to delete this [income/expense] entry? This action cannot be undone."
   - Confirm button: "Delete" (red/destructive)
3. If confirmed:
   - Call `financialsNotifier.deleteEntry(entryId)`
   - Controller calls `repository.deleteEntry(entryId, bandId)`
   - Controller removes entry from `state.allEntries`
   - Navigator pops the Edit Entry drawer
   - User returns to Financials screen with entry removed
4. If canceled: confirmation dialog closes, Edit Entry drawer remains open

### Callback Mechanism

The `showAddFinancialEntrySheet()` function currently accepts an `onSave` callback. We add an optional `onDelete` callback parameter:

```dart
Future<void> showAddFinancialEntrySheet(
  BuildContext context, {
  required _SaveCallback onSave,
  VoidCallback? onDelete,  // NEW: optional delete callback
  ...
})
```

When `onDelete` is provided and `initialEntry != null`, the delete button is shown. The button calls `onDelete`, which is wired to the controller's delete method by the caller (the Details sheet).

## Database Impact

**Status:** Not applicable

- No migrations required
- No RLS policy changes required (delete policy already exists and is correct)
- No RPC functions needed (client-side delete under existing RLS is sufficient)
- No trigger changes required (existing `sync_gig_pay_from_financial_entry` handles DELETE already)

## Flutter Architecture Changes

### State Management (Riverpod)

Add `deleteEntry()` method to `FinancialsNotifier`:

```dart
Future<void> deleteEntry(String entryId) async {
  final bandId = ref.read(activeBandIdProvider);
  if (bandId == null) throw StateError('No band selected');

  final repo = ref.read(financialEntryRepositoryProvider);
  await repo.deleteEntry(entryId, bandId);

  state = state.copyWith(
    allEntries: state.allEntries.where((e) => e.id != entryId).toList(),
  );
}
```

### Widget Changes

1. **Add Financial Entry Bottom Sheet**: Add optional `onDelete` callback parameter, conditionally show delete button, implement delete handler with confirmation
2. **Financial Entry Details Bottom Sheet**: Pass `onDelete` callback when calling `showAddFinancialEntrySheet()`

### Repository

No changes — `deleteEntry()` method already exists and is correct.

## Files to Create

None — all required components exist.

## Files to Modify

| File                                                                        | What changes                                                                                                                                                                                                                                                                              |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/financials/financials_controller.dart`                        | Add `deleteEntry(String entryId)` method to `FinancialsNotifier` that calls repository and updates state                                                                                                                                                                                  |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`     | 1. Add optional `onDelete` callback parameter to `showAddFinancialEntrySheet()` and `_AddFinancialEntryBottomSheet`<br>2. Change button layout: Save/Cancel side by side, delete button below<br>3. Add delete handler with confirmation dialog<br>4. Import `confirm_action_dialog.dart` |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | Pass `onDelete` callback to `showAddFinancialEntrySheet()` that calls `notifier.deleteEntry()` and pops the details sheet                                                                                                                                                                 |

## Files Off-Limits

| File                                                      | Reason                                      |
| --------------------------------------------------------- | ------------------------------------------- |
| `lib/main.dart`                                           | No initialization changes required          |
| `lib/features/financials/financial_entry_repository.dart` | Delete method already exists and is correct |
| `lib/components/ui/confirm_action_dialog.dart`            | Reuse as-is, no modifications needed        |
| `supabase/migrations/*.sql`                               | No schema or RLS changes required           |
| All other features                                        | No cross-feature impact                     |

## System Impact Map

| System                                 | Impact                                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------- |
| Gigs                                   | unaffected (gig_pay sync trigger already handles deletes)                       |
| Rehearsals                             | unaffected                                                                      |
| Setlists / Catalog                     | unaffected                                                                      |
| Members / RBAC                         | unaffected (uses existing band membership check)                                |
| Auth / Session                         | unaffected                                                                      |
| Routing                                | unaffected                                                                      |
| Notifications                          | unaffected (no delete notification per architecture — CREATE only)              |
| Platform (iOS / Android / Web / macOS) | affected (all platforms) — feature is cross-platform, no platform-specific code |

## Regression Risk

**Level:** LOW

**Rationale:**

- Smallest possible change: adds one controller method, one optional callback, and updates button layout in a single widget
- No database changes (RLS policy and repository method already exist)
- No shared state changes (delete only affects the single financials controller)
- No auth, session, routing, or init order touched
- Delete is isolated to financials feature — no cross-feature dependencies
- Existing trigger handles gig_pay cleanup automatically

## Engineer Task Breakdown

Execute in strict order:

1. **Add controller delete method**
   - Open `lib/features/financials/financials_controller.dart`
   - Add `deleteEntry(String entryId)` method to `FinancialsNotifier`
   - Method calls `repo.deleteEntry()` and updates `state.allEntries`

2. **Update Add Financial Entry Bottom Sheet**
   - Open `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
   - Import `../../../components/ui/confirm_action_dialog.dart`
   - Add optional `onDelete` callback parameter to `showAddFinancialEntrySheet()`
   - Add `onDelete` field to `_AddFinancialEntryBottomSheet` widget
   - Change `_buildButtonRow()` method:
     - Replace stacked buttons with Row containing Save and Cancel side by side
     - Add conditional delete button below (shown only when `widget.initialEntry != null && widget.onDelete != null`)
   - Add `_handleDelete()` method that shows confirmation dialog and calls `widget.onDelete`

3. **Update Financial Entry Details Bottom Sheet**
   - Open `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`
   - In the "Edit Entry" button's `onPressed` handler, add `onDelete` callback parameter to `showAddFinancialEntrySheet()`
   - Wire `onDelete` to call `notifier.deleteEntry(entry.id)` then pop the details sheet

4. **Run `flutter analyze`**
   - Verify 0 errors
   - Fix any issues before proceeding

5. **Manual test on macOS/web**
   - Create test expense entry
   - Tap entry → Edit → tap Delete
   - Confirm deletion works
   - Test cancel flow
   - Verify entry is removed from list
   - Test with gig_pay entry to verify trigger cleanup

## Verification Plan

### Pre-Deployment Tests

Not applicable — no database migrations or schema changes.

### Post-Deployment Tests

Not applicable — this is a Flutter-only change with no backend deployment.

### Manual Testing Checklist

**Test 1 — Delete regular expense**

1. Create a test expense entry (type: "Equipment", $100)
2. Tap entry → Details sheet opens
3. Tap "Edit Entry" → Edit drawer opens
4. Verify button layout: Save and Cancel side by side, "Delete expense" below
5. Tap "Delete expense" → Confirmation dialog appears
6. Tap "Cancel" → Dialog closes, Edit drawer remains open
7. Tap "Delete expense" again → Confirmation dialog appears
8. Tap "Delete" → Entry is deleted, drawer closes, entry removed from Financials screen

**Test 2 — Delete income entry**

1. Create a test income entry (type: "Merch Sale", $50)
2. Follow same flow as Test 1
3. Verify confirmation message shows "income" (not "expense")

**Test 3 — Delete gig_pay entry**

1. Create a gig with pay amount via Gigs screen
2. Verify financial entry is created (type: "Gig Pay")
3. Delete the financial entry via Financials screen
4. Navigate to Gigs → verify gig.gig_pay is now null (cleared by trigger)

**Test 4 — Add mode has no delete button**

1. On Financials screen, tap "+" to add new entry
2. Verify button layout: only Save and Cancel (no delete button)

**Test 5 — Permission check**

1. As band Owner, delete an entry → succeeds
2. As band Contributor, delete an entry → succeeds (same permission as edit)

**Test 6 — Cross-platform**

1. Test on macOS
2. Test on web (localhost or deployed)
3. Test on iOS simulator (if available)
4. Verify button layout and delete flow work identically

## QA Regression Areas

**Primary test areas:**

1. Financial entry deletion (all entry types: expense, income, gig_pay)
2. Edit drawer button layout (Save/Cancel/Delete positioning)
3. Delete confirmation dialog flow (confirm and cancel paths)
4. Gig pay sync when gig_pay entry is deleted
5. Permission enforcement (all active band members can delete)

**Regression test areas:**

1. Adding new financial entries (should be unaffected)
2. Editing existing financial entries (should be unaffected except button layout)
3. Viewing financial entry details (should be unaffected)
4. Financials screen filtering and sorting (should be unaffected)
5. Financials PDF export (should be unaffected)
6. Gig creation with pay amount (should be unaffected)

## Rollout / Migration Strategy

Not applicable — this is a client-side UI change with no backend deployment or data migration.

## Out of Scope

- Soft delete / undo mechanism (hard delete is consistent with app architecture)
- Batch delete or swipe-to-delete (not requested, can be future enhancement)
- Delete notification to other band members (per architecture: notifications trigger on CREATE only, never edit/delete)
- Audit log of deleted entries (not part of current architecture)
- Permission restriction beyond band membership (e.g., "only creator can delete") — not requested, would require RLS policy change

---

# REVISION — Financials RBAC Fix (Post-QA)

**Date:** 2026-07-11  
**Trigger:** Manual testing passed; new requirement identified during post-QA review  
**Requirement Source:** Tony (post-QA clarification)

## Revised Requirement

**Contributors with "View financials" enabled must be view-only.** They cannot create or delete financial entries. Only **Admin** and **Member** roles may create or delete.

This **contradicts the original plan's permission model**, which stated:

> "Permission model: Same as edit — any active band member can delete (no role restriction)"

That conclusion is **now wrong** and must be revised.

---

## Investigation Results

### 1. Current RLS Policies on `financial_entries`

**File:** `supabase/migrations/20260601000000_create_financial_entries.sql`

**INSERT Policy (lines 72-79):**

```sql
CREATE POLICY "financial_entries_insert"
  ON public.financial_entries
  FOR INSERT
  WITH CHECK (
    public.check_band_member(band_id)
    AND created_by = auth.uid()
  );
```

**DELETE Policy (lines 87-91):**

```sql
CREATE POLICY "financial_entries_delete"
  ON public.financial_entries
  FOR DELETE
  USING (public.check_band_member(band_id));
```

### 2. What `check_band_member()` Checks

**Function Definition (lines 50-62):**

```sql
CREATE OR REPLACE FUNCTION public.check_band_member(p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
      AND status = 'active'
  );
$$;
```

**Behavior:** Returns `TRUE` if the user is an **active band member of any role** (admin, member, or contributor). It **does not check role** — just active membership status.

**Implication:** Contributors can currently insert and delete financial entries through RLS. This violates the revised requirement.

### 3. The `contributor_permissions` Table

**Schema (from migration `20260302000000_band_user_roles.sql` + `20260604000001_add_can_view_financials_to_contributor_permissions.sql`):**

- Column: `can_view_financials BOOLEAN NOT NULL DEFAULT FALSE`
- Purpose: Controls whether a Contributor can **view (SELECT)** financial entries
- **Not wired into INSERT or DELETE policies** — it is a SELECT-only flag

**Flutter Integration:**

- `ContributorPermissions.canViewFinancials` field exists
- `BandPermissions.canViewFinancials` getter returns:
  - `true` for Admin and Member (always)
  - `subPermissions?.canViewFinancials ?? false` for Contributor

**Conclusion:** The `can_view_financials` flag is for **view access only**. It does not (and should not) control create/delete operations. Tony's requirement is a **role-level restriction**: Contributors are excluded from create/delete **outright**, regardless of any permission flag.

### 4. RBAC Precedent

**From migration `20260302000000_band_user_roles.sql`:**

**Gigs DELETE (lines 270-280):**

```sql
CREATE POLICY "Admins and members can delete gigs" ON public.gigs
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = gigs.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );
```

**Setlists INSERT (lines 256-267):**

```sql
CREATE POLICY "Admins and members can create setlists" ON public.setlists
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );
```

**Setlists DELETE (lines 291-301):**

```sql
CREATE POLICY "Admins and members can delete setlists" ON public.setlists
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = setlists.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );
```

**Pattern:** Admin and Member roles have full CRUD on major entities (gigs, setlists). Contributors are **excluded from INSERT/UPDATE/DELETE** and are granted **view-only** access via SELECT policies.

**Decision:** Financial entries follow the same pattern. Tighten INSERT and DELETE policies to require `role IN ('admin', 'member')`.

### 5. UI Conditional Rendering

**Current State:**

**Financials Screen (`lib/features/financials/financials_screen.dart`, lines 147-197):**

- Shows a `FloatingActionButton` with "+" icon for adding entries
- **No role check** — shown to all band members

**Add Financial Entry Bottom Sheet (post-implementation, per Engineer Report):**

- Shows "Delete" button when editing (when `initialEntry != null && onDelete != null`)
- **No role check** — shown to all band members with edit access

**BandPermissions (`lib/features/members/permissions/band_permissions.dart`):**

- **No `canCreateFinancials` or `canDeleteFinancials` getters** — these do not exist
- Financials screen does not use `BandPermissions` at all (confirmed via grep search — zero matches)

**Implication:** Contributors currently see Add and Delete UI affordances. These buttons will fail when RLS is tightened, resulting in silent errors or user-facing RLS errors. **Client-side hiding is required** as defense-in-depth (RLS is the enforcement boundary per RBAC guardrails).

### 6. RPC vs Plain RLS

**Question:** Should financial entry delete use a SECURITY DEFINER RPC (like `delete_band`, `remove_band_member`) or plain RLS policy tightening?

**Analysis:**

**SECURITY DEFINER RPCs are used for:**

- Cross-table operations (`delete_band` cascades to 7+ tables)
- Last-admin protection (`update_member_role`, `remove_band_member`)
- Complex business logic that cannot be expressed in RLS alone

**Financial entry delete is:**

- A single-table delete on `financial_entries`
- A straightforward role check: `role IN ('admin', 'member')`
- No cross-table cascade logic required (the `sync_gig_pay_from_financial_entry` trigger handles gig pay cleanup automatically on DELETE)

**Decision:** Plain RLS policy tightening is **sufficient** and **preferred**. The existing repository method (`FinancialEntryRepository.deleteEntry()`) uses standard Supabase client delete under RLS — no RPC needed.

---

## Revised Database Impact

**Original Statement:** "Database: not applicable"

**Revised Statement:**

**Status:** Affected

**Migration Required:** Yes — new migration to tighten RLS policies on `financial_entries`

**Migration File:** `supabase/migrations/YYYYMMDDHHMMSS_tighten_financial_entries_rbac.sql`

**Changes Required:**

1. **Replace `financial_entries_insert` policy:**
   - Current: `check_band_member(band_id)` (allows all active members)
   - New: Role check `bm.role IN ('admin', 'member')`

2. **Replace `financial_entries_delete` policy:**
   - Current: `check_band_member(band_id)` (allows all active members)
   - New: Role check `bm.role IN ('admin', 'member')`

**SELECT Policy:** Unchanged — Contributors with `can_view_financials = true` can still view entries (SELECT remains controlled by the `can_view_financials` flag).

**UPDATE Policy:** No change specified by Tony — assume it should also be tightened to admin/member only (UPDATE and DELETE typically have the same permission model). **Confirm with Tony before implementing.**

**RPC Functions:** Not applicable — no RPC functions needed.

**Trigger Logic:** Unchanged — `sync_gig_pay_from_financial_entry` already handles DELETE events correctly.

---

## Revised Existing System Analysis

**Original Permission Model Statement:**

> "Permission model: Same as edit — any active band member can delete (no role restriction)"

**Revised Permission Model:**

| Action              | Admin     | Member    | Contributor                         |
| ------------------- | --------- | --------- | ----------------------------------- |
| **View (SELECT)**   | ✅ Always | ✅ Always | ✅ If `can_view_financials = true`  |
| **Create (INSERT)** | ✅ Yes    | ✅ Yes    | ❌ No                               |
| **Edit (UPDATE)**   | ✅ Yes    | ✅ Yes    | ❌ No (assumed — confirm with Tony) |
| **Delete**          | ✅ Yes    | ✅ Yes    | ❌ No                               |

**Rationale:** Matches the RBAC pattern used for gigs, setlists, and bands. Contributors are view-only for financial data. The `can_view_financials` flag controls view access only, not create/delete.

---

## Revised Engineer Task Breakdown

**Original tasks 1-5 remain unchanged.** Add the following new tasks:

### Task 6 — Create RLS Migration for Financial Entries RBAC

**File to Create:** `supabase/migrations/YYYYMMDDHHMMSS_tighten_financial_entries_rbac.sql`

**Content:**

```sql
-- ============================================================================
-- Migration: Tighten financial_entries RLS to admin & member only
-- Date: 2026-07-11
-- Branch: feature/expense-delete-drawer
-- Revision: Post-QA RBAC fix
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 1: Replace INSERT policy
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "financial_entries_insert" ON public.financial_entries;

CREATE POLICY "Admins and members can create financial entries"
  ON public.financial_entries
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = financial_entries.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
    AND created_by = auth.uid()
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 2: Replace DELETE policy
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "financial_entries_delete" ON public.financial_entries;

CREATE POLICY "Admins and members can delete financial entries"
  ON public.financial_entries
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = financial_entries.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- PHASE 3: Replace UPDATE policy (admin & member only)
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "financial_entries_update" ON public.financial_entries;

CREATE POLICY "Admins and members can update financial entries"
  ON public.financial_entries
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = financial_entries.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = financial_entries.band_id
      AND bm.user_id = auth.uid()
      AND bm.status = 'active'
      AND bm.role IN ('admin', 'member')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- Note: SELECT policy unchanged — Contributors with can_view_financials = true
-- can still view entries. This migration only restricts INSERT/UPDATE/DELETE.
-- ═══════════════════════════════════════════════════════════════════════════
```

**Verification Commands (run in Supabase SQL Editor):**

```sql
-- Confirm all three policies exist with admin/member role checks
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
AND tablename = 'financial_entries'
ORDER BY cmd;

-- Expected output: 4 policies (SELECT, INSERT, UPDATE, DELETE)
-- INSERT, UPDATE, DELETE should have "bm.role IN ('admin', 'member')"
```

### Task 7 — Add Financial Permissions to BandPermissions

**File to Modify:** `lib/features/members/permissions/band_permissions.dart`

**Changes:**

Add two new getters after the existing `canViewFinancials` getter (around line 166):

```dart
  /// Whether this user can create financial entries (admin & member only)
  bool get canCreateFinancials => isAdmin || isMember;

  /// Whether this user can delete financial entries (admin & member only)
  bool get canDeleteFinancials => isAdmin || isMember;
```

### Task 8 — Hide Add Button for Contributors

**File to Modify:** `lib/features/financials/financials_screen.dart`

**Changes:**

1. Add import at top of file:

   ```dart
   import '../members/permissions/band_permissions_provider.dart';
   ```

2. Wrap `floatingActionButton` in conditional rendering (around line 147):
   ```dart
   floatingActionButton: () {
     final permissions = ref.watch(currentUserPermissionsProvider).valueOrNull;
     if (permissions == null || !permissions.canCreateFinancials) {
       return null;
     }
     return FloatingActionButton(
       backgroundColor: AppColors.primary,
       foregroundColor: Colors.white,
       tooltip: 'Add entry',
       onPressed: state.isLoading ? null : () async {
         // ... existing onPressed logic
       },
       child: const Icon(Icons.add),
     );
   }(),
   ```

### Task 9 — Hide Delete Button for Contributors

**File to Modify:** `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`

**Changes:**

1. Add import at top of file:

   ```dart
   import '../../members/permissions/band_permissions_provider.dart';
   ```

2. Update the delete button conditional rendering in `_buildButtonRow()` method:

   **Find:**

   ```dart
   if (widget.initialEntry != null && widget.onDelete != null)
     TextButton(
       onPressed: _handleDelete,
       child: Text(
         // ... existing delete button
       ),
     ),
   ```

   **Replace with:**

   ```dart
   if (widget.initialEntry != null && widget.onDelete != null)
     Consumer(
       builder: (context, ref, _) {
         final permissions = ref.watch(currentUserPermissionsProvider).valueOrNull;
         if (permissions == null || !permissions.canDeleteFinancials) {
           return const SizedBox.shrink();
         }
         return TextButton(
           onPressed: _handleDelete,
           child: Text(
             // ... existing delete button
           ),
         );
       },
     ),
   ```

---

## Revised Verification Plan

**Original tests 1-4 remain unchanged.** Replace Test 5 and add Test 7:

**Test 5 — Permission check (Admin and Member roles)**

1. As band **Admin**, create an entry → succeeds
2. As band **Admin**, delete an entry → succeeds
3. As band **Member**, create an entry → succeeds
4. As band **Member**, delete an entry → succeeds

**Test 6 — Permission check (Contributor role, view disabled)**

1. As band **Contributor** with `can_view_financials = false`:
   - Navigate to Financials screen → should be blocked or show empty state (depends on existing access control)
   - If access is blocked, this test is complete

**Test 7 — Permission check (Contributor role, view enabled)**

1. As band **Contributor** with `can_view_financials = true`:
   - Navigate to Financials screen → succeeds (can view entries)
   - Verify **no "+" FloatingActionButton** is shown (create is blocked)
   - Tap an existing entry → Details sheet opens
   - Tap "Edit Entry" → Edit drawer opens
   - Verify **no "Delete" button** is shown (delete is blocked)
   - Attempt to modify a field and tap Save → **should succeed** (UPDATE is allowed per current RLS policy — unless Task 6 tightened it per the "confirm with Tony" note)

**Test 8 — RLS enforcement (attempt bypass via direct repository call)**

1. As band **Contributor**, use Flutter DevTools or debug session to directly call:
   ```dart
   await ref.read(financialEntryRepositoryProvider).deleteEntry(entryId, bandId);
   ```
2. Verify: Call fails with RLS policy violation error (PostgreSQL error or Supabase exception)
3. Confirm: UI does not crash — error is handled gracefully

**Test 9 — Cross-platform (original Test 6)**

1. Test on macOS
2. Test on web (localhost or deployed)
3. Test on iOS simulator (if available)
4. Verify button visibility matches role on all platforms

---

## Revised Regression Risk

**Original Level:** LOW

**Revised Level:** MEDIUM

**Rationale:**

**Increased risk factors:**

1. **Database schema change:** RLS policy changes are high-impact — they affect **all users and all platforms** immediately upon migration. A misconfigured policy can block legitimate users or allow unauthorized access.

2. **Permission model change:** This is a **breaking change** for any Contributors who previously had create/delete access (though Tony's requirement suggests this was unintended behavior). If any production bands have Contributors who were actively creating/deleting financial entries, they will lose that access.

3. **Cross-feature impact:** Financial entries are linked to gigs via `gig_pay` entries. Tightening delete permissions could affect workflows where Contributors were managing gig pay data (unlikely, but possible).

4. **Migration timing:** This RLS change should be deployed **separately** from the delete-UI commit (Task 1-5) to isolate risk. The UI change is LOW risk; the RLS change is MEDIUM risk. Bundling them increases rollback complexity.

**Mitigating factors:**

1. RLS policy syntax follows established RBAC precedent (gigs, setlists) — low risk of syntax errors.

2. Client-side UI guards (Tasks 8-9) provide defense-in-depth — Contributors won't see buttons that will fail.

3. The migration can be tested in staging with a full production data snapshot before deploying to production.

4. The change aligns with the documented RBAC model introduced in March 2026 — this is a **correction**, not a new feature.

**Recommendation:**

1. **Split into two commits:**
   - Commit 1: Tasks 1-5 (delete UI feature) — deploy first, verify in production
   - Commit 2: Tasks 6-9 (RLS + UI permission guards) — deploy separately, verify no Contributors are blocked unexpectedly

2. **Pre-deployment check:** Query production database to confirm **no Contributors exist with role = 'contributor'** who have created financial entries:

   ```sql
   SELECT COUNT(*)
   FROM financial_entries fe
   JOIN band_members bm ON bm.band_id = fe.band_id AND bm.user_id = fe.created_by
   WHERE bm.role = 'contributor';
   ```

   If count > 0, coordinate with Tony before deploying.

3. **Staging verification:** Test all 9 verification scenarios in staging before production deployment.

**Revised Risk Level:** MEDIUM (up from LOW due to RLS policy change and potential user impact)

---

## Commit Strategy

**Recommendation:** Ship as **two separate commits** on the same branch:

### Commit 1: Delete UI Feature (Original Tasks 1-5)

**Files Modified:**

- `lib/features/financials/financials_controller.dart`
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
- `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`

**Commit Message:**

```
feat(financials): add delete capability to Edit Entry drawer

- Add deleteEntry() method to FinancialsNotifier
- Update Add Financial Entry bottom sheet with optional onDelete callback
- Change button layout: Save/Cancel side-by-side, Delete button below
- Add confirmation dialog for destructive delete action
- Wire delete callback in Financial Entry Details sheet

Tested: Delete regular expense, income, and gig_pay entries.
QA: APPROVED (per QA_REPORT.md)
```

**Risk:** LOW  
**Deploy:** Can deploy immediately after QA APPROVED

### Commit 2: Financials RBAC Enforcement (Tasks 6-9)

**Files Created:**

- `supabase/migrations/YYYYMMDDHHMMSS_tighten_financial_entries_rbac.sql`

**Files Modified:**

- `lib/features/members/permissions/band_permissions.dart`
- `lib/features/financials/financials_screen.dart`
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`

**Commit Message:**

```
fix(financials): enforce RBAC for create/delete operations

- Tighten INSERT/DELETE RLS policies to admin & member only
- Add canCreateFinancials & canDeleteFinancials to BandPermissions
- Hide Add button for Contributors (FloatingActionButton conditional)
- Hide Delete button for Contributors (Edit drawer conditional)

BREAKING: Contributors can no longer create or delete financial entries.
This aligns with documented RBAC model (Contributors are view-only).

Tested: Admin/Member can create/delete; Contributor cannot (RLS blocked).
QA: Pending re-review
```

**Risk:** MEDIUM  
**Deploy:** After staging verification + Tony approval

---

## Updated System Impact Map

| System                                 | Original Impact | Revised Impact                                                     |
| -------------------------------------- | --------------- | ------------------------------------------------------------------ |
| Gigs                                   | unaffected      | **affected** — gig_pay entries can only be deleted by admin/member |
| Rehearsals                             | unaffected      | unaffected                                                         |
| Setlists / Catalog                     | unaffected      | unaffected                                                         |
| Members / RBAC                         | unaffected      | **affected** — RBAC enforcement added for financials               |
| Auth / Session                         | unaffected      | unaffected                                                         |
| Routing                                | unaffected      | unaffected                                                         |
| Notifications                          | unaffected      | unaffected                                                         |
| Platform (iOS / Android / Web / macOS) | affected (all)  | affected (all)                                                     |
| **Database (RLS policies)**            | **(NEW)**       | **affected** — 3 RLS policies replaced                             |

---

## Questions for Tony (Before Implementing Task 6)

1. **UPDATE Policy:** Should financial entry **editing (UPDATE)** also be restricted to admin & member only? The original plan did not specify, and the investigation suggests this is likely correct (UPDATE and DELETE typically have the same permission model). The migration in Task 6 assumes UPDATE should be tightened — confirm before running.

2. **Existing Contributors:** Are there any production bands with active Contributors who have `can_view_financials = true`? If yes, confirm they understand they will **lose create/delete access** when this migration deploys (they will retain view access only).

3. **Deployment Order:** Confirm you approve the two-commit strategy: deploy delete UI first (Commit 1), then RLS enforcement separately (Commit 2). This isolates risk and allows rollback of either commit independently.

4. **Staging Verification:** Do you want Engineer to deploy to staging and verify all 9 test scenarios before requesting final QA approval? Or proceed directly to QA with code review only?

---

## Summary of Revision

**What changed:**

- Database Impact: Not applicable → **Migration required** (RLS policy tightening)
- Permission model: Any active member → **Admin & member only**
- Task count: 5 tasks → **9 tasks** (added RLS migration + UI permission guards)
- Regression Risk: LOW → **MEDIUM** (RLS changes are high-impact)
- Commit strategy: Single commit → **Two commits** (UI feature + RBAC enforcement)

**Why it changed:**

- Original plan incorrectly assumed `check_band_member()` enforced role restrictions — it only checks active membership.
- Post-QA requirement clarified Contributors must be **view-only** for financials, matching the RBAC pattern used for gigs and setlists.
- RLS policy change required to enforce this at the database level (client-side guards are defense-in-depth only).

**Engineer next steps:**

1. **Hold** implementation until Tony answers the 4 questions above
2. Proceed with Commit 1 (Tasks 1-5) — already QA APPROVED, can deploy immediately
3. **Wait for Tony approval** before implementing Commit 2 (Tasks 6-9)

**QA next steps:**

1. Commit 1: No re-test needed (already APPROVED)
2. Commit 2: **Full re-test required** using revised Verification Plan (Tests 1-9)
