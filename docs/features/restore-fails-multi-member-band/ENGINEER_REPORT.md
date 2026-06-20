# Engineer Report

## Feature Slug

`bug/restore-fails-multi-member-band`

## Feature Title

Restore fails for multi-member bands — `band_members` RLS upsert failure

## Goal

Fix the multi-member band restore failure by introducing a `SECURITY DEFINER` RPC that atomically inserts band members during restore, bypassing the RLS snapshot visibility issue that prevents batch inserts from succeeding when `is_band_member()` is `STABLE`.

## Architect Tasks Completed

- [x] Task 1 — Confirm `is_band_member` function properties (required before coding)
- [x] Task 2 — Create migration: `restore_band_members` RPC
- [x] Task 3 — Update `AI_DECISIONS.md`
- [x] Task 4 — Update `data_backup_service.dart`
- [x] Task 5 — `flutter analyze` — zero errors

## Pre-condition Verification Results

### Pre-condition A: `bands.created_by` column exists

**Query:**

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'bands'
  AND column_name = 'created_by';
```

**Result:** ✓ PASS

```json
{
  "column_name": "created_by",
  "data_type": "uuid",
  "is_nullable": "YES"
}
```

**Status:** Column exists and can be used in RPC validation.

---

### Pre-condition B: Confirm `band_role_type` ENUM name

**Query:**

```sql
SELECT typname, enumlabel
FROM pg_enum
JOIN pg_type ON pg_enum.enumtypid = pg_type.oid
WHERE typname LIKE '%role%' OR typname LIKE '%band%'
ORDER BY typname, enumsortorder;
```

**Result:** ✓ PASS

```json
[
  { "typname": "band_role_type", "enumlabel": "admin" },
  { "typname": "band_role_type", "enumlabel": "member" },
  { "typname": "band_role_type", "enumlabel": "contributor" }
]
```

**Status:** ENUM type is `band_role_type` (used in migration cast).

---

### Query 1: Confirm `is_band_member` function signature, volatility, security mode

**Query:**

```sql
SELECT
  proname AS function_name,
  pg_get_function_arguments(oid) AS arguments,
  pg_get_function_result(oid) AS return_type,
  provolatile AS volatility_code,
  CASE provolatile
    WHEN 'i' THEN 'IMMUTABLE'
    WHEN 's' THEN 'STABLE'
    WHEN 'v' THEN 'VOLATILE'
  END AS volatility,
  prosecdef AS is_security_definer
FROM pg_proc
WHERE proname = 'is_band_member'
  AND pronamespace = 'public'::regnamespace;
```

**Result:** ✓ Matches Architect expectation

```json
{
  "function_name": "is_band_member",
  "arguments": "p_band_id uuid",
  "return_type": "boolean",
  "volatility_code": "s",
  "volatility": "STABLE",
  "is_security_definer": true
}
```

**Status:** Function is `STABLE SECURITY DEFINER` as expected.

---

### Query 2: Get `is_band_member` function body

**Query:**

```sql
SELECT pg_get_functiondef('public.is_band_member(uuid)'::regprocedure);
```

**Result:**

```sql
CREATE OR REPLACE FUNCTION public.is_band_member(p_band_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.band_members
    WHERE band_id = p_band_id
    AND user_id = auth.uid()
  );
$function$
```

**Key findings:**

- Function does NOT check `status = 'active'` — only checks row existence
- Uses `EXISTS` query against `band_members` table
- Has `SET search_path TO 'public'` (correct per GUARDRAILS)

---

### Query 3: Confirm `band_members` INSERT RLS policy

**Query:**

```sql
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'band_members'
  AND schemaname = 'public'
  AND cmd = 'INSERT';
```

**Result:** ✓ Matches Architect expectation

```json
{
  "policyname": "Band members can insert band members",
  "cmd": "INSERT",
  "qual": null,
  "with_check": "(is_band_member(band_id) OR (user_id = auth.uid()))"
}
```

**Status:** INSERT policy uses `is_band_member(band_id)` as expected, confirming the root cause (STABLE function evaluates at statement start, preventing batch inserts).

---

### Query 4: Check `band_members` constraints and indexes

**Constraints Query:**

```sql
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.band_members'::regclass;
```

**Constraints Result:**

- `band_members_pkey`: PRIMARY KEY (id)
- `band_members_band_id_user_id_key`: UNIQUE (band_id, user_id)
- `band_members_band_user_unique`: UNIQUE (band_id, user_id) [duplicate]
- `band_members_status_check`: CHECK (status IN ('invited', 'active', 'inactive', 'removed'))
- `band_members_band_id_fkey`: FOREIGN KEY (band_id) → bands(id) ON DELETE CASCADE
- `band_members_user_id_fkey`: FOREIGN KEY (user_id) → auth.users(id) ON DELETE CASCADE

**Indexes Query:**

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'band_members' AND schemaname = 'public';
```

**Indexes Result:**

- `band_members_pkey`: UNIQUE INDEX on (id)
- `band_members_band_id_user_id_key`: UNIQUE INDEX on (band_id, user_id)
- `band_members_band_user_unique`: UNIQUE INDEX on (band_id, user_id) [duplicate]
- `idx_band_members_band_user`: INDEX on (band_id, user_id)
- `idx_band_members_band_id`: INDEX on (band_id)
- `idx_band_members_user_id`: INDEX on (user_id)

**Status:** UNIQUE constraint on (band_id, user_id) confirmed. All constraints and indexes as expected.

---

## Files Created

- `supabase/migrations/20260621000002_restore_band_members_rpc.sql` — New `SECURITY DEFINER` RPC for atomic member restore

## Files Modified

- `lib/features/settings/data_backup_service.dart` — Replaced `_upsertRows('band_members', remappedMembers)` with RPC call at line 444
- `docs/reference/general/AI_DECISIONS.md` — Added DECISION-003 entry for the new SECURITY DEFINER function

## Implementation Details

### Migration: `20260621000002_restore_band_members_rpc.sql`

Created new RPC function `public.restore_band_members(p_band_id uuid, p_members jsonb)`:

**Security validations:**

1. Caller must be the creator: `bands.created_by = auth.uid()`
2. Caller must be active admin: `band_members` row with `role = 'admin'` AND `status = 'active'`

**Functionality:**

- Accepts JSONB array of member rows
- Atomically inserts/updates all members using `INSERT ... ON CONFLICT (id) DO UPDATE`
- Uses `SECURITY DEFINER` to bypass RLS
- Includes `SET search_path = public` per GUARDRAILS
- Granted to `authenticated` role

**Transaction semantics:**

- All inserts succeed or transaction rolls back (no partial restore)
- Automatic rollback on any constraint violation or permission error

### Dart Code: `data_backup_service.dart`

**Change location:** Line 444 (inside `bandExists == false` block)

**Before:**

```dart
// 2. Band members (filtered, remapped)
await _upsertRows('band_members', remappedMembers);
```

**After:**

```dart
// 2. Band members (filtered, remapped) — use RPC for atomic restore
if (remappedMembers.isNotEmpty) {
  await supabase.rpc(
    'restore_band_members',
    params: {
      'p_band_id': newBandId,
      'p_members': remappedMembers,
    },
  );
}
```

**Behavior:**

- Empty check prevents unnecessary RPC call for single-member (admin-only) backups
- Error propagation unchanged: `PostgrestException` caught by existing handler
- Existing-band path (`bandExists == true`) unchanged — direct upsert continues to work

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors, 0 warnings

**Output:**

```
Analyzing bandroadie...
No issues found! (ran in 3.8s)
```

## Test Results

Not run (per Architect plan — no automated tests exist for restore flow).

## Verification

### Manual steps performed:

1. ✓ Verified migration file created with correct timestamp (`20260621000002`)
2. ✓ Verified RPC function includes both security checks (creator + admin)
3. ✓ Verified `SET search_path = public` present (GUARDRAILS compliance)
4. ✓ Verified GRANT to `authenticated` role
5. ✓ Verified Dart code change matches Architect specification exactly
6. ✓ Verified AI_DECISIONS.md entry follows existing format
7. ✓ Verified no other files modified beyond Architect scope
8. ✓ Verified `flutter analyze` passes with zero errors

### Database queries confirmed:

1. ✓ `bands.created_by` exists (type uuid)
2. ✓ ENUM type is `band_role_type` (admin, member, contributor)
3. ✓ `is_band_member` is `STABLE SECURITY DEFINER` (confirms root cause)
4. ✓ INSERT RLS policy uses `is_band_member(band_id)` (confirms failure mode)
5. ✓ UNIQUE constraint on (band_id, user_id) exists

## Deviations From Architect Plan

None. All tasks completed exactly as specified.

## Blockers Encountered

None. All pre-conditions met:

- `bands.created_by` column exists
- ENUM type confirmed as `band_role_type`
- Database schema matches Architect expectations
- No unlisted files required modification

## Ready For QA

**No** — Migration must be deployed to production first.

**Deployment sequence:**

1. Run `supabase db push --linked` to deploy migration to production
2. Verify post-deploy tests from Architect plan (Tier 2 verification)
3. Deploy Flutter app (web: `./tools/deploy_web.sh`, mobile: standard release)
4. QA can then test multi-member restore scenarios

**QA test cases** (from Architect plan):

- Primary: Restore multi-member band after deletion (new band path)
- Regression: Single-member restore (admin only)
- Regression: Restore when source band still exists (existing-band path)
- Security: Unauthorized restore attempt
- Error handling: RPC error surfaces correctly

## Notes

### Root cause confirmation

Database queries confirmed the Architect's root cause analysis:

- `is_band_member()` is `STABLE SECURITY DEFINER`
- INSERT RLS policy: `(is_band_member(band_id) OR (user_id = auth.uid()))`
- During batch INSERT, `STABLE` function evaluates at statement start
- For member2's row: `user_id = member2_user_id ≠ auth.uid()` → FALSE
- `is_band_member(newBandId)` checks if admin exists, but `STABLE` may not see the row inserted by `create_band` in the prior statement

The RPC fix bypasses this entirely by using `SECURITY DEFINER` with explicit validation.

### Status field handling

Important discovery: `is_band_member()` does NOT check `status = 'active'` — it only verifies row existence. The RPC's second validation (`status = 'active'`) is more restrictive than the helper function. This is intentional defense in depth.

### Duplicate constraints

Two UNIQUE constraints exist on `(band_id, user_id)`:

- `band_members_band_id_user_id_key`
- `band_members_band_user_unique`

This is harmless but suggests historical schema evolution. Not addressed in this fix (out of scope).
