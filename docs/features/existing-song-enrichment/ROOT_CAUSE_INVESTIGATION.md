# Root Cause Investigation Report

## Bug Summary
Migration `20260801000000` deployed to production but **POST-DEPLOY TEST 3 fails**: `musical_key` remains NULL after calling `update_song_metadata(p_musical_key => 'Dm')` on a song where `musical_key` was initially NULL.

## Rollback Status
✅ **Task 1 Complete**: Rollback migration `20260801000001_rollback_musical_key_duration_overwrite.sql` committed to `main` branch (NOT YET PUSHED - awaiting Tony approval).

## Debugging Progress

### What QA Already Ruled Out
- ✅ RPC overload ambiguity: Only one `update_song_metadata` signature exists
- ✅ Authentication/permission failures: RPC returns `success: true`
- ✅ Obvious triggers: No interfering triggers found on `songs` table via `pg_trigger`

### New Findings from Engineer Investigation

#### 1. Broken vs. Working Logic Comparison

**Old (working) logic from migration `20260703034302`:**
```sql
musical_key = CASE
  WHEN p_musical_key = '' THEN NULL
  WHEN p_musical_key IS NOT NULL THEN p_musical_key  -- Always overwrites if param not null
  ELSE musical_key
END
```

**New (broken) logic from migration `20260801000000`:**
```sql
musical_key = CASE 
  WHEN p_musical_key IS NOT NULL AND musical_key IS NULL THEN p_musical_key  -- Only fill if currently NULL
  ELSE musical_key 
END
```

#### 2. CASE Logic Works Outside Function Context

**Test Result**: Created `/tmp/simple_update_test.sql` with three test scenarios:
1. Simple assignment: `SET musical_key = 'Dm'` ✅ **PASSED**
2. CASE with hardcoded condition: `SET musical_key = CASE WHEN TRUE AND musical_key IS NULL THEN 'Dm' ELSE musical_key END` ✅ **PASSED**
3. Exact broken RPC logic: `SET musical_key = CASE WHEN 'Dm' IS NOT NULL AND musical_key IS NULL THEN 'Dm' ELSE musical_key END` ✅ **PASSED**

**Conclusion**: The CASE expression itself is syntactically correct and works in bare UPDATE statements. The bug is specific to `SECURITY DEFINER` function execution context.

#### 3. RLS Policy Analysis

**Found UPDATE policy** `authenticated_members_can_update_songs`:
- **USING clause**: `is_band_member(band_id)`  (checks OLD row - determines which rows can be updated)
- **WITH CHECK clause**: `is_band_member(band_id)` (checks NEW row - validates updated values)

**Hypothesis**: The WITH CHECK clause evaluates the NEW row's `band_id` after the UPDATE. However, `is_band_member(band_id)` should pass for both OLD and NEW rows since `band_id` doesn't change.

**Status**: WITH CHECK clause is NOT the root cause - bare UPDATE tests with the same CASE logic passed, meaning RLS allows the update.

#### 4. Constraint Triggers

**Query**: Checked `pg_trigger` for constraint triggers (deferred, INSTEAD OF, etc.)
**Result**: No interfering constraint triggers found beyond standard FK triggers.

####5. Test Data Integrity Issue Discovered

**CRITICAL**: The hardcoded test user ID in `sql/tests/pre_deploy_tests.sql` and `sql/tests/post_deploy_tests.sql`:
- UUID: `55d1f57a-9558-4363-a980-5ece88068979`
- Email: `mspitzer75@yahoo.com`
- **DOES NOT EXIST IN PRODUCTION** (verified via `SELECT FROM users WHERE id = ...` returned empty)

**Impact**: SQL tests cannot run without a valid test user. Tests were created with invented UUID, not a real production user.

## Outstanding Debugging Steps

### Not Yet Attempted
1. **GET DIAGNOSTICS v_update_count** inside actual `update_song_metadata` RPC to verify UPDATE executes
2. **Postgres server logs** to see RAISE INFO/NOTICE output (Supabase CLI doesn't display these)
3. **Column reference evaluation timing**: In `CASE WHEN p_musical_key IS NOT NULL AND musical_key IS NULL`, does `musical_key` reference OLD or NEW value during SET clause evaluation?
4. **Savepoint/exception handling**: Check if there's implicit transaction rollback or exception swallowing
5. **Row visibility under SECURITY DEFINER**: Does the function's execution role see different row states?

### Recommended Next Steps

**Hypothesis to Test**: In the broken CASE logic, when evaluating `musical_key IS NULL` within the SET clause, PostgreSQL might be checking against an intermediate state or the NEW value being assigned, not the OLD value.

**Test Plan**:
```sql
-- Add explicit debug SELECT before UPDATE in actual RPC
DECLARE v_old_key_before_update TEXT;
SELECT musical_key INTO v_old_key_before_update FROM songs WHERE id = p_song_id;
RAISE NOTICE 'DEBUG: Old key before UPDATE: %', COALESCE(v_old_key_before_update, '<NULL>');

-- Then run UPDATE
UPDATE songs SET musical_key = CASE ... WHERE id = p_song_id;
GET DIAGNOSTICS v_row_count = ROW_COUNT;
RAISE NOTICE 'DEBUG: Rows updated: %', v_row_count;

-- Check after
SELECT musical_key INTO v_new_key_after_update FROM songs WHERE id = p_song_id;
RAISE NOTICE 'DEBUG: New key after UPDATE: %', COALESCE(v_new_key_after_update, '<NULL>');
```

**Alternative Fix**: Rewrite to use explicit variable storage:
```sql
DECLARE v_current_key TEXT;
SELECT musical_key INTO v_current_key FROM songs WHERE id = p_song_id;

UPDATE songs
SET musical_key = CASE 
  WHEN p_musical_key IS NOT NULL AND v_current_key IS NULL THEN p_musical_key
  ELSE v_current_key
END
WHERE id = p_song_id;
```

This eliminates ambiguity about which `musical_key` value is being checked.

## Files Modified This Session

### On `main` branch (committed, not pushed):
- ✅ `supabase/migrations/20260801000001_rollback_musical_key_duration_overwrite.sql` (NEW)
  - Commit message: "fix(db): rollback broken musical_key non-overwrite logic"

### On `feature/existing-song-enrichment` branch:
- Still has broken migration `20260801000000`
- All feature code changes unchanged

## Status

🔴 **BLOCKED**: Cannot fully root-cause without access to Postgres server logs or ability to see RAISE INFO output.

🟡 **PARTIAL SUCCESS**: 
- Confirmed CASE logic works outside function (not a SQL syntax bug)
- Confirmed RLS policies and triggers are not blocking the UPDATE
- Identified test data integrity issue

🟢 **READY FOR TONY**:
- Rollback migration committed on `main`, ready to push after approval
- Comprehensive investigation notes documented

## Recommendations

1. **Immediate**: Push rollback migration `20260801000001` to restore production
2. **Short-term**: Fix test data - replace invented UUID with real production admin user
3. **Medium-term**: Try alternative implementation (explicit variable storage) to avoid CASE ambiguity
4. **Long-term**: Add Postgres log monitoring to CI/CD for future RPC debugging
