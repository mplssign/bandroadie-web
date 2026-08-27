# Feature Slug

bug/song-duration-edit-silently-fails

---

# Problem Summary

Band members can edit a song duration in the Song Details UI, but when the current `duration_seconds` is already non-zero, the save appears to succeed while the database value remains unchanged. In the reported case, a value of `0:58` is edited to `4:17` and then reopens with `0:58` unchanged. This breaks duration totals, set-planning accuracy, and the user’s ability to correct a wrong inherited or imported value.

This is a shared client/server path and is not limited to Android: the `SetlistRepository.updateSongDurationOverride()` method calls the same `update_song_metadata` RPC used across platforms.

---

# Root Cause

Root cause confirmed in current code: the live `update_song_metadata` RPC in `supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql` only writes `duration_seconds` when the current value is `0`. The update is guarded by:

```sql
duration_seconds = CASE
  WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0
    THEN p_duration_seconds
  ELSE duration_seconds
END
```

The verification logic has the same eligibility gate:

```sql
IF p_duration_seconds IS NOT NULL THEN
  IF v_before_duration = 0 THEN
    IF v_new_duration IS DISTINCT FROM p_duration_seconds THEN
      RETURN json_build_object('success', false, 'error', ...);
    END IF;
  END IF;
END IF;
```

When the existing value is already non-zero, the `UPDATE` is a no-op, `ROW_COUNT` is still `1` for the matched row, and the function returns `{"success": true}` even though the field was never changed. This is a false success caused by a fill-missing-only write strategy for duration. Confidence: HIGH.

This does not mean the whole `update_song_metadata` RPC is broken for all fields; the same file and the related architecture docs show `tuning` intentionally uses `COALESCE` (always-overwrite) while `bpm` and `musical_key` are also known fill-missing-only fields with the same false-success class. This bug is being scoped to `duration_seconds` only because the feature request is specifically the duration overwrite bug and the plan must not silently widen scope to fix `bpm`/`musical_key` without an explicit escalation.

---

# Reference Docs Consulted

- `supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql` — current live RPC definition and verification logic
- `lib/features/setlists/setlist_repository.dart` — `updateSongDurationOverride()` call path and RPC params
- `lib/features/setlists/setlist_detail_controller.dart` — controller method that invokes the repository update
- `docs/features/song-original-vs-performance-values/ARCHITECT_PLAN.md` — confirms the known asymmetry pattern and the write-once limitation on `bpm`/`musical_key`
- `docs/features/song-metadata-revert-dual-value/ARCHITECT_PLAN.md` — confirms the revert migration restored single-value semantics and notes the same false-success gap on non-zero duration

No notification-domain reference docs were relevant to this feature; this is a setlist/song metadata persistence bug, not a notification bug.

---

# Existing System Analysis

Current call flow is:

1. `SongDetailsBottomSheet` accepts a new duration value and calls the save handler when the user saves.
2. `SetlistDetailController._handleDurationSave()` (or equivalent save path) invokes `SetlistRepository.updateSongDurationOverride()`.
3. The repository calls `supabase.rpc('update_song_metadata', params: {... 'p_duration_seconds': durationSeconds, ...})`.
4. The RPC runs `UPDATE songs SET duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END`.
5. Because existing durations greater than `0` are excluded from the CASE, the row is matched but not changed.
6. The function checks `v_before_duration = 0` and therefore skips the `success: false` verification branch when the old value is non-zero.
7. The function still returns `{"success": true}` and the client treats the update as successful.
8. The UI appears to accept the change, but a reload fetches the original duration value from `songs.duration_seconds` and the user sees the old value again.

This is a write-path bug in the Supabase database function, not a display-only issue. The read path is not the source of the revert; the database write is silently ignored before it reaches the client.

Platform impact: the save path is shared and cross-platform. The bug should be treated as cross-platform unless a platform-specific client-side branch is shown to intercept or transform the value before it reaches the RPC. In current code, there is no such branch, so no Android-only scope is justified.

---

# Proposed Solution

Implement a minimal database fix for `duration_seconds` in the `update_song_metadata` RPC, without changing the existing API signature or broadening the behavior of `bpm`/`musical_key` in the same patch.

Design:

- Keep the RPC signature unchanged.
- Update the `duration_seconds` assignment to allow a provided value to overwrite the current value whenever `p_duration_seconds IS NOT NULL`.
- Preserve the existing behavior for other fields exactly as they are today.
- Keep the verification logic consistent with the actual write semantics: if the caller explicitly passes a non-null `p_duration_seconds`, then `v_new_duration` must match `p_duration_seconds` unless the update is intentionally blocked by a different constraint.
- If the update remains a no-op because of a different database constraint, return `success: false` with an explicit error, not `success: true`.

This is the smallest fix that resolves the reported bug while respecting the scope note in the feature input. It does not attempt to convert `bpm` and `musical_key` to always-overwrite semantics in the same migration. The related issue is real, but it is not this bug and should be tracked as a separate follow-up unless the Manager explicitly broadens scope.

---

# Database Impact

- Migration required: yes
- RLS impact: no new policies; existing `SECURITY DEFINER` function remains in place and required for legacy NULL `band_id` songs
- RPC signature impact: no change; keep same 11 parameters to avoid client breakage and PostgREST overload ambiguity
- Trigger impact: none
- Table impact: modify only the SQL logic inside `update_song_metadata` function; no schema change to `songs`
- Existing behavior for `bpm`, `musical_key`, and `tuning`: unchanged in this patch; duration gets corrected while the known broader write-once behavior on BPM/key remains out of scope for this fix

This is a backend function logic change only.

---

# Flutter Architecture Changes

- No new Flutter architecture layer is required.
- No provider, controller, or repository abstraction change is needed unless the Engineer decides to add explicit error surfacing in the UI. That is not required for the root fix because the existing call chain already passes the value correctly; the silent failure is server-side.
- The current repository method and controller flow are already correct in calling the shared RPC with the updated duration value.
- This plan does not require changes to `song_details_bottom_sheet.dart`, `setlist_detail_controller.dart`, or the persistence model unless the UI should surface a stronger error message in a later task.

---

# Files to Create

none

---

# Files to Modify

| File                                                                  | What changes                                                                                                                                                                                                                                      |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260827120000_fix_song_duration_write_once.sql` | Replace the current `update_song_metadata` duration assignment and verification logic so a non-null duration override persists even when the existing value is already non-zero. Keep the function signature and other field semantics unchanged. |
| `docs/features/song-duration-edit-silently-fails/ARCHITECT_PLAN.md`   | This plan document.                                                                                                                                                                                                                               |

If the implementation also decides to add explicit client-side error messaging for a failed RPC response, that would be a separate, optional UI follow-up and is not required for the underlying bug fix.

---

# Files Off-Limits

| File                                                                              | Reason                                                                                                                                               |
| --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_controller.dart`                            | The save path already reaches the repository correctly; the bug is not in controller logic.                                                          |
| `lib/features/setlists/setlist_repository.dart`                                   | The repository already passes the correct `p_duration_seconds`; fixing the backend semantics is the minimal root-cause solution.                     |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`                    | UI is not the source of the silent no-op; the user-visible data is not being persisted by the database function.                                     |
| `lib/main.dart`                                                                   | Initialization order must not change.                                                                                                                |
| `supabase/migrations/20260811120001_revert_update_song_metadata_single_value.sql` | This live migration is the current prod definition; do not edit it in place. Create a new migration that replaces the function with corrected logic. |

---

# System Impact Map

| System                                 | Impact                                                                              |
| -------------------------------------- | ----------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                          |
| Rehearsals                             | unaffected                                                                          |
| Setlists / Catalog                     | affected                                                                            |
| Members / RBAC                         | unaffected                                                                          |
| Auth / Session                         | unaffected                                                                          |
| Routing                                | unaffected                                                                          |
| Notifications                          | unaffected                                                                          |
| Platform (iOS / Android / Web / macOS) | affected (shared RPC path, cross-platform; no platform-specific branching observed) |

---

# Regression Risk

Risk level: MEDIUM

Reasoning:

- The fix affects a shared `update_song_metadata` RPC used by setlists and catalog metadata writes.
- The change is limited to `duration_seconds` and does not alter other fields in this patch.
- The function remains `SECURITY DEFINER` and retains the same signature, so the risk of cross-feature breakage is lower than a broader metadata redesign.
- The known broader `bpm`/`musical_key` write-once behavior remains out of scope, which reduces the chance of an unintended side effect on unrelated fields.

---

# Engineer Task Breakdown

1. Add a migration that recreates `update_song_metadata` with corrected `duration_seconds` semantics while preserving the current signature and field behavior for all other columns.
2. Ensure the SQL verification logic matches the actual write semantics: when `p_duration_seconds` is non-null, a successful update must change or validate the stored duration accordingly rather than silently returning `success: true` on a no-op.
3. Keep the function ACL and security model intact; do not broaden to new RLS rules or client auth changes.
4. Run the required pre-deploy and post-deploy SQL verification checks to confirm the fix works and no bad data is written.
5. Document the broader `bpm`/`musical_key` false-success limitation as a separate issue in the release notes or follow-up ticket, not as part of this scope unless the Manager explicitly approves it.

---

# Verification Plan

## Tier 1 — Pre-deployment (must pass before `supabase db push`)

- Test only functions and objects that already exist in the database unchanged.
- Do not call the function being replaced before migration.

```sql
-- PRE-DEPLOY TEST 1:
SELECT pg_get_functiondef('update_song_metadata'::regproc)
LIKE '%duration_seconds = CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0%'
AS current_duration_fill_only_behavior_detected;
```

```sql
-- PRE-DEPLOY TEST 2:
DO $$
DECLARE
  v_before_duration INTEGER := 97;
  v_candidate INTEGER := 257;
  v_after_duration INTEGER;
BEGIN
  v_after_duration := CASE
    WHEN v_candidate IS NOT NULL AND v_before_duration = 0 THEN v_candidate
    ELSE v_before_duration
  END;

  IF v_after_duration != v_before_duration THEN
    RAISE EXCEPTION 'Current pre-deploy behavior would be expected to overwrite only when zero; this test should detect the regression path for a non-zero value.';
  END IF;
END $$;
```

These two tests verify the current behavior in place and document the exact gap without invoking the function that will be replaced.

## Tier 2 — Post-deployment (run after `supabase db push` succeeds)

The only automated SQL gate in Tier 2 is the function-body check below. It is valid because it confirms the deployed `update_song_metadata` function actually contains the corrected `duration_seconds` logic; paired with PRE-DEPLOY TEST 1, this is a legitimate before/after check for the migration itself. No SQL-only mutation test is a substitute for end-to-end validation of the RPC auth + membership + write path.

```sql
-- POST-DEPLOY TEST 1:
SELECT pg_get_functiondef('update_song_metadata'::regproc)
LIKE '%duration_seconds = COALESCE(p_duration_seconds, duration_seconds)%'
OR pg_get_functiondef('update_song_metadata'::regproc)
LIKE '%WHEN p_duration_seconds IS NOT NULL THEN p_duration_seconds%'
AS duration_override_logic_present;
```

Required manual QA gate (must be completed by an authenticated app user; no SQL-only replacement):

1. Use a real test/dev band and pick or create a song with a non-zero duration.
2. Sign in as an authenticated band member in the app.
3. Open the Song Details UI for that song, edit the duration to a different non-zero value, and tap Save.
4. Force-reload the app or navigate away and back to the same song.
5. Confirm the new duration persists in the UI and remains visible after reload.

This is the only validation that exercises the RPC's auth guard, band-membership check, and database write together. No database-only query can substitute for it.

---

# QA Regression Areas

- Duration edit from a non-zero value to a corrected non-zero value should persist and survive refresh.
- Duration edit from zero to a valid non-zero value should continue to work as expected.
- Save is not allowed to silently succeed when the database write did not happen.
- Required manual authenticated app check: in a real test/dev band, open a song with a non-zero duration, edit it through the Song Details UI as an authenticated band member, save, force-reload the screen, and confirm the new value persists. This is the only step that validates the RPC's auth guard + membership check + write in the same flow.
- Cross-platform client behavior should be confirmed because the RPC is shared; Android is the confirmed reproducer but the same call path is used elsewhere.
- The broader `bpm`/`musical_key` write-once limitation remains out-of-scope for this fix and should not be conflated with the duration regression.

---

# Rollout / Migration Strategy

This is a backend-only function fix with a new migration. The safest deployment pattern is:

1. Deploy the migration that redefines `update_song_metadata` with corrected `duration_seconds` behavior while preserving the same signature.
2. Confirm the function definition and migration checks pass.
3. Validate at least one real user scenario in staging or a controlled environment using a test song with a non-zero duration.
4. Release to production after the DB migration passes the verification checks.

Because the function signature remains stable, clients do not require a coordinated front-end release. The logic change is source-compatible with the existing call site.

---

# Out of Scope

- Fixing the known `bpm`/`musical_key` fill-missing-only false-success issue in the same migration.
- Redesigning the song metadata model around dual values or source/performance values.
- Changing the repository or UI save flow beyond optional error surfacing.
- Any new RLS policy, auth flow change, or platform-specific branch.
- Any refactor unrelated to root-cause correction.

---

# Final Note

The evidence already in the codebase supports a single root cause: the shared `update_song_metadata` RPC silently refuses to overwrite non-zero durations. The minimal safe fix is to correct that SQL logic, not to rewrite the save path or broaden the patch to unrelated metadata fields.
