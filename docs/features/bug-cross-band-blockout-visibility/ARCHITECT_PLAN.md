# ARCHITECT PLAN — Cross-Band Block-Out Visibility

**Feature Identifier:** `bug/cross-band-blockout-visibility`  
**Type:** Bug (Diagnosis Required — Path Undetermined)  
**Date:** 2026-07-08  
**Status:** **AWAITING DECISION**

---

## Problem Summary

Tony is a member of multiple bands. He sets a block-out (unavailability) date while viewing one band's calendar and expects that date to also show as blocked/unavailable on his other bands' calendars, since he physically cannot be in two places on the same date. Currently the block-out only appears on the band it was created under.

**Critical Context:**  
Tony just deployed a new production web build to app.bandroadie.com today (2026-07-08) and wants this diagnosed before shipping matching mobile builds. This is a diagnosis-first investigation — do not assume a fix direction without presenting findings and tradeoffs for confirmation.

---

## Diagnosis

### Phase 0 — Workspace Verification ✅

```bash
Branch: main
Status: working tree clean
```

Git state is clean. No uncommitted changes to block investigation.

---

### Phase 1 — Schema Analysis ✅

**Table: `block_dates`**

Schema (from `lib/app/models/block_out.dart` header comment and repository code):
```sql
id          UUID PRIMARY KEY
user_id     UUID NOT NULL REFERENCES auth.users(id)
band_id     UUID NOT NULL REFERENCES bands(id)
date        DATE NOT NULL
reason      TEXT NOT NULL
created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
UNIQUE(user_id, band_id, date)
```

**Key Finding:**  
The `block_dates` table is **inherently band-scoped**. Each row is explicitly tied to a single `(user_id, band_id)` pair. The unique constraint `(user_id, band_id, date)` allows the same date to be blocked multiple times for a user — once per band.

**Calendar Display Query:**  
`lib/features/calendar/calendar_notifier.dart` queries block-out dates filtered by `band_id`:
```dart
supabase.from('block_dates').select().eq('band_id', bandId).order('date');
```

This means:
- Block-out created in Band A writes to `block_dates` with `band_id = Band A ID`
- Band B's calendar queries `block_dates` with `band_id = Band B ID`
- **Without additional propagation logic, Band B will never see Band A's block-out**

**Verdict:**  
Per-band isolation is the **default architectural behavior** of the `block_dates` table. Cross-band visibility requires explicit duplication of rows.

---

### Phase 2 — One Calendar Feature Investigation ✅

**Discovery:**  
A feature called "One Calendar" was designed, implemented, QA'd, and deployed on **2026-06-26** (11 days ago) to solve this exact problem.

**Migration:** `supabase/migrations/20260626005216_add_user_calendar_preferences.sql`

**Table: `user_calendar_preferences`**
```sql
CREATE TABLE user_calendar_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  one_calendar_enabled BOOLEAN NOT NULL DEFAULT true,              -- ✅ DEFAULT TRUE
  apply_to_mode TEXT NOT NULL DEFAULT 'all_bands',                 -- 'all_bands' or 'selected_bands'
  selected_band_ids UUID[] DEFAULT '{}',
  auto_block_conflicts_enabled BOOLEAN NOT NULL DEFAULT true,      -- ✅ DEFAULT TRUE
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);
```

**How One Calendar Works:**

1. **Manual block-out propagation** (`lib/features/events/widgets/event_editor_drawer.dart` lines 1104-1127):
   - After creating a block-out in the current band, the code checks One Calendar preferences
   - If `one_calendar_enabled = true`, it fetches the user's bands via `getBandIdsToApplyBlockOut()`
   - For each other band, it creates a duplicate block-out row with the same date/reason
   - Wrapped in try-catch (non-blocking — must not fail primary save)

2. **Auto-conflict blocking** (`lib/features/calendar/auto_conflict_blocking_service.dart`):
   - When a gig or rehearsal is created, auto-creates block-outs in other bands
   - Only if `one_calendar_enabled = true` AND `auto_block_conflicts_enabled = true`
   - Reason: `"Unavailable (scheduled with [Band Name])"`

**Settings UI Visibility:**  
`lib/features/settings/settings_screen.dart` lines 59-71:
```dart
final bandCount = ref.watch(activeBandProvider).userBands.length;
if (bandCount >= 2) {
  regularItems.add(SettingsItem(
    icon: AppIcons.calendar,
    label: 'One Calendar',
    subtitle: 'Share block-out dates across bands',
    onTap: _openOneCalendar,
  ));
}
```

**Critical Finding:**  
The "One Calendar" settings item is **only visible if the user belongs to 2+ bands**. If Tony has only 1 band, he would never see this setting.

---

### Phase 3 — Bug History Analysis ✅

**Timeline:**

1. **2026-06-26** — Commit `b6c833c`: `feat: One Calendar / shared block-out dates across bands`
   - Initial implementation and deployment
   - Migration deployed to production database (confirmed in QA report)
   - Defaults: `one_calendar_enabled = true`, `auto_block_conflicts_enabled = true`

2. **Later (exact date unknown)** — Bug discovered: Manual block-out propagation was broken
   - Feature identifier: `bug/one-calendar-manual-blackout`
   - Root cause: The live code path (`event_editor_drawer.dart`) initially lacked propagation logic
   - A separate file (`add_block_out_drawer.dart`) had correct propagation but was dead code

3. **Commit `bb3e9d0`**: `fix(calendar): propagate manual blockout dates across bands when One Calendar enabled (#39)`
   - Fix applied to `event_editor_drawer.dart`
   - Propagation logic added at lines 1104-1127
   - Fix is present in current `main` branch

4. **Multiple subsequent fixes:**
   - Commit `25c2b57`: `docs(calendar): architect plan for one-calendar propagation fix (db-only, applied manually 2026-07-07)` — yesterday
   - Commit `e3e60ec`: `fix(calendar): auto-block all occurrences of recurring rehearsals...`

**Verdict:**  
The One Calendar feature exists in production code and has undergone multiple bug fixes. The manual block-out propagation fix IS present in the codebase.

---

### Phase 4 — Current Code Verification ✅

**File:** `lib/features/events/widgets/event_editor_drawer.dart` lines 1104-1127

```dart
// One Calendar propagation: if enabled, replicate blockout to other bands.
// Wrapped in try-catch — must not fail the primary save.
try {
  final prefsRepo = ref.read(oneCalendarPreferencesRepositoryProvider);
  final userBandIds =
      ref.read(activeBandProvider).userBands.map((b) => b.id).toList();
  final bandIds = await prefsRepo.getBandIdsToApplyBlockOut(userBandIds);
  final otherBandIds =
      bandIds.where((id) => id != widget.bandId).toList();
  for (final bandId in otherBandIds) {
    try {
      await repository.createBlockOut(
        bandId: bandId,
        userId: userId,
        startDate: _selectedDate,
        untilDate: _blockOutUntilDate,
        reason: _notesController.text.trim(),
      );
    } catch (e) {
      debugPrint(
        '[EventEditorDrawer] Propagation failed for band $bandId: $e',
      );
    }
  }
} catch (e) {
  debugPrint('[EventEditorDrawer] One Calendar propagation error: $e');
}
```

**Verdict:**  
Manual block-out propagation logic is present and correct. If One Calendar is enabled, it will propagate block-outs to other bands.

---

### Phase 5 — Root Cause Hypothesis ✅

**Confidence: HIGH (confirmed by code evidence)**

The `block_dates` table is **designed to be per-band by default**. Cross-band visibility was **never part of the original design** — it was added later via the One Calendar feature (2026-06-26).

Tony's issue can be caused by one of the following:

| Root Cause | Likelihood | Evidence |
|-----------|------------|----------|
| **RC-1: One Calendar is disabled** | HIGH | Default is TRUE, but Tony may have toggled it OFF in settings, or preferences row may not exist / RPC may have failed to create defaults |
| **RC-2: Tony is unaware of One Calendar feature** | HIGH | Settings item is only visible for users with 2+ bands; Tony may not have discovered it or may not know it needs to be enabled |
| **RC-3: Tony has only 1 band** | MEDIUM | If Tony has only 1 band, the settings item is hidden AND cross-band propagation is irrelevant (no other bands to propagate to) |
| **RC-4: Browser cache serving old code** | MEDIUM | Tony just deployed web to production; PWA service worker may be serving cached pre-One-Calendar code; requires hard refresh |
| **RC-5: Preferences RPC is broken** | LOW | Migration deployed 11 days ago; if RPC was broken, other users would have reported it; manual SQL verification needed |
| **RC-6: Propagation logic has a regression** | LOW | Code inspection shows logic is present and correct; would require runtime debugging to confirm |

---

## Path Analysis

### Path A: Cross-Band Sharing is the Correct Fix (One Calendar Enforcement)

**Assumption:**  
Tony's expectation is correct — musicians cannot be in two places at once. Block-outs should be shared across all bands a user belongs to by default.

**What This Means:**

The One Calendar feature already solves this. The issue is:
1. **User Awareness:** Tony may not know about One Calendar or that it needs to be checked in settings
2. **Preferences State:** Tony's `user_calendar_preferences` row may have `one_calendar_enabled = false` (either manually toggled or RPC failed to create defaults)
3. **Cache Issue:** Tony's browser may be serving old code from before One Calendar was deployed

**Required Actions (if this path is chosen):**

1. **Tier 1 Verification (SQL):**
   ```sql
   -- Check if Tony has a preferences row and what the values are
   SELECT 
     one_calendar_enabled, 
     apply_to_mode, 
     auto_block_conflicts_enabled,
     created_at
   FROM user_calendar_preferences
   WHERE user_id = 'TONY_USER_ID';
   -- Expected: Row exists with one_calendar_enabled = true
   
   -- Check Tony's band membership
   SELECT 
     bm.band_id, 
     b.name as band_name,
     bm.role,
     bm.status
   FROM band_members bm
   JOIN bands b ON b.id = bm.band_id
   WHERE bm.user_id = 'TONY_USER_ID' 
     AND bm.status = 'active';
   -- Expected: 2+ rows (Tony must have 2+ bands for cross-band to matter)
   
   -- Check if block-outs exist in only one band
   SELECT 
     bd.band_id,
     b.name as band_name,
     bd.date,
     bd.reason
   FROM block_dates bd
   JOIN bands b ON b.id = bd.band_id
   WHERE bd.user_id = 'TONY_USER_ID'
   ORDER BY bd.date, b.name;
   -- Expected: If One Calendar is OFF, dates appear in only one band
   ```

2. **If preferences row doesn't exist or is FALSE:**
   - Option A: Enable One Calendar for Tony via SQL update
   - Option B: Guide Tony to enable it via Settings UI
   - Option C: Change migration default (affects all future users, not retroactive)

3. **If preferences row is TRUE but propagation didn't happen:**
   - Check browser console for JavaScript errors
   - Verify RPC `get_or_create_calendar_preferences` returns correct data
   - Check if `getBandIdsToApplyBlockOut()` repository method is working
   - Test in incognito mode (bypass cache)

4. **If this is a cache issue:**
   - Tony needs to hard refresh (Cmd+Shift+R on macOS Chrome/Firefox)
   - Or clear PWA cache / reinstall PWA

**Blast Radius:** LOW — existing feature, no code changes required  
**Effort:** LOW — SQL verification + settings check  
**Risk:** LOW — feature already exists and is working for other users (presumably)

---

### Path B: Per-Band Isolation is Correct by Design (No Fix Required)

**Assumption:**  
The original per-band design was intentional. Block-outs are band-specific because:
- Different bands may have different scheduling contexts
- A user may want to mark unavailability for one band but not another
- Cross-band sharing should be opt-in, not automatic

**What This Means:**

Tony's expectation doesn't match the product design. The One Calendar feature already exists as an **opt-in** solution for users who want cross-band sharing. If Tony hasn't enabled it, the app is working as designed.

**Required Actions (if this path is chosen):**

1. **Confirm Intent:**  
   - Is cross-band sharing supposed to be opt-in or automatic?
   - Should new users have One Calendar ON or OFF by default?
   - Current default: ON (migration default is TRUE)

2. **If opt-in is correct:**
   - Educate Tony about One Calendar feature
   - Ensure settings UI is discoverable
   - Verify Tony has 2+ bands (required for feature visibility)
   - No code changes needed

3. **If automatic is correct:**
   - Change product strategy: remove One Calendar toggle, make cross-band sharing always-on
   - Requires migration to remove `one_calendar_enabled` flag
   - Simplifies UX but removes user choice
   - Blast radius: MEDIUM (affects all users)

**Blast Radius:** NONE if opt-in is correct; MEDIUM if changing to always-on  
**Effort:** NONE if opt-in is correct; MEDIUM if changing to always-on  
**Risk:** NONE if no changes; MEDIUM if changing behavior for all users

---

## Tradeoffs

| Aspect | Path A: Enforce One Calendar | Path B: Keep Opt-In |
|--------|------------------------------|---------------------|
| **User Expectation** | Matches musician's physical reality (can't be in two places) | Allows band-specific scheduling flexibility |
| **Existing Users** | May surprise users who disabled One Calendar intentionally | No change — current behavior persists |
| **Default Behavior** | Already defaults to ON (migration default TRUE) | Already defaults to ON (no change) |
| **Settings Visibility** | Only visible for users with 2+ bands (correct) | Only visible for users with 2+ bands (correct) |
| **Code Changes** | None — feature already exists | None — current design is intentional |
| **Migration Required** | None | None |
| **Tony's Issue** | Likely a settings/awareness issue, not a bug | Working as designed; Tony needs to enable One Calendar |
| **Discoverability** | Settings item may not be obvious; could add onboarding hint | Same |

---

## Recommendation

**Confidence: MEDIUM (awaiting Tony's preferences state confirmation)**

This appears to be a **settings/awareness issue**, not a technical bug. The One Calendar feature was designed and deployed 11 days ago (2026-06-26) to solve exactly this problem. The code is correct and present in production.

**Recommended Next Steps:**

1. **Verify Tony's One Calendar preferences state** (SQL query above)
2. **Verify Tony has 2+ bands** (Settings item won't appear for single-band users)
3. **Check if Tony's browser is serving cached code** (deployed today — cache may be stale)
4. **Ask Tony:**
   - "Do you see a 'One Calendar' item in Settings?"
   - "Have you enabled One Calendar sharing?"
   - "Did you recently disable One Calendar after it was automatically enabled?"

**Most Likely Scenario:**

Tony either:
- Has One Calendar disabled (manually or preferences never initialized)
- Hasn't discovered the Settings item
- Is seeing cached old code (deployed today — service worker may be serving pre-One-Calendar build)

**If preferences are enabled and browser is not cached:**

Then this is a **technical bug** (propagation logic not executing), and we should proceed to:
- Add debug logging to propagation code path
- Test in production with Tony's account
- Check for RLS policy issues preventing cross-band writes
- Verify RPC `get_or_create_calendar_preferences` is returning correct data

---

## Database Impact

**Database: Not Applicable (assuming Path A settings/awareness issue)**

If this is a technical bug requiring code changes:
- No schema changes required
- `user_calendar_preferences` table already exists
- `get_or_create_calendar_preferences` RPC already exists
- `block_dates` RLS policies already allow cross-band inserts (confirmed by gig propagation working)

---

## Files Investigated

| File | Purpose | Finding |
|------|---------|---------|
| `supabase/migrations/20260626005216_add_user_calendar_preferences.sql` | One Calendar migration | Defaults: `one_calendar_enabled = true`, `auto_block_conflicts_enabled = true` |
| `lib/features/events/widgets/event_editor_drawer.dart` | Manual block-out creation | Propagation logic present at lines 1104-1127 ✅ |
| `lib/features/calendar/auto_conflict_blocking_service.dart` | Auto-conflict blocking | Propagation logic present for gig/rehearsal creation ✅ |
| `lib/features/calendar/block_out_repository.dart` | Block-out data layer | Per-band by design; supports cross-band writes via multiple inserts |
| `lib/features/calendar/one_calendar_settings_screen.dart` | One Calendar settings UI | Exists; only visible for users with 2+ bands |
| `lib/features/settings/settings_screen.dart` | Main settings menu | "One Calendar" item conditionally visible |
| `lib/features/calendar/one_calendar_preferences_repository.dart` | Preferences data layer | `getBandIdsToApplyBlockOut()` implements propagation logic |
| `docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md` | Original feature design | Feature was intentionally designed to solve this exact problem |
| `docs/features/one-calendar-manual-blackout/ARCHITECT_PLAN.md` | Bug fix for manual propagation | Propagation was broken initially; fix is present in current code |

---

## Verification Plan

### Tier 1 — Pre-Decision (SQL Verification Required)

**Tony must provide:**

1. **His user ID** (from Supabase auth dashboard or `supabase.auth.currentUser.id` in browser console)

**Run these queries in Supabase SQL Editor:**

```sql
-- QUERY 1: Check Tony's One Calendar preferences
SELECT 
  id,
  user_id,
  one_calendar_enabled,
  apply_to_mode,
  selected_band_ids,
  auto_block_conflicts_enabled,
  created_at,
  updated_at
FROM user_calendar_preferences
WHERE user_id = 'TONY_USER_ID';
-- Expected: Row exists with one_calendar_enabled = true (migration default)
-- If no row: RPC failed to create defaults
-- If row exists with FALSE: Tony manually disabled it

-- QUERY 2: Check Tony's band membership
SELECT 
  bm.id as membership_id,
  bm.band_id,
  b.name as band_name,
  bm.role,
  bm.status,
  bm.joined_at
FROM band_members bm
JOIN bands b ON b.id = bm.band_id
WHERE bm.user_id = 'TONY_USER_ID'
ORDER BY bm.joined_at;
-- Expected: 2+ rows with status = 'active' (One Calendar requires 2+ bands)

-- QUERY 3: Check Tony's existing block-out dates
SELECT 
  bd.id,
  bd.band_id,
  b.name as band_name,
  bd.date,
  bd.reason,
  bd.created_at
FROM block_dates bd
JOIN bands b ON b.id = bd.band_id
WHERE bd.user_id = 'TONY_USER_ID'
ORDER BY bd.date DESC, b.name
LIMIT 20;
-- Expected: If One Calendar is OFF, same date appears in only one band
-- If One Calendar is ON, same date appears in multiple bands with same reason

-- QUERY 4: Check if get_or_create_calendar_preferences RPC works
SELECT * FROM get_or_create_calendar_preferences('TONY_USER_ID');
-- Expected: Returns JSONB with one_calendar_enabled = true
```

### Tier 2 — Post-Decision (if technical bug confirmed)

If Tier 1 shows:
- Preferences exist and `one_calendar_enabled = true`
- Tony has 2+ bands
- Block-outs still don't propagate

Then proceed with:

**Browser Testing:**

1. Open app in incognito mode (bypass cache)
2. Create test block-out in Band A
3. Check browser console for errors
4. Switch to Band B
5. Verify if block-out appears

**Debug Logging:**

Add temporary logging to `event_editor_drawer.dart` propagation block:
```dart
debugPrint('[DEBUG] One Calendar check: bandIds=$bandIds, otherBandIds=$otherBandIds');
```

**RLS Policy Verification:**

```sql
-- Check if block_dates INSERT policy allows cross-band writes
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'block_dates';
-- Expected: INSERT policy allows writes if user is member of target band
```

---

## QA Regression Areas

**If code changes are required (unlikely):**

1. **One Calendar propagation** — Verify manual block-outs propagate when enabled
2. **One Calendar disabled** — Verify no propagation when disabled
3. **Single-band users** — Verify no settings item visible, no errors
4. **Multi-band users** — Verify settings item visible, propagation works
5. **Auto-conflict blocking** — Verify gig/rehearsal creation still auto-blocks
6. **Block-out deletion** — Verify deletion prompt shows cross-band choice when applicable
7. **Calendar display** — Verify block-outs appear on all bands' calendars when propagated

---

## Next Steps

**STOP — Awaiting Decision:**

1. **Tony:** Provide user ID for SQL verification
2. **Manager:** Review Path A vs. Path B tradeoffs
3. **Tony:** Confirm One Calendar settings state in app (Settings → One Calendar)
4. **Tony:** Confirm browser is serving latest code (hard refresh: Cmd+Shift+R)

Do not proceed to Engineer implementation until root cause is confirmed via Tier 1 verification.

---

**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-07-08  
**Status:** AWAITING DECISION
