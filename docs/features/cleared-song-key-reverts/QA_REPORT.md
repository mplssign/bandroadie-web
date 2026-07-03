# QA Report

## Feature Slug

`bug/cleared-song-key-reverts`

## Feature Title

Fix: Song musical key clears do not persist to database

## Final Verdict

**APPROVED**

## Manual Verification Results

**Migration Deployment:**
- Migration `20260703034302_fix_musical_key_clear_in_update_song_rpc.sql` deployed to production via `supabase db push`

**Manual Device Testing:**
- **Date:** 2026-07-03
- **Device:** Physical iPhone (iOS)
- **Tester:** Tony Holmes

**Test Results:**
- ✓ Cleared keys persist across wait/refresh/navigation
- ✓ Key segment displays "—" after clearing key
- ✓ Re-setting a key after clear works correctly
- ✓ No spurious saves detected
- ✓ Other metadata fields unaffected

**Verdict:** PASSED

## Validation Summary

Verified implementation against Architect plan plus two Manager-approved scope amendments via code-path analysis and git diff inspection. All three Architect tasks completed correctly: (1) migration file creates RPC with empty-string-to-NULL conversion, (2) bottom sheet flows empty string through instead of converting to null, (3) defensive conversion removed. The two Manager-approved amendments (display empty string as "—" and normalize null/empty-string in change detection) are correctly implemented in the already-approved file. Migration comparison confirms only the expected functional changes (musical_key CASE logic, DROP signature, COMMENT). Code path traced from picker → sheet → controller → repository → RPC. No-op path verified (opening details without key edit triggers no save). Optimistic update correctly clears badge via isEmpty check. Flutter analyze shows 0 errors in project code (13,079 issues are all in external Firebase dependencies). No secrets, debug artifacts, or out-of-scope changes found.

## Architect Scope Review

- **Scope adherence:** Compliant
- **Files modified:** As expected (1 Flutter file + 1 migration)
  - `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — Listed in plan's "Files to Modify" ✓
  - `supabase/migrations/20260703034302_fix_musical_key_clear_in_update_song_rpc.sql` — Listed in plan's "Files to Create" ✓
- **Files off-limits:** Not touched
  - All 8 files in plan's "Files Off-Limits" table remain unmodified ✓

### Manager-Approved Scope Amendments

Two additional changes were made beyond the three Architect tasks, both approved by Manager as required amendments:

1. **Amendment 1 (line ~1019):** Display logic updated to render empty string as "—" placeholder
   - Justification: Empty-string-sentinel requires UI to treat empty string as "unset"
   - File: `song_details_bottom_sheet.dart` (already approved in plan)
   - No architectural change

2. **Amendment 2 (line ~304):** Change detection updated to normalize null and empty string as equivalent
   - Justification: Prevents spurious saves when original=null and current=empty-string (semantic no-op)
   - File: `song_details_bottom_sheet.dart` (already approved in plan)
   - No architectural change

Both amendments are localized fixes in the already-approved file and do not add new files, change the architecture, or modify off-limits files.

## Completeness Check

- **All Architect tasks implemented:** Yes
- **Missing tasks:** None

### Task Verification

**Task 1 (Create migration file):** ✓ Confirmed in code

- File: `supabase/migrations/20260703034302_fix_musical_key_clear_in_update_song_rpc.sql`
- Migration drops 11-parameter signature and recreates with updated musical_key CASE logic
- Timestamp format correct (YYYYMMDDHHMMSS in UTC)

**Task 2 (Modify \_selectKey()):** ✓ Confirmed in code

- Location: `song_details_bottom_sheet.dart:428`
- Change: `_currentMusicalKey = null;` → `_currentMusicalKey = '';`
- Empty string now flows through to repository

**Task 3 (Remove defensive conversion):** ✓ Confirmed in code

- Location: `song_details_bottom_sheet.dart:473-479` (removed block)
- Lines 473-479 deleted: the `musicalKeyToSave` variable that converted empty string to null
- Line 486: Now uses `_currentMusicalKey` directly instead of `musicalKeyToSave`

## Behavior Verification

- **Validation method:** Code-path analysis only (runtime testing requires deployment)
- **Result:** Matches expected behavior per plan

### Clear Path (Empty String Sentinel Flow)

Traced complete path from picker to database:

1. **Picker returns `''`** — `key_picker_bottom_sheet.dart:171`

   ```dart
   onTap: () => Navigator.of(context).pop(isSelected ? '' : key)
   ```

   Confirmed: Returns empty string when tapping selected key to unselect ✓

2. **Sheet keeps `''`** — `song_details_bottom_sheet.dart:428`

   ```dart
   setState(() { _currentMusicalKey = ''; });
   ```

   Confirmed: No longer converts to null ✓

3. **Save result carries `''`** — `song_details_bottom_sheet.dart:486`

   ```dart
   musicalKey: musicalKeyChanged ? _currentMusicalKey : null,
   ```

   Confirmed: When changed, passes `_currentMusicalKey` which is `''` ✓

4. **Controller passes `''` to repository** — `setlist_detail_controller.dart:1326`

   ```dart
   musicalKey: musicalKey,
   ```

   Confirmed: Passes parameter unchanged ✓

5. **Repository passes `''` to RPC** — `setlist_repository.dart:2197`

   ```dart
   'p_musical_key': musicalKey,
   ```

   Confirmed: Passes to RPC as-is ✓

6. **RPC converts `''` to NULL** — Migration file line 61-65
   ```sql
   musical_key = CASE
     WHEN p_musical_key = '' THEN NULL
     WHEN p_musical_key IS NOT NULL THEN p_musical_key
     ELSE musical_key
   END
   ```
   Confirmed: Empty string explicitly converted to NULL before UPDATE ✓

### No-Op Path (No Spurious Saves)

Verified change detection prevents unnecessary saves when no actual change occurred:

**Initialization:** `song_details_bottom_sheet.dart:233-234`

```dart
_originalMusicalKey = widget.song.musicalKey;  // null or ''
_currentMusicalKey = widget.song.musicalKey;   // null or ''
```

**Change Detection:** `song_details_bottom_sheet.dart:304-305`

```dart
final musicalKeyChanged = (_currentMusicalKey ?? '') != (_originalMusicalKey ?? '');
```

**Test Cases:**

- Original `null`, current `null` → `('' != '')` → `false` (no change) ✓
- Original `''`, current `''` → `('' != '')` → `false` (no change) ✓
- Original `null`, current `''` → `('' != '')` → `false` (no change) ✓ — **This is the key no-op case**
- Original `"C#"`, current `''` → `('' != "C#")` → `true` (change detected) ✓
- Original `null`, current `"Dm"` → `("Dm" != '')` → `true` (change detected) ✓

Confirmed: Null and empty string are normalized as equivalent "no key" states ✓

### Optimistic Update Path

Verified badge hides immediately on clear:

**Controller optimistic update:** `setlist_detail_controller.dart:1315`

```dart
clearMusicalKey: musicalKey == null || musicalKey.isEmpty,
```

Confirmed: Both null and empty string trigger clearMusicalKey flag ✓

**Badge display logic:** `song_card.dart:236-237` and `reorderable_song_card.dart` (similar)

```dart
if (widget.song.musicalKey != null && widget.song.musicalKey!.isNotEmpty)
  _buildKeyBadge(),
```

Confirmed: Badge shown only when musicalKey is non-null AND non-empty. Empty string correctly hides badge ✓

### Display Logic Amendment Verification

**Key segment placeholder:** `song_details_bottom_sheet.dart:1019-1021`

```dart
value: (_currentMusicalKey == null || _currentMusicalKey!.isEmpty)
    ? '—'
    : _currentMusicalKey!,
```

Confirmed: Both null and empty string render as "—" placeholder ✓

## Regression Check

- **Risk level:** LOW
- **Systems reviewed:** Setlists/Catalog (affected), all others per System Impact Map (unaffected)
- **Regressions found:** None

### Risk Assessment

**Surface area:** Minimal and localized

- One RPC function modified (update_song_metadata)
- One UI widget modified (song_details_bottom_sheet)
- One sentinel value introduced (empty string for clearing)
- No changes to: auth, session, routing, init order, other metadata fields, shared state, providers

**Blast radius:** Single field in single feature

- Only affects song musical_key clearing
- Other metadata fields (BPM, duration, tuning, notes, title, artist, youtube_links, lyrics) unchanged
- Badge display logic already handles empty string correctly (no visual regression)
- No cross-feature dependencies

**Guardrail compliance:**

- No initialization order changes (Guardrail #1) ✓
- No config changes (Guardrail #2) ✓
- No platform-specific behavior changes (Guardrail #3) ✓
- No RLS policy self-references (Guardrail #4, see Database Safety) ✓
- No async lifecycle violations (Guardrail #5) — no new async gaps introduced ✓
- No data integrity violations (Guardrail #6) — atomic write via RPC ✓
- Minimal code change (Guardrail #7) — 3 changes + 2 amendments in 1 file ✓
- Unidirectional data flow preserved (Guardrail #9) ✓
- Git discipline compliant (Guardrail #10) — feature branch, no push yet ✓

## Database Safety

**Status:** Verified via migration comparison

### Migration File Comparison

Compared new migration (`20260703034302`) against original (`20260630000001`):

**Preserved (unchanged):**

- SECURITY DEFINER: Present in both ✓
- SET search_path = public: Present in both ✓
- GRANT statement: Identical 11-parameter signature in both ✓
- All other field update logic: Identical (bpm, duration_seconds, tuning, notes, title, artist, youtube_links, lyrics) ✓
- Function signature: Identical 11 parameters ✓
- Security checks: Identical (auth check, band membership check, song ownership check) ✓

**Changed (expected per plan):**

1. DROP signature: 10-parameter → 11-parameter (correct — original migration added 11th param)
2. musical_key CASE logic: Added `WHEN p_musical_key = '' THEN NULL` clause before existing conditions ✓
3. COMMENT: Added "Pass empty string for p_musical_key to clear." after "including musical key." ✓

### RLS Policy Self-Reference Check

Migration only modifies a function, does not touch RLS policies. No risk of table self-reference (Guardrail #4). ✓

### Privilege Escalation Check

SECURITY DEFINER status preserved for legitimate reason: bypass RLS for legacy songs with NULL band_id. No new privileges granted. ✓

### Signature Match Verification

Repository call: `setlist_repository.dart:2184-2199`

```dart
await supabase.rpc('update_song_metadata', params: {
  'p_song_id': songId,
  'p_band_id': bandId,
  'p_bpm': null,
  'p_duration_seconds': null,
  'p_tuning': null,
  'p_notes': null,
  'p_title': null,
  'p_artist': null,
  'p_youtube_links': null,
  'p_lyrics': null,
  'p_musical_key': musicalKey,  // Can now be '', null, or key string
});
```

RPC signature: Migration file line 4-16

- 11 parameters: p_song_id, p_band_id, p_bpm, p_duration_seconds, p_tuning, p_notes, p_title, p_artist, p_youtube_links, p_lyrics, p_musical_key ✓
- All with DEFAULT NULL except p_song_id and p_band_id (required) ✓

Confirmed: Repository call matches RPC signature exactly. All 11 parameters passed explicitly. ✓

### Destructive Behavior Check

Migration only modifies function logic, does not:

- Drop tables or columns
- Modify constraints
- Delete data
- Change column types
- Add cascades

No destructive behavior. ✓

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors in project code ✓

**Evidence:**

```
13079 issues found. (ran in 11.0s)
```

All errors located in external Firebase dependencies:

- `build/ios/SourcePackages/checkouts/flutterfire/packages/cloud_firestore/cloud_firestore/dartpad/lib/main.dart`
- `build/ios/SourcePackages/checkouts/flutterfire/packages/cloud_firestore/cloud_firestore/example/integration_test/`

Project code (`lib/` directory) has only deprecation info (not errors):

- `lib/features/setlists/setlist_detail_screen.dart:1716:29` — deprecated_member_use (axisAlignment)
- `lib/features/setlists/setlist_detail_screen.dart:2295:23` — deprecated_member_use (onReorder)
- `lib/features/setlists/setlists_tab_content.dart:511:25` — deprecated_member_use (onReorder)

No errors introduced by this implementation. ✓

## Test Results

**Status:** Not run (no automated tests exist for this feature)

**Manual device testing:** Deferred to Tony post-deployment per QA instructions

## Diff Safety Review

- **Secrets:** None found ✓
- **Debug artifacts:** None found ✓
- **Unrelated changes:** None found ✓

### Git Diff Inspection

Reviewed complete git diff (not relying on Engineer's embedded diff):

**Files changed:**

1. `lib/features/setlists/widgets/song_details_bottom_sheet.dart` — 4 hunks, all expected ✓
2. `supabase/migrations/20260703034302_fix_musical_key_clear_in_update_song_rpc.sql` — New file ✓

**Untracked files/directories:**

- `docs/features/band-data-isolation-audit/` — Unrelated, not part of this feature ✓
- `docs/features/cleared-song-key-reverts/` — This feature's documentation ✓
- Migration file (listed above) ✓

**Hunk-by-hunk review:**

**Hunk 1 (line 304):** Change detection normalization

```diff
-    final musicalKeyChanged = _currentMusicalKey != _originalMusicalKey;
+    final musicalKeyChanged =
+        (_currentMusicalKey ?? '') != (_originalMusicalKey ?? '');
```

- Purpose: Manager-approved Amendment 2 (normalize null/empty string) ✓
- Safe: No side effects, pure boolean logic ✓

**Hunk 2 (line 427):** Empty string assignment in \_selectKey()

```diff
-        _currentMusicalKey = null;
+        _currentMusicalKey = '';
```

- Purpose: Architect Task 2 (flow empty string through) ✓
- Safe: setState call, standard pattern ✓

**Hunk 3 (lines 473-479, 486):** Remove defensive conversion

```diff
-    // Treat empty string as null when saving musical key
-    final musicalKeyToSave =
-        (_currentMusicalKey != null && _currentMusicalKey!.isEmpty)
-            ? null
-            : _currentMusicalKey;
-
     final result = SongDetailsResult(
       ...
-      musicalKey: musicalKeyChanged ? musicalKeyToSave : null,
+      musicalKey: musicalKeyChanged ? _currentMusicalKey : null,
```

- Purpose: Architect Task 3 (remove defensive conversion) ✓
- Safe: Simplifies code, no behavior change except allowing empty string ✓

**Hunk 4 (lines 1019-1021):** Display empty string as placeholder

```diff
-          value: _currentMusicalKey ?? '—',
+          value: (_currentMusicalKey == null || _currentMusicalKey!.isEmpty)
+              ? '—'
+              : _currentMusicalKey!,
```

- Purpose: Manager-approved Amendment 1 (render empty string as "—") ✓
- Safe: Display logic only, no state mutation ✓

No print statements, TODO comments, test scaffolding, or debug flags. ✓

## Issues Found

None

## Outstanding Items for Tony

The following verification steps from the Architect plan are explicitly **NOT TESTED** in this QA pass and must be performed by Tony after deployment:

### Database Tests (Tier 1 — Pre-deployment & Tier 2 — Post-deployment)

**From ARCHITECT_PLAN.md sections "Verification Plan":**

**Tier 1 (Pre-deploy SQL tests, lines 444-502):**

- PRE-DEPLOY TEST 1: Verify empty string converts to NULL (test function logic in isolation)

**Tier 2 (Post-deploy integration tests, lines 506-638):**

- POST-DEPLOY TEST 1: Verify function exists with updated logic
- POST-DEPLOY TEST 2: Integration test — clear musical key via RPC
- POST-DEPLOY TEST 3: Verify other fields not affected

**Note:** These SQL tests cannot be run during code review because they require database access. Tony must execute them via Supabase SQL Editor after running `supabase db push` but before deploying the Flutter build.

### Manual Device Tests (QA Regression Areas 1-10)

**From ARCHITECT_PLAN.md section "QA Regression Areas" (lines 642-710):**

**Primary — Song Key Clearing (Bug Fix Validation):**

1. Clear key and verify persistence (badge stays gone after refresh)
2. Pull-to-refresh after clear (badge does not reappear)
3. Key badge behavior on different song cards (song_card.dart and reorderable_song_card.dart)
4. Re-set key after clearing (new key persists)
5. Legacy songs with NULL band_id (SECURITY DEFINER logic allows update)

**Secondary — Regression Tests (Other Metadata):** 6. Other metadata fields unaffected (title, artist, BPM, duration, tuning, notes, youtube_links, lyrics) 7. Key picker selection (non-clear scenarios work correctly) 8. Badge rendering timing (no flicker, immediate display)

**Edge Cases:** 9. Rapid save/cancel cycles (discard vs. save clear operations) 10. Multiple setlists sharing same song (global change propagates)

**Device coverage required:**

- iOS physical device (per original bug report)
- Android
- Web

## Summary

Code review **APPROVED**. Implementation correctly addresses the root cause (RPC not writing NULL when parameter is NULL) via the empty-string-sentinel pattern. All three Architect tasks plus two Manager-approved amendments are correctly implemented. Migration only modifies the expected RPC logic with no unintended changes. Code paths traced and verified via static analysis. No regressions, no safety issues, no out-of-scope changes. Flutter analyze passes with 0 project errors.

**Next steps:**

1. Tony: Run `supabase db push` to apply migration
2. Tony: Execute Tier 1 and Tier 2 SQL tests in Supabase SQL Editor
3. Tony: Deploy Flutter web build via `./tools/deploy_web.sh`
4. Tony: Perform manual device testing (QA Regression Areas 1-10) on iOS/Android/Web
5. If all tests pass: Commit and merge to main
6. If any tests fail: Report findings to Engineer for fixes

**Code is ready for database deployment and manual testing.**
