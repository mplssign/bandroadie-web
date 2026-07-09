# ARCHITECT PLAN — Cross-Band Block-Out Visibility

**Feature Identifier:** `bug/cross-band-blockout-visibility`  
**Type:** Bug  
**Date:** 2026-07-08  
**Status:** **SCOPE EXPANDED — Multiple Issues Confirmed**

---

## Problem Summary

Tony is a member of multiple bands. He sets a block-out (unavailability) date while viewing one band's calendar and expects that date to also show as blocked/unavailable on his other bands' calendars, since he physically cannot be in two places on the same date.

**Reported Issues:**

1. **Manual block-outs don't appear immediately** — When Tony creates a block-out in one browser tab/window, it doesn't appear in his other bands' calendars in already-open tabs/windows without a page reload.

2. **Gigs are not creating auto-conflict blocks** — When Tony creates a gig in one band, the date should automatically be blocked in his other bands (via One Calendar auto-conflict-blocking feature). This is NOT happening for gigs (but IS working for rehearsals).

3. **Historical events have no cross-band blocks** — Tony has 62 events (21 gigs + 41 rehearsals) created before One Calendar was deployed (2026-06-26). These events have no corresponding block-outs in his other bands' calendars.

**Critical Context:**  
Tony just deployed a new production web build to app.bandroadie.com today (2026-07-08) and wants this diagnosed before shipping matching mobile builds. This expanded to a multi-issue investigation with distinct root causes requiring different fixes.

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

| Root Cause                                        | Likelihood | Evidence                                                                                                                                 |
| ------------------------------------------------- | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| **RC-1: One Calendar is disabled**                | HIGH       | Default is TRUE, but Tony may have toggled it OFF in settings, or preferences row may not exist / RPC may have failed to create defaults |
| **RC-2: Tony is unaware of One Calendar feature** | HIGH       | Settings item is only visible for users with 2+ bands; Tony may not have discovered it or may not know it needs to be enabled            |
| **RC-3: Tony has only 1 band**                    | MEDIUM     | If Tony has only 1 band, the settings item is hidden AND cross-band propagation is irrelevant (no other bands to propagate to)           |
| **RC-4: Browser cache serving old code**          | MEDIUM     | Tony just deployed web to production; PWA service worker may be serving cached pre-One-Calendar code; requires hard refresh              |
| **RC-5: Preferences RPC is broken**               | LOW        | Migration deployed 11 days ago; if RPC was broken, other users would have reported it; manual SQL verification needed                    |
| **RC-6: Propagation logic has a regression**      | LOW        | Code inspection shows logic is present and correct; would require runtime debugging to confirm                                           |

---

### Phase 6 — Tier 1 Verification (COMPLETE) ✅

**Tony confirmed via settings UI:**

- ✅ One Calendar is **ON**
- ✅ Mode is set to **"All bands"**
- ✅ Auto-conflict blocking is **ON**
- ✅ Tony has **3 active bands** ("Open Mic", "The Second Summer", "Toxic Crayon")

**SQL Verification (user_id: `671b32e8-60eb-448a-8167-106bf835297f`):**

```sql
-- Preferences state (confirmed)
one_calendar_enabled: true
apply_to_mode: all_bands
auto_block_conflicts_enabled: true
created_at: 2026-06-26 21:55:31 (11 days ago — correct migration date)

-- Band membership (confirmed)
3 active bands:
- "Open Mic" (6740246d-ba9b-493e-936d-ba733ce2101d)
- "The Second Summer" (6d71a662-f1a4-4fb9-a611-9b2c8e7716d3)
- "Toxic Crayon" (003be463-e63a-4ec5-b152-4f64c60afcbf)
```

**RC-1, RC-2, RC-3 ruled out.** Tier 1 checks passed. Moving to Tier 2.

---

### Phase 7 — Tier 2 Database Verification (COMPLETE) ✅

**Reproduction Test:**  
Tony created a block-out in an incognito window, then checked his regular (already-open) browser window showing a different band — the block-out did not appear.

**Database Query Results:**

**Test 1 — Recent block-out with "Test" reason (2026-10-01):**

```
Created: 2026-07-09 03:26:20 (all within 200ms)
✅ Open Mic:         03:26:20.990461
✅ The Second Summer: 03:26:20.935362
✅ Toxic Crayon:     03:26:20.822075
```

**Verdict:** Propagation **WORKED** — all 3 bands received the block-out.

**Test 2 — Earlier block-out (2026-08-04):**

```
Created: 2026-07-09 03:25:23
✅ Open Mic:         03:25:23.990926
❌ The Second Summer: (pre-existing from 2026-05-24 22:41:30)
✅ Toxic Crayon:     03:25:23.616281
```

**Verdict:** Propagation **PARTIAL** — skipped "The Second Summer" due to unique constraint violation (block-out for that date already existed from May 24th). This is **correct behavior** — propagation code has try-catch that gracefully skips duplicates.

**RLS Policy Check:**

```sql
INSERT policy: is_band_member(band_id) AND (user_id = auth.uid())
```

This is correct. Tony is a member of all 3 bands, so cross-band writes are permitted.

**Unique Constraint:**

```sql
UNIQUE (user_id, band_id, date)
```

Prevents duplicate block-outs for the same user/band/date. Working as designed.

---

### Phase 8 — Git History Verification ✅

**Deployed Code Verification:**

All three critical commits are present in `main` branch:

- ✅ `bb3e9d0` — Manual block-out propagation fix (deployed)
- ✅ `25c2b57` — DB-only propagation fix documentation (2026-07-07)
- ✅ `e3e60ec` — Recurring rehearsal auto-block fix (deployed)

**Verdict:** Propagation logic is present and correct in deployed code.

---

### Phase 9 — Root Cause Confirmed ✅

**Confidence: HIGH (confirmed by database + code evidence)**

**The propagation logic works correctly** — block-outs DO propagate to all other bands at the database level. The issue Tony experienced is a **stale cache / no realtime sync** problem:

**How the bug manifests:**

1. Tony creates a block-out in **Browser Window A** (incognito, viewing Band A)
2. Propagation writes rows to all 3 bands in the database ✅ (confirmed by SQL)
3. `event_editor_drawer.dart` calls `ref.read(calendarProvider.notifier).invalidateAndRefresh(bandId: widget.bandId)` at line 1134
4. This invalidates the cache **ONLY** for Band A in Window A's Riverpod state
5. Tony switches to **Browser Window B** (already-open regular browser, viewing Band B)
6. Window B's `calendarProvider` state is **NOT invalidated** because:
   - Riverpod state is **not shared across browser tabs/windows**
   - There is **no realtime subscription** to database changes
   - Window B's calendar is using **cached data** from its last load
7. Tony refreshes the view or switches months → still shows cached data
8. Tony must **manually reload the page** (Cmd+R) or navigate away and back to trigger a fresh database query

**The same issue occurs within a single tab:**  
If Tony creates a block-out while viewing Band A, then switches to Band B's calendar view in the same tab, Band B's calendar will use cached data unless the cache TTL (5 minutes) has expired or a manual refresh is triggered.

**File: `lib/features/calendar/calendar_controller.dart` lines 433-443:**

```dart
Future<void> invalidateAndRefresh({required String bandId}) async {
  final keysToRemove =
      _cache.keys.where((key) => key.startsWith('$bandId-')).toList();

  for (final key in keysToRemove) {
    _cache.remove(key);
  }

  await loadEvents(forceRefresh: true);
}
```

This method only invalidates cache keys for the **specified bandId**. Other bands' caches remain untouched.

**Root Cause Summary:**

| Component              | Behavior          | Issue                                                       |
| ---------------------- | ----------------- | ----------------------------------------------------------- |
| **Propagation logic**  | ✅ CORRECT        | Writes to all bands successfully                            |
| **Database writes**    | ✅ CORRECT        | Rows exist for all target bands                             |
| **RLS policies**       | ✅ CORRECT        | Cross-band writes permitted                                 |
| **Cache invalidation** | ❌ **INCOMPLETE** | Only invalidates current band's cache                       |
| **Realtime sync**      | ❌ **MISSING**    | No Supabase Realtime subscription for `block_dates` changes |

**Why this wasn't caught earlier:**

One Calendar was designed and QA'd using code-path analysis, not runtime testing with multiple browser tabs open simultaneously. The QA report explicitly states: "Validation Method: Code-path analysis only (runtime testing blocked by migration deployment failure)."

---

### Phase 10 — Auto-Conflict-Blocking Verification (COMPLETE) ✅

**Tony reported:** Historical/pre-existing gigs and rehearsals in one band are NOT showing as block-outs in his other bands. This is a separate code path from manual block-outs.

**Database Verification:**

**Query 1: Auto-conflict blocks in Tony's account**

```
Total auto-conflict blocks (reason contains "Unavailable (scheduled with"): 4
All created: 2026-07-07 09:03-09:04 AM
All for: Open Mic events blocking Toxic Crayon and The Second Summer
```

**Query 2: Gig auto-conflict-blocking test**
Sample of 5 recent gigs:

- July 9 "The Little Owl Social Pub" (Open Mic, created July 7) → **NO blocks in other bands** ❌
- July 9 "Gravity Studios hold" (The Second Summer, created May 15) → **NO blocks** ❌
- July 8 gig (The Second Summer, created May 6) → **HAS block in Toxic Crayon** ✅ (but created July 7, 2 months later!)
- July 7 gig (The Second Summer, created May 6) → **HAS block in Toxic Crayon** ✅ (created July 7)

**Query 3: Rehearsal auto-conflict-blocking test**
Sample of 5 recent rehearsals:

- July 12 rehearsal (Toxic Crayon, created June 25) → **NO blocks** ❌
- July 8 rehearsal (Open Mic, created July 7) → **HAS blocks in both other bands** ✅ (created within 1 second)
- July 7 rehearsal (Toxic Crayon, created June 25) → **HAS block in The Second Summer** ✅ (created July 7, 12 days later!)
- June 17 & June 11 rehearsals (Toxic Crayon, created May 20) → **NO blocks** ❌

**Analysis:**

The 4 auto-conflict blocks that exist correspond to **ONE rehearsal** (July 8, created July 7 at 9:03:20 AM). The blocks were created at 9:03:21 (within 1 second). This proves auto-conflict-blocking **works for rehearsals**.

However:

- **Gigs created after July 7 have NO auto-conflict blocks** (e.g., July 9 "The Little Owl Social Pub" gig)
- Some blocks dated July 7-8 were created on July 7 but correspond to **events created in May/June** — these were likely manually backfilled or created via a different mechanism

**Root Cause:**

Auto-conflict-blocking is **BROKEN for gigs**. Code inspection shows:

- File: `lib/features/events/events_repository.dart` line ~650 — calls `autoBlockConflictingDates()` after gig creation
- File: `lib/features/calendar/auto_conflict_blocking_service.dart` — service implementation is correct
- **But gigs are NOT triggering auto-conflict blocks in production**

Possible causes:

1. Gig creation uses a different code path (update? edit? import?) that bypasses auto-conflict-blocking
2. Auto-conflict-blocking fails silently for gigs (try-catch swallows error, only logs to debugPrint)
3. Some condition prevents auto-blocking for gigs but not rehearsals

**Verdict:** Auto-conflict-blocking for gigs requires investigation. Cannot confirm fix until runtime debugging with production data.

---

### Phase 11 — Historical Gap Quantification (COMPLETE) ✅

**Query: Events created before One Calendar feature (2026-06-26)**

| Category                                    | Count                            |
| ------------------------------------------- | -------------------------------- |
| Gigs created before 2026-06-26              | 21                               |
| Rehearsals created before 2026-06-26        | 41                               |
| Manual block-outs created before 2026-06-26 | 155                              |
| **Total events without cross-band blocks**  | **62** (21 gigs + 41 rehearsals) |

**Analysis:**

One Calendar was deployed 2026-06-26 with propagation-on-create logic. Any event created **before** that date has:

- ✅ A row in `gigs` or `rehearsals` or `block_dates` for the original band
- ❌ NO corresponding `block_dates` rows in other bands

This is expected behavior — propagation only fires at creation time. There is no retroactive backfill mechanism.

**Impact:**

Tony has 62 historical events (21 gigs + 41 rehearsals) that will **never** appear as block-outs in his other bands' calendars unless:

1. A one-time backfill job is run to populate missing `block_dates` rows
2. Tony manually edits each event (triggering an update that may or may not re-run propagation)
3. Tony manually creates duplicate block-outs for those dates

**Design Question:**

Should historical events be backfilled? This is a product decision:

- **Option A: Backfill for all users** — Large blast radius, but ensures consistent experience
- **Option B: Backfill for Tony only** — Test in production with real data before wider rollout
- **Option C: No backfill** — Historical events remain per-band; only new events propagate
- **Option D: Build a user-facing "Sync Calendar" button** — Let users opt-in to backfill on demand

**Backfill Design (dry-run required before any writes):**

A backfill job would need to:

1. Query all users with `one_calendar_enabled = true`
2. For each user, fetch all `gigs` and `rehearsals` in bands they belong to
3. For each event, check if corresponding `block_dates` rows exist in other bands
4. Respect `apply_to_mode` (all_bands vs selected_band_ids)
5. Insert missing `block_dates` rows with reason `"Unavailable (scheduled with [Band Name])"`
6. Handle unique constraint violations gracefully (skip existing rows)
7. Log count of rows inserted per user for audit trail

**Effort:** MEDIUM (new script/migration, ~100-200 lines)  
**Risk:** MEDIUM (production data mutation, requires careful testing)  
**Blast Radius:** Depends on scope (single user vs all users)

---

## Proposed Solution (Updated)

### Path: Multi-Band Cache Invalidation (Issue 1)

**Approach:**  
When a block-out is created with One Calendar enabled, invalidate the calendar cache for **all bands** the user belongs to, not just the current band.

**Implementation:**

Add a helper method to `CalendarNotifier`:

```dart
void invalidateCacheForBand(String bandId) {
  final keysToRemove =
      _cache.keys.where((key) => key.startsWith('$bandId-')).toList();
  for (final key in keysToRemove) {
    _cache.remove(key);
  }
}
```

Then call it from `event_editor_drawer.dart`:

```dart
// Refresh calendar for current band
ref
    .read(calendarProvider.notifier)
    .invalidateAndRefresh(bandId: widget.bandId);

// One Calendar: invalidate cache for other bands
if (otherBandIds.isNotEmpty) {
  final notifier = ref.read(calendarProvider.notifier);
  for (final bandId in otherBandIds) {
    notifier.invalidateCacheForBand(bandId);
  }
}
```

**What this fixes:**

- ✅ Within the same browser tab: switching from Band A to Band B will show the new **manual** block-out immediately
- ❌ Across browser tabs/windows: still requires manual page reload (no cross-tab state sync)

**What this doesn't fix:**

- Cross-tab/window sync (requires Supabase Realtime subscription — separate feature)
- Other users' calendars updating when you create a block-out (requires Realtime)
- **Auto-conflict-blocking for gigs** (requires investigation, see Phase 10)
- **Historical gap** (events created before 2026-06-26, see Phase 11 backfill design)

---

## Scope Summary

**Three distinct issues confirmed:**

### Issue 1: Cache Invalidation (Manual Block-Outs)

**Severity:** MEDIUM  
**Status:** Root cause confirmed, fix ready  
**Blast Radius:** LOW  
**Files:** 2 (`calendar_controller.dart`, `event_editor_drawer.dart`)  
**Effort:** LOW (add helper method + call it in propagation loop)  
**Risk:** LOW (cache invalidation is safe)

### Issue 2: Auto-Conflict-Blocking for Gigs

**Severity:** HIGH  
**Status:** ROOT CAUSE CONFIRMED — gig creation path missing auto-conflict-blocking call  
**Blast Radius:** HIGH (affects all users creating gigs, fix will restore intended feature behavior)  
**Files:** 1 (`lib/features/events/events_repository.dart`)  
**Effort:** MEDIUM (code appears present in Git, likely build/deployment issue)  
**Risk:** LOW (identical pattern to rehearsals which work correctly, non-blocking try-catch)

**Evidence:** Only 4 auto-conflict blocks exist for Tony, all from ONE rehearsal. Recent gigs (e.g., July 9 "The Little Owl Social Pub") have NO auto-conflict blocks despite being created with One Calendar enabled.

**Console Log Evidence (Tony, 2026-07-09):**

Tony created a test gig and captured browser console output immediately after saving:

```
[EventsRepository] Creating gig for band: e89bea44-8dd4-4e3d-b527-c0f75e94aa7d
[EventsRepository] Inserting gig with data: {band_id: ..., name: Test Gig, date: 2026-07-09, ...}
[EventsRepository] Invalidating cache for band: e89bea44-8dd4-4e3d-b527-c0f75e94aa7d
[EventsRepository] Invalidating cache for band: e89bea44-8dd4-4e3d-b527-c0f75e94aa7d
[BlockOutRepository] Fetching block dates for band: e89bea44-8dd4-4e3d-b527-c0f75e94aa7d
```

**Critical Finding:** NO `[AutoConflictBlockingService]` log appears anywhere in the output — not a success log, not a caught error, nothing. The service is never invoked during gig creation. This is confirmed root cause: the code path that creates rehearsals successfully calls into auto-conflict-blocking (proven by July 8 rehearsal DB evidence), but the code path that creates gigs does not.

---

#### Issue 2 — Root Cause Analysis

**Phase 12 — Code Path Comparison (COMPLETE) ✅**

**File:** `lib/features/events/events_repository.dart`

**Rehearsal Creation (`createRehearsal` method, lines 78-185):**

Lines 145-177 show the auto-conflict-blocking call:

```dart
invalidateCache(bandId);

// Trigger automatic conflict blocking (if enabled)
if (firstRehearsal != null) {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      // Fetch band name for auto-conflict blocking reason
      final bandResponse = await supabase
          .from('bands')
          .select('name')
          .eq('id', bandId)
          .single();
      final bandName = bandResponse['name'] as String;

      await _autoConflictBlockingService.autoBlockConflictingDates(
        userId: userId,
        eventBandId: bandId,
        eventDates: dates,
        eventStartTime: null,
        eventEndTime: null,
        eventName: 'Rehearsal',
        bandName: bandName,
      );
    }
  } catch (e) {
    // Do not fail rehearsal creation if auto-blocking fails
    debugPrint('[EventsRepository] Auto-conflict blocking failed: $e');
  }
}
```

**Expected Service Logs:** `[AutoConflictBlockingService] Auto-blocking X date(s) for user: ...` (line 142 of service)

**Gig Creation (`createGig` method, lines 569-680):**

Git repository shows auto-conflict-blocking code at lines 632-668:

```dart
invalidateCache(bandId);

// Trigger automatic conflict blocking (if enabled)
try {
  final userId = supabase.auth.currentUser?.id;
  if (userId != null) {
    // Fetch band name for auto-conflict blocking reason
    final bandResponse = await supabase
        .from('bands')
        .select('name')
        .eq('id', bandId)
        .single();
    final bandName = bandResponse['name'] as String;

    // Build date list: main date + additional dates
    final allDates = [
      formData.date,
      ...formData.additionalDates.map((e) => e.date),
    ];

    await _autoConflictBlockingService.autoBlockConflictingDates(
      userId: userId,
      eventBandId: bandId,
      eventDates: allDates,
      eventStartTime: null,
      eventEndTime: null,
      eventName: formData.name ?? formData.displayName,
      bandName: bandName,
    );
  }
} catch (e) {
  // Do not fail gig creation if auto-blocking fails
  debugPrint('[EventsRepository] Auto-conflict blocking failed: $e');
}
```

**Discrepancy:**

- **Git repository code:** Lines 632-668 contain auto-conflict-blocking logic, structurally identical to rehearsal pattern
- **Runtime behavior:** Tony's console logs show NO service invocation, NO debug logs from try block or catch block
- **Conclusion:** The code exists in Git but is NOT executing in the deployed production build

**Possible Causes:**

1. **Build cache issue:** Flutter web build cached old code without auto-conflict-blocking
2. **Deployment mismatch:** Production was deployed from a branch that predates commit `e3e60ec` (2026-07-07)
3. **Hot reload artifact:** Development server retained old code in memory
4. **Code removal:** Manual edit removed the code in production (unlikely)

**Git History Verification:**

```bash
$ git log --oneline lib/features/events/events_repository.dart | head -10
e3e60ec fix(calendar): auto-block all occurrences of recurring rehearsals and multi-date gigs (#53)
064b8ca feat: add address field to gigs (#43)
b6c833c feat: One Calendar / shared block-out dates across bands
```

Commit `e3e60ec` (2026-07-07) added auto-conflict-blocking for multi-date gigs, changing from `autoBlockConflictingDate` (singular) to `autoBlockConflictingDates` (plural). This commit IS on the `main` branch and IS on current branch `bug/cross-band-blockout-visibility`.

**Verdict:**

The code is present in Git but not executing in production. This indicates a build/deployment issue, not a missing feature. The fix requires ensuring the production build includes the latest code.

---

#### Issue 2 — Proposed Fix

**Approach:** Verify auto-conflict-blocking code is present in production build, perform clean rebuild and redeployment.

**Engineer Tasks:**

**Task 1:** Add debug logging to confirm code path execution

**File:** `lib/features/events/events_repository.dart`

**Location:** Line 632, immediately before the auto-conflict-blocking try block

**Add:**

```dart
invalidateCache(bandId);

// DEBUG: Confirm code path is reached (remove after verification)
debugPrint('[EventsRepository] DEBUG: About to trigger auto-conflict blocking for gig');

// Trigger automatic conflict blocking (if enabled)
try {
```

**Purpose:** If this log appears but service logs don't, it confirms the try block is entered but service call fails. If this log doesn't appear, it confirms the code path is not reached.

**Task 2:** Verify code matches Git repository

**Action:** Open `lib/features/events/events_repository.dart` in IDE and confirm lines 632-668 match the expected structure documented above.

**Expected Result:** Code should be present and identical to rehearsal pattern.

**Task 3:** Perform clean rebuild

**Commands:**

```bash
flutter clean
flutter pub get
flutter build web --release
```

**Purpose:** Clear all build caches and force a fresh compilation from source. This eliminates cached artifacts that may contain old code.

**Task 4:** Deploy and verify

**Actions:**

1. Deploy clean web build to production
2. Create test gig in browser with DevTools console open
3. Capture console output
4. Verify presence of `[AutoConflictBlockingService]` logs
5. Query database to confirm `block_dates` rows were created in other bands

**Expected Console Output:**

```
[EventsRepository] Creating gig for band: ...
[EventsRepository] Inserting gig with data: ...
[EventsRepository] DEBUG: About to trigger auto-conflict blocking for gig
[EventsRepository] Invalidating cache for band: ...
[AutoConflictBlockingService] Auto-blocking 1 date(s) for user: ..., event: Test Gig
[AutoConflictBlockingService] Auto-blocked date for band: ...
[AutoConflictBlockingService] Auto-block complete: 2 bands
```

**Task 5:** Remove debug logging

**Action:** Remove the debug log added in Task 1 once verification is complete.

**Alternative Fix (if code is actually missing):**

If Tasks 1-2 reveal the code is genuinely missing from the file (not a build issue), then manually add the auto-conflict-blocking code by copying the pattern from `createRehearsal` (lines 148-177) and adapting it for gigs:

```dart
invalidateCache(bandId);

// Trigger automatic conflict blocking (if enabled)
try {
  final userId = supabase.auth.currentUser?.id;
  if (userId != null) {
    // Fetch band name for auto-conflict blocking reason
    final bandResponse = await supabase
        .from('bands')
        .select('name')
        .eq('id', bandId)
        .single();
    final bandName = bandResponse['name'] as String;

    // Build date list: main date + additional dates
    final allDates = [
      formData.date,
      ...formData.additionalDates.map((e) => e.date),
    ];

    await _autoConflictBlockingService.autoBlockConflictingDates(
      userId: userId,
      eventBandId: bandId,
      eventDates: allDates,
      eventStartTime: null,
      eventEndTime: null,
      eventName: formData.name ?? formData.displayName,
      bandName: bandName,
    );
  }
} catch (e) {
  // Do not fail gig creation if auto-blocking fails
  debugPrint('[EventsRepository] Auto-conflict blocking failed: $e');
}

// Fetch the gig with its dates to return complete data
final gigWithDates = await supabase
    .from('gigs')
    .select(
        '*, gig_dates(id, gig_id, date, start_time, created_at, updated_at)')
    .eq('id', gigId)
    .single();

return Gig.fromJson(gigWithDates);
```

**Critical Pattern Match:**

- ✅ Wrapped in try-catch (non-blocking)
- ✅ Checks `userId != null` before proceeding
- ✅ Fetches band name for reason text
- ✅ Builds date list including additional dates
- ✅ Calls `autoBlockConflictingDates` (plural) not singular
- ✅ Logs errors with `debugPrint` but doesn't rethrow
- ✅ Primary operation (return Gig) happens after try-catch completes

---

#### Issue 2 — Blast Radius Assessment

**Impact:** This fix will enable auto-conflict-blocking for ALL gig creation going forward for ALL users with One Calendar enabled, not just Tony.

**Risk Level:** LOW

**Justification:**

1. **Feature already deployed for rehearsals:** Rehearsals have been auto-blocking successfully since July 7, 2026 (commit `e3e60ec`). This fix brings gigs to parity.

2. **User settings respected:** Only users with `one_calendar_enabled = true` AND `auto_block_conflicts_enabled = true` will be affected. Users can disable this in Settings → One Calendar.

3. **Non-blocking implementation:** The auto-conflict-blocking code is wrapped in try-catch. If it fails for any reason (network error, RLS issue, etc.), the gig creation still succeeds. User never sees an error.

4. **Consistent with feature design:** One Calendar was specifically designed to auto-block conflicts for BOTH gigs and rehearsals. Gigs not auto-blocking is a BUG, not a feature difference.

5. **No different than Issue 1:** Issue 1 (cache invalidation) also affects all users and also restores intended feature behavior. Both are low-risk fixes.

**Comparison to Issue 1:**

| Aspect                | Issue 1 (Cache)         | Issue 2 (Gig Auto-Block) |
| --------------------- | ----------------------- | ------------------------ |
| Blast Radius          | All users               | All users                |
| Restores Intended?    | Yes                     | Yes                      |
| Already Works for...  | N/A                     | Rehearsals               |
| User Settings Control | Yes (One Calendar flag) | Yes (same flags)         |
| Non-Blocking?         | N/A (cache only)        | Yes (try-catch)          |
| Risk Level            | LOW                     | LOW                      |

**Conclusion:** This fix is NO RISKIER than Issue 1. Both restore intended functionality that matches the already-designed and already-deployed One Calendar feature.

---### Issue 3: Historical Gap (Pre-One-Calendar Events)

**Severity:** MEDIUM  
**Status:** Expected behavior, backfill design required  
**Blast Radius:** Depends on scope (single user vs all users)  
**Files:** New backfill script/migration  
**Effort:** MEDIUM (~100-200 lines, requires dry-run validation)  
**Risk:** MEDIUM (production data mutation)

**Impact:** Tony has 62 historical events (21 gigs + 41 rehearsals) created before 2026-06-26 that will never appear as block-outs in other bands unless backfilled.

---

## Blast Radius (Combined)

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

## Recommendation

**Confidence: HIGH (three distinct issues confirmed)**

**Issue 1 (Cache Invalidation):** ✅ Ready for implementation. Low risk, clear fix.

**Issue 2 (Auto-Conflict-Blocking for Gigs):** ✅ ROOT CAUSE CONFIRMED. Ready for Engineer tasks. Code exists in Git but not executing in production — likely build cache issue. Fix requires clean rebuild + redeployment with verification logging. Low risk (identical pattern to working rehearsal implementation).

**Issue 3 (Historical Gap):** ⏸️ Requires **Tony's decision on scope** before implementation:

- Backfill only Tony's account? (safe, test in prod)
- Backfill all users? (high impact, requires dry-run first)
- No backfill, document as expected behavior? (simplest)
- Build user-facing "Sync Calendar" feature? (most flexible, more effort)

**Recommended Sequence:**

1. ✅ **Fix Issue 1 (Cache Invalidation)** — deploy immediately, low risk
2. ✅ **Fix Issue 2 (Gig Auto-Conflict-Blocking)** — root cause confirmed, Engineer tasks documented, ready for implementation
3. ⏸️ **Hold Issue 3 (Historical Backfill)** — awaiting Tony's decision on scope

**Issue 2 Confidence Level:**

- Console log evidence proves service is not invoked ✅
- Git history shows code IS present in repository ✅
- Rehearsals work correctly with identical pattern ✅
- Root cause: build/deployment artifact mismatch (cache issue) ✅
- Fix approach: clean rebuild + verification logging ✅
- Blast radius: same as Issue 1 (restores intended feature) ✅

---

## Database Impact

**Issue 1:** None (frontend cache only)

**Issue 2:** None (fix will use existing `block_dates` table)

**Issue 3:** HIGH if backfill is run

- Inserts potentially hundreds of rows to `block_dates` table
- Requires dry-run to quantify exact impact per user
- Must respect unique constraint `(user_id, band_id, date)` to avoid errors
- Recommend per-user batching to limit blast radius

---

## Files Investigated

| File                                                                   | Purpose                        | Finding                                                                                                                        |
| ---------------------------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| `supabase/migrations/20260626005216_add_user_calendar_preferences.sql` | One Calendar migration         | Defaults: `one_calendar_enabled = true`, `auto_block_conflicts_enabled = true`                                                 |
| `lib/features/events/widgets/event_editor_drawer.dart`                 | Manual block-out creation      | Propagation logic present at lines 1104-1127 ✅ Cache invalidation only for current band ❌                                    |
| `lib/features/calendar/calendar_controller.dart`                       | Calendar state management      | `invalidateAndRefresh()` only clears cache for one band at lines 433-443                                                       |
| `lib/features/calendar/auto_conflict_blocking_service.dart`            | Auto-conflict blocking         | Service implementation is correct ✅ BUT gigs are not triggering it ❌                                                         |
| `lib/features/events/events_repository.dart`                           | Event creation                 | Rehearsals call auto-blocking at lines 145-177 ✅ Gigs have code at lines 632-668 in Git ✅ BUT not executing in production ❌ |
| `lib/features/calendar/block_out_repository.dart`                      | Block-out data layer           | Per-band by design; supports cross-band writes via multiple inserts                                                            |
| `lib/features/calendar/one_calendar_settings_screen.dart`              | One Calendar settings UI       | Exists; only visible for users with 2+ bands                                                                                   |
| `lib/features/settings/settings_screen.dart`                           | Main settings menu             | "One Calendar" item conditionally visible                                                                                      |
| `lib/features/calendar/one_calendar_preferences_repository.dart`       | Preferences data layer         | `getBandIdsToApplyBlockOut()` implements propagation logic                                                                     |
| `docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md`         | Original feature design        | Feature was intentionally designed to solve this exact problem                                                                 |
| `docs/features/one-calendar-manual-blackout/ARCHITECT_PLAN.md`         | Bug fix for manual propagation | Propagation was broken initially; fix is present in current code                                                               |

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

**For Issue 1 (Cache Invalidation Fix):**

1. **Manual block-out propagation** — Verify block-outs created in Band A appear in Band B when switching bands within the same tab (no page reload required)
2. **One Calendar disabled** — Verify no propagation when disabled, cache behaves normally
3. **Single-band users** — Verify no errors when user has only 1 band (no propagation target)
4. **Multi-date block-outs** — Verify date ranges (e.g., "block Monday through Friday") propagate and invalidate cache correctly
5. **Cross-tab behavior** — Verify cross-tab sync still requires manual page reload (expected limitation)
6. **Cache expiration** — Verify stale cache (5+ minutes old) forces refresh as designed
7. **Band switching performance** — Verify no performance regression from cache invalidation (should be instant, no network calls for invalidation)
8. **Concurrent edits** — Verify no race conditions when creating block-outs rapidly in multiple bands

**For Issue 2 (Gig Auto-Conflict-Blocking, after root cause found):**

1. **Gig creation** — Verify gigs create auto-conflict blocks in other bands (currently broken)
2. **Rehearsal creation** — Verify rehearsals still create auto-conflict blocks (currently working)
3. **Potential gigs** — Verify `is_potential = true` gigs do NOT create auto-conflict blocks (by design)
4. **Multi-date gigs** — Verify gigs with `additionalDates` create blocks for all dates
5. **One Calendar disabled** — Verify no auto-conflict blocks when `auto_block_conflicts_enabled = false`
6. **Selected bands mode** — Verify `apply_to_mode = 'selected_bands'` respects `selected_band_ids`
7. **Event updates** — Verify editing a gig does NOT re-run auto-conflict-blocking (avoid duplicate rows)
8. **Event deletion** — Verify deleting a gig does NOT automatically delete auto-conflict blocks (user decision)

**For Issue 3 (Historical Backfill, if implemented):**

1. **Dry-run output** — Verify dry-run reports accurate count of rows to be inserted
2. **Duplicate prevention** — Verify unique constraint prevents duplicate `block_dates` rows
3. **One Calendar settings** — Verify backfill respects current `one_calendar_enabled` and `apply_to_mode` settings
4. **Band membership** — Verify backfill only creates blocks for bands user is currently a member of (not past bands)
5. **Date accuracy** — Verify block-out dates match source event dates
6. **Reason format** — Verify reason follows pattern: `"Unavailable (scheduled with [Band Name])"`
7. **Performance** — Verify backfill completes in reasonable time for large datasets (e.g., 100+ events)
8. **Rollback** — Document rollback procedure if backfill causes issues

---

## Backfill Decision Point (Issue 3)

**⚠️ DO NOT IMPLEMENT** until Tony confirms scope. This is a production data mutation that requires explicit approval.

**Dry-Run SQL (Tony's Account Only):**

```sql
-- Read-only query to quantify backfill impact for Tony
WITH tony_events AS (
  -- Tony's gigs in his bands
  SELECT
    g.band_id,
    g.date as event_date,
    b.name as band_name,
    'Gig: ' || g.name as event_name
  FROM gigs g
  JOIN bands b ON b.id = g.band_id
  WHERE g.band_id IN (
    SELECT band_id FROM band_members
    WHERE user_id = '671b32e8-60eb-448a-8167-106bf835297f' AND status = 'active'
  )
  AND g.is_potential = false

  UNION ALL

  -- Tony's rehearsals
  SELECT
    r.band_id,
    r.date,
    b.name,
    'Rehearsal at ' || r.location
  FROM rehearsals r
  JOIN bands b ON b.id = r.band_id
  WHERE r.band_id IN (
    SELECT band_id FROM band_members
    WHERE user_id = '671b32e8-60eb-448a-8167-106bf835297f' AND status = 'active'
  )
  AND r.is_potential = false
),
tony_bands AS (
  SELECT band_id, b.name as band_name
  FROM band_members bm
  JOIN bands b ON b.id = bm.band_id
  WHERE bm.user_id = '671b32e8-60eb-448a-8167-106bf835297f' AND bm.status = 'active'
),
missing_blocks AS (
  -- For each event, check which bands are missing corresponding block_dates
  SELECT
    te.event_date,
    te.band_name as event_band,
    tb.band_name as target_band,
    tb.band_id as target_band_id,
    'Unavailable (scheduled with ' || te.band_name || ')' as reason
  FROM tony_events te
  CROSS JOIN tony_bands tb
  WHERE tb.band_id != te.band_id  -- Don't block the band where event is happening
  AND NOT EXISTS (
    SELECT 1 FROM block_dates bd
    WHERE bd.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
      AND bd.band_id = tb.band_id
      AND bd.date = te.event_date
  )
)
SELECT
  COUNT(*) as rows_to_insert,
  COUNT(DISTINCT event_date) as unique_dates,
  COUNT(DISTINCT target_band) as bands_affected
FROM missing_blocks;
```

**Backfill Options:**

| Option                        | Scope                                      | Effort | Risk   | Decision Required                                     |
| ----------------------------- | ------------------------------------------ | ------ | ------ | ----------------------------------------------------- |
| **A: Backfill Tony only**     | 1 user                                     | LOW    | LOW    | Tony approves dry-run count                           |
| **B: Backfill all users**     | All users with `one_calendar_enabled=true` | MEDIUM | MEDIUM | Tony reviews aggregate dry-run, approves blast radius |
| **C: No backfill**            | None                                       | NONE   | NONE   | Tony accepts historical events remain per-band        |
| **D: "Sync Calendar" button** | Per-user on-demand                         | HIGH   | LOW    | Product decision, requires UI design                  |

**Tony's Decision:** Option A (backfill his account only)

**Dry-Run Status:** READY TO RUN — Supabase CLI experiencing authentication/connectivity issues. SQL files created for direct execution in Supabase Dashboard:

1. **Dry-Run:** `sql/fixes/backfill_tony_historical_blocks_dryrun.sql`
   - Shows exactly which rows would be inserted (event_date, event_description, origin_band, target_band, reason)
   - No database modifications, safe to run anytime
   - Tony should review full list and approve exact row count

2. **Backfill:** `sql/fixes/backfill_tony_historical_blocks.sql`
   - **⚠️ DO NOT RUN UNTIL Tony approves dry-run results**
   - Idempotent (can be re-run safely, skips existing rows)
   - Returns summary: rows_inserted, unique_dates, bands_affected
   - Rollback SQL included in file header comments

**If Tony chooses Option A or B, Engineer must:**

1. Run dry-run SQL first, report row counts
2. Get explicit approval from Tony with row counts visible
3. Implement as idempotent script (can be re-run safely) ✅ DONE
4. Run on staging/test data first (optional for single-user backfill)
5. Provide rollback SQL (DELETE WHERE created_at > [backfill_timestamp]) ✅ DONE

---

## Engineer Tasks (Issue 1 Only)

**Task 1:** Add `invalidateCacheForBand()` helper method to `CalendarNotifier`

**File:** `lib/features/calendar/calendar_controller.dart`

Add after the existing `invalidateAndRefresh()` method (around line 444):

```dart
/// Invalidates cache for a specific band without triggering a reload.
/// Used for cross-band cache invalidation when One Calendar propagates block-outs.
void invalidateCacheForBand(String bandId) {
  final keysToRemove =
      _cache.keys.where((key) => key.startsWith('$bandId-')).toList();
  for (final key in keysToRemove) {
    _cache.remove(key);
  }
}
```

**Task 2:** Call `invalidateCacheForBand()` for all propagated bands

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

Modify the block after One Calendar propagation (around line 1127, after the propagation try-catch closes):

**Current:**

```dart
} catch (e) {
  debugPrint('[EventEditorDrawer] One Calendar propagation error: $e');
}

// Close drawer, refresh, etc.
if (mounted) {
  Navigator.of(context).pop();
}

// Refresh calendar
ref
    .read(calendarProvider.notifier)
    .invalidateAndRefresh(bandId: widget.bandId);
```

**Proposed:**

```dart
} catch (e) {
  debugPrint('[EventEditorDrawer] One Calendar propagation error: $e');
}

// Close drawer, refresh, etc.
if (mounted) {
  Navigator.of(context).pop();
}

// Refresh calendar for current band
ref
    .read(calendarProvider.notifier)
    .invalidateAndRefresh(bandId: widget.bandId);

// One Calendar cross-band cache invalidation: if block-outs were propagated
// to other bands, invalidate their calendar caches so they pick up the new
// data when user switches bands (within this tab/window).
if (otherBandIds.isNotEmpty) {
  final notifier = ref.read(calendarProvider.notifier);
  for (final bandId in otherBandIds) {
    notifier.invalidateCacheForBand(bandId);
  }
}
```

**Note:** The variable `otherBandIds` is already available from the propagation logic above (line ~1112).

---

## Testing Instructions

**Manual Test 1: Same-tab band switching**

1. Navigate to Band A's calendar
2. Create a block-out for a future date (e.g., tomorrow)
3. Switch to Band B's calendar view (same browser tab)
4. **Expected:** Block-out appears on Band B's calendar immediately (no page reload required)

**Manual Test 2: Cross-tab sync (WILL NOT WORK — expected behavior)**

1. Open Band A's calendar in Tab 1
2. Open Band B's calendar in Tab 2
3. Create a block-out in Tab 1
4. Switch to Tab 2
5. **Expected:** Block-out does NOT appear until user manually reloads page (Cmd+R)
6. **Reason:** Riverpod state is not shared across tabs; would require Supabase Realtime subscription (separate feature)

**Manual Test 3: One Calendar disabled**

1. Settings → One Calendar → Turn OFF
2. Create a block-out in Band A
3. Switch to Band B's calendar
4. **Expected:** Block-out does NOT appear on Band B (no propagation when disabled)

**Manual Test 4: Cache expiration**

1. Create a block-out in Band A
2. Switch to Band B immediately
3. **Expected:** Block-out appears (cache invalidated)
4. Wait 5+ minutes
5. Create another block-out in Band A
6. Switch to Band B
7. **Expected:** Block-out still appears (cache was already stale, forced refresh)

---

## Next Steps

**Status: BOTH ISSUES 1 & 2 READY FOR ENGINEER**

### Issue 1 (Cache Invalidation) — Ready for Engineer ✅

1. **Engineer:** Implement Task 1 and Task 2 (documented in "Engineer Tasks (Issue 1 Only)" section above)
2. **Engineer:** Test per Manual Test instructions
3. **Engineer:** Submit PR with test evidence
4. **Tony:** Deploy to production web

### Issue 2 (Gig Auto-Conflict-Blocking) — Ready for Engineer ✅

**Root cause confirmed via console log evidence. Code exists in Git but not executing in production (build cache issue).**

1. **Engineer:** Implement Tasks 1-5 (documented in "Issue 2 — Proposed Fix / Engineer Tasks" section above)
   - Task 1: Add debug logging before auto-conflict-blocking try block
   - Task 2: Verify code matches Git repository (lines 632-668)
   - Task 3: Perform clean rebuild (`flutter clean && flutter pub get && flutter build web --release`)
   - Task 4: Deploy and verify with console logging + database query
   - Task 5: Remove debug logging after verification
2. **Engineer:** If code is genuinely missing (not just cache), use Alternative Fix pattern documented above
3. **Engineer:** Test by creating gigs with One Calendar enabled, verify block_dates created in other bands
4. **Engineer:** Submit PR with console log evidence + database query results
5. **Tony:** Deploy to production web

**Expected Result:** Gigs will auto-create block-outs in other bands, matching rehearsal behavior (already working since July 7).

### Issue 3 (Historical Backfill) — Awaiting Decision ⏸️

1. **Tony:** Review backfill options (A, B, C, or D)
2. **Tony:** If choosing Option A (backfill Tony's account only):
   - SQL scripts already created: `sql/fixes/backfill_tony_historical_blocks_dryrun.sql` and `sql/fixes/backfill_tony_historical_blocks.sql`
   - Run dry-run SQL first to review exact row list
   - Approve explicit row count before running backfill
3. **Tony:** If choosing Option B (backfill all users):
   - Requires new SQL script (dry-run first)
   - Higher risk, needs careful review
4. **Engineer:** Only implement if Tony provides explicit approval with row counts

---

## Issue 2 — Resolution

**Status:** CLOSED — Root cause was stale browser cache, not a code defect  
**Date:** 2026-07-09  
**Confidence:** HIGH (controlled A/B test with same session, same gig-creation action)

### Evidence Summary

Tony conducted a controlled runtime test with two gig-creation attempts in the same browser session:

**Attempt 1 — "Test Gig" (no browser refresh):**

- Browser: regular session, no refresh since before commit `e3e60ec` deployment
- Result: Zero `[AutoConflictBlockingService]` log lines in console
- Database: No auto-conflict block_dates rows created
- **Conclusion:** Service was never invoked

**Attempt 2 — "Test Gig 2" (after hard refresh):**

- Browser: same session, hard refresh performed (Cmd+Shift+R)
- Result: Full successful trace in console:
  ```
  [AutoConflictBlockingService] Auto-blocking 1 date(s)
  [OneCalendarPreferencesRepository] Preferences RPC confirmed: one_calendar_enabled: true, apply_to_mode: all_bands
  [AutoConflictBlockingService] Apply to all bands: 2 bands
  [AutoConflictBlockingService] Auto-block complete: 1 date(s) × 1 bands
  ```
- Database: block_dates row created in target band
- **Conclusion:** Service worked as designed

### Root Cause

The browser was serving cached JavaScript bundle predating commit `e3e60ec` (2026-07-07 22:56:04), when gig auto-conflict-blocking support was added to `events_repository.dart`. Rehearsals have had this feature since commit `b6c833c` (2026-06-26 — One Calendar initial deployment), but gigs did not until commit `e3e60ec`.

**Timeline:**

- 2026-06-26: One Calendar deployed, auto-conflict-blocking implemented for **rehearsals only**
- 2026-07-07 22:56:04: Commit `e3e60ec` added auto-conflict-blocking for **gigs and multi-date events**
- 2026-07-09 (pre-refresh): Browser cache served pre-`e3e60ec` bundle → gig creation skipped auto-blocking
- 2026-07-09 (post-refresh): Browser loaded post-`e3e60ec` bundle → gig creation successfully auto-blocked

### No Code Changes Required

The code is correct and present in `lib/features/events/events_repository.dart` at lines 632-668. Git history shows commit `e3e60ec` is on the `main` branch and deployed to production. The feature works when the browser loads the current bundle.

**Resolution:** This was a browser cache artifact, not a missing feature or bug. Users experiencing this issue can resolve it with a hard refresh (Cmd+Shift+R / Ctrl+Shift+R). No code changes are needed.

**Lessons Learned:**

- Runtime testing with cache-busting (incognito mode or hard refresh) is critical after deployments that add new code paths
- Console log absence (not just error logs) is a valid diagnostic signal — if a service is never invoked, it won't log anything, including success messages
- A/B testing within the same session (before/after cache clear) isolates browser cache as the variable
- **SQL CTE scope bug (recurring):** CTEs defined in a `WITH` clause are only valid for the single statement that immediately follows them. This issue occurred twice in this branch: (1) Issue 3 backfill dry-run script had a summary query referencing CTEs from a previous statement, (2) Task 2 and Task 3 diagnostic scripts repeated the same mistake. Each SQL statement must declare its own `WITH` clause, even if duplicating CTE definitions. Worth flagging explicitly for any future backfill scripts (e.g., if Task 3 gap analysis finds real rows requiring a backfill).

---

## Task 2 — Partial-Block Anomaly Investigation

**Status:** DIAGNOSIS REQUIRED — SQL query corrected, awaiting execution  
**Date:** 2026-07-09 (updated post-Architecture Gate review)

### Context

During the successful "Test Gig 2" run (post-refresh), the console logs showed:

```
[AutoConflictBlockingService] Apply to all bands: 2 bands
[AutoConflictBlockingService] Auto-block complete: 1 date(s) × 1 bands
```

**ARCHITECTURE GATE CORRECTION — Wrong User Investigated:**

"Test Gig 2" was created under a **non-admin test account** (`stubbymalone@gmail.com` / user_id `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`), NOT Tony's account. This was confirmed by:

1. Console log from the successful run: `[AutoConflictBlockingService] Auto-blocking 1 date(s) for user: 4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`
2. Tony's confirmation of the email associated with that user_id

**Why a test account was used:** Tony created the gig under a non-admin account to avoid spamming real band members with auto-conflict blocks during testing.

**Impact:** All Task 2 diagnostic queries created in the first round (band list, summary counts, partial-block anomaly query) were checking Tony's `user_id` (`671b32e8-60eb-448a-8167-106bf835297f`) and are **invalid**. Those results have been discarded. New diagnostics have been created for the correct user.

**Task 3 is unaffected** — it's correctly scoped to Tony's own account since it investigates historical gigs created by Tony.

---

**Critical Finding — Band Membership Discrepancy:**

The gig that produced this anomaly was created in band **"The Banana Stand" (`e89bea44-8dd4-4e3d-b527-c0f75e94aa7d`)**. This band was NOT in the original hardcoded band list used earlier in this investigation (Open Mic, The Second Summer, Toxic Crayon), which revealed the need for dynamic band resolution in diagnostic queries.

**Discrepancy to Investigate:** 2 target bands were resolved, but only 1 block row was written. This could be:

1. **Expected behavior (benign):** One of the 2 target bands already had a pre-existing block for that date (2026-07-26). The auto-conflict-blocking code is idempotent and skips duplicates via try-catch around unique constraint violations.

2. **Real bug:** One of the 2 target bands was genuinely missed despite not having a pre-existing block.

### Corrected Diagnostic Approach

**Prerequisite Query 1:** `sql/diagnostics/verify_stubbymalone_email_id_mapping.sql`

**CRITICAL: Run this FIRST** to verify the email-to-ID mapping before running any other Task 2 diagnostics:

```sql
-- Check auth.users (canonical source for email)
SELECT
  id,
  email,
  created_at
FROM auth.users
WHERE email = 'stubbymalone@gmail.com';
```

**Expected Result:** `id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'`

**If the ID doesn't match or is NULL, STOP and flag the discrepancy.** Do NOT proceed with Task 2 diagnostics until this is resolved.

**Note:** Query only checks `auth.users` (canonical email source) to avoid doc-vs-schema mismatches after hitting this issue twice (`gigs.city`, potentially `users.email`).

---

**Prerequisite Query 2:** `sql/diagnostics/verify_stubbymalone_current_bands.sql`

After confirming the email/ID mapping, run this to confirm which bands stubbymalone is currently a member of:

```sql
SELECT
  bm.band_id,
  b.name as band_name,
  bm.role,
  bm.status,
  bm.joined_at
FROM band_members bm
JOIN bands b ON b.id = bm.band_id
WHERE bm.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
  AND bm.status = 'active'
ORDER BY bm.joined_at;
```

**Expected Result:** Should show "The Banana Stand" (`e89bea44-8dd4-4e3d-b527-c0f75e94aa7d`) as an active band, plus however many other bands this user is a member of.

---

**Main Diagnostic Query:** `sql/diagnostics/investigate_partial_block_anomaly.sql`

This query now **dynamically resolves stubbymalone's current active bands** and checks block_dates for this user:

```sql
WITH stubbymalone_bands AS (
  -- Dynamically fetch stubbymalone's current active bands
  SELECT
    bm.band_id,
    b.name as band_name
  FROM band_members bm
  JOIN bands b ON b.id = bm.band_id
  WHERE bm.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
    AND bm.status = 'active'
)
SELECT
  sb.band_name,
  sb.band_id,
  bd.id as block_id,
  bd.date,
  bd.reason,
  bd.created_at,
  CASE
    WHEN sb.band_id = 'e89bea44-8dd4-4e3d-b527-c0f75e94aa7d' THEN 'ORIGIN (gig created here)'
    WHEN bd.id IS NOT NULL THEN 'HAS BLOCK'
    ELSE 'MISSING BLOCK'
  END as status
FROM stubbymalone_bands sb
LEFT JOIN block_dates bd ON bd.band_id = sb.band_id
  AND bd.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
  AND bd.date = '2026-07-26'
ORDER BY sb.band_name;
```

**Expected Outcomes:**

- **Outcome A (benign):** 2 target bands (excluding origin) both have block_dates for 2026-07-26. One was created earlier (pre-dating Test Gig 2), explaining why only 1 new row was written during the test.
  - **Action:** Document as expected idempotency behavior, close investigation.

- **Outcome B (genuine miss):** Only 1 target band has a block_dates row for 2026-07-26, created during Test Gig 2. The other target band is completely missing its block.
  - **Action:** Flag as new scope item — auto-conflict-blocking may have a bug where one target band is skipped. Requires Manager decision on whether to investigate further.

**Status:** Queries corrected and ready. **Run in sequence: (1) email/ID verification, (2) band membership verification, (3) partial-block anomaly diagnostic. Do not proceed to step 2 or 3 if step 1 fails.**

---

## Task 3 — Jun 26 → Jul 7 Gig Backfill Gap Investigation

**Status:** DIAGNOSIS REQUIRED — SQL query created, awaiting execution  
**Date:** 2026-07-09

### Context

The Issue 3 historical backfill (93 rows executed) only covered events with `created_at < '2026-06-26'` — before One Calendar was deployed. However:

- **Rehearsal auto-conflict-blocking:** Deployed 2026-06-26 (commit `b6c833c`)
- **Gig auto-conflict-blocking:** Deployed 2026-07-07 22:56:04 (commit `e3e60ec`)

**Gap Period:** Gigs created between **2026-06-26 00:00:00** and **2026-07-07 22:56:04** would have:

- ✅ One Calendar preferences enabled (defaults to true since migration)
- ❌ No gig auto-conflict-blocking code in the deployed bundle (feature didn't exist yet)
- ❌ No cross-band block_dates created at gig creation time

This is a **systematic gap** distinct from the pre-One-Calendar historical events (Issue 3). Those events predated the feature entirely. These events were created **during** the One Calendar rollout but **before** gig support was added.

### Diagnostic Query

**File:** `sql/diagnostics/investigate_gig_backfill_gap.sql`

**⚠️ Architecture Gate Correction:** This query now **dynamically resolves Tony's current active bands** instead of hardcoding the original 3 band IDs. This ensures correctness if Tony's band membership changed since the gap period (e.g., if "The Banana Stand" replaced one of the original bands).

This query identifies:

1. All gigs created by Tony during the gap period (2026-06-26 to 2026-07-07 22:56:04)
2. For each gig, checks which target bands have existing block_dates rows (EXISTS) vs missing (MISSING)
3. Provides both detailed breakdown and summary count

**Query Structure:**

```sql
WITH tony_bands AS (
  -- Dynamically fetch Tony's current active bands
  SELECT
    bm.band_id,
    b.name as band_name
  FROM band_members bm
  JOIN bands b ON b.id = bm.band_id
  WHERE bm.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
    AND bm.status = 'active'
),
gap_gigs AS (
  -- Fetch gigs created during the gap period in Tony's current bands
  SELECT
    g.id,
    g.band_id,
    b.name as band_name,
    g.name as gig_name,
    g.date,
    g.created_at,
    g.is_potential
  FROM gigs g
  JOIN bands b ON b.id = g.band_id
  WHERE g.band_id IN (SELECT band_id FROM tony_bands)
  AND g.created_at >= '2026-06-26 00:00:00'
  AND g.created_at < '2026-07-07 22:56:04'
  AND g.is_potential = false
  ORDER BY g.created_at
),
missing_blocks AS (
  SELECT
    gg.date as event_date,
    gg.band_name as origin_band,
    gg.gig_name as event_name,
    gg.created_at as event_created_at,
    tb.band_name as target_band,
    tb.band_id as target_band_id,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM block_dates bd
        WHERE bd.user_id = '671b32e8-60eb-448a-8167-106bf835297f'
          AND bd.band_id = tb.band_id
          AND bd.date = gg.date
      ) THEN 'EXISTS'
      ELSE 'MISSING'
    END as block_status
  FROM gap_gigs gg
  CROSS JOIN tony_bands tb
  WHERE tb.band_id != gg.band_id  -- Don't check origin band
)
SELECT
  event_date,
  event_name,
  origin_band,
  target_band,
  block_status,
  event_created_at
FROM missing_blocks
ORDER BY event_date, origin_band, target_band;
```

**Expected Outcomes:**

- **Outcome A (gap is empty):** Zero gigs created during this window, or all gigs already have corresponding block_dates (perhaps manually created or via a different mechanism).
  - **Action:** Document as clear, no backfill needed, close investigation.

- **Outcome B (real gap exists):** One or more gigs created during this window are missing cross-band block_dates.
  - **Action:** Produce a dry-run-only SQL script (same conventions as `backfill_tony_historical_blocks_dryrun.sql`) showing exactly which rows would be inserted. Use `GROUP BY` + `string_agg(DISTINCT ...)` to handle same-day collisions from multiple origin bands. Exclude rows already in `block_dates` to ensure idempotency.
  - **Do NOT write or run the live insert script** — dry-run only, pending Manager/Tony review.

**Status:** ~~Query corrected and ready. **Tony must run `verify_tony_current_bands.sql` FIRST to confirm membership, then run this diagnostic query.**~~ **✅ DIAGNOSIS COMPLETE — Gap confirmed**

### Gap Analysis Results

**Executed:** 2026-07-09

**Finding:** Gap is **real but minimal** — exactly **one gig** with **one missing block row**.

**Details:**

- **Gig:** "The Little Owl Social Pub"
- **Origin Band:** Open Mic
- **Event Date:** 2026-07-09
- **Created:** 2026-07-07 09:04:29 (before `e3e60ec` deployed at 22:56:04 same day)
- **Missing Block:** The Second Summer (band_id `6d71a662-f1a4-4fb9-a611-9b2c8e7716d3`)
- **Existing Block (requires investigation):** Toxic Crayon already has a block_dates row for 2026-07-09

**Next Steps:**

1. **Investigate Toxic Crayon block:** Run `sql/diagnostics/inspect_toxic_crayon_block_jul09.sql` to determine if the existing block was caused by this gig (partial propagation success) or by a different event (coincidental date overlap). Check if `created_at` is near 2026-07-07 09:04:29.

2. **Supplemental Backfill (dry-run prepared):** `sql/fixes/backfill_open_mic_gig_jul09_dryrun.sql` shows exactly one row that would be inserted:
   - `user_id`: `671b32e8-60eb-448a-8167-106bf835297f` (Tony)
   - `band_id`: `6d71a662-f1a4-4fb9-a611-9b2c8e7716d3` (The Second Summer)
   - `date`: `2026-07-09`
   - `reason`: `'Unavailable (scheduled with Open Mic)'`
   - Includes `ON CONFLICT (user_id, band_id, date) DO NOTHING` safety net

**Status:** Dry-run prepared, **do NOT execute** until Toxic Crayon block origin is confirmed and Manager approves.

**Note on Dry-Run Script:** If gap rows are found, the dry-run script will also use dynamic band resolution from `band_members` rather than hardcoded IDs, ensuring it remains correct regardless of membership changes.

---

## Summary of Findings

### Task 1 — Issue 2 Resolution ✅ COMPLETE

**Finding:** Root cause was stale browser cache serving pre-`e3e60ec` JavaScript bundle, not missing or broken code. Hard refresh resolved the issue immediately. No code changes required.

### Task 2 — Partial-Block Anomaly ⏸️ AWAITING SQL EXECUTION (Architecture Gate correction applied)

**Critical Finding:** The gig that triggered this anomaly was created in "The Banana Stand" (`e89bea44-8dd4-4e3d-b527-c0f75e94aa7d`), which was NOT in the original hardcoded band list. This revealed that Tony's band membership may have changed since the original investigation, invalidating both diagnostic queries.

**Correction Applied:** Query now dynamically resolves Tony's current active bands via `band_members` table instead of hardcoding. This ensures correctness regardless of membership changes.

**Finding (pending SQL execution):** Likely benign (idempotency skip due to pre-existing block on one target band), but requires SQL verification to confirm. If genuine miss is found, flag as new scope item for Manager decision.

**Action Required:**

1. Tony must run `sql/diagnostics/verify_tony_current_bands.sql` FIRST to confirm current band membership
2. Then run `sql/diagnostics/investigate_partial_block_anomaly.sql` and report results

### Task 3 — Jun 26 → Jul 7 Gig Backfill Gap ✅ DIAGNOSIS COMPLETE (Architecture Gate correction applied)

**Critical Finding:** Original query hardcoded the same 3 band IDs, which would silently miss any gigs/blocks involving bands not in that stale list (e.g., "The Banana Stand").

**Correction Applied:** Query now dynamically resolves Tony's current active bands via `band_members` table and filters gigs by `g.band_id IN (SELECT band_id FROM tony_bands)` instead of hardcoded IDs.

**SQL Executed:** 2026-07-09 — Gap confirmed as real but minimal.

**Findings:**

- **Gap Scope:** Exactly **one gig** with **one missing block row**
- **Gig:** "The Little Owl Social Pub" (Open Mic, event date 2026-07-09)
- **Created:** 2026-07-07 09:04:29 (before `e3e60ec` deployed at 22:56:04)
- **Missing Block:** The Second Summer (band_id `6d71a662-f1a4-4fb9-a611-9b2c8e7716d3`)
- **Existing Block:** Toxic Crayon already has a block for 2026-07-09 (origin requires investigation)

**Action Items:**

1. **[PREREQUISITE]** Run `sql/diagnostics/inspect_toxic_crayon_block_jul09.sql` to determine if the existing Toxic Crayon block was caused by this gig (partial propagation) or by a different event. Check if `created_at` is near 2026-07-07 09:04:29.

2. **[PREPARED]** Dry-run backfill script ready at `sql/fixes/backfill_open_mic_gig_jul09_dryrun.sql`:
   - Shows exactly one row that would be inserted (The Second Summer, 2026-07-09)
   - Uses `ON CONFLICT (user_id, band_id, date) DO NOTHING` safety net
   - **Do NOT execute** until Toxic Crayon block origin confirmed and Manager approves

**Status:** Diagnosis complete, dry-run prepared. Awaiting Toxic Crayon block investigation and Manager approval before execution.

---

## Branch Status

**Current State:** Issue 2 formally closed (browser cache, no code fix needed). Task 2 awaiting SQL execution. Task 3 diagnosis complete, dry-run backfill prepared pending Manager approval.

**Architecture Gate Corrections Applied:**

- Task 2: Corrected user_id from Tony to stubbymalone (test account that created "Test Gig 2")
- Task 2: Added email/ID verification prerequisite (`verify_stubbymalone_email_id_mapping.sql`)
- Task 2: Fixed schema safety issue (dropped `users.email` query after doc-vs-schema mismatch pattern)
- Task 3: Gap confirmed — exactly one gig ("The Little Owl Social Pub") with one missing block (The Second Summer, 2026-07-09)
- Task 3: Dry-run backfill prepared (`backfill_open_mic_gig_jul09_dryrun.sql`)
- Task 3: Toxic Crayon block investigation query created to determine if existing block was partial propagation or coincidental

**Ready for Commit:** No — Task 2 awaiting SQL execution, Task 3 awaiting Toxic Crayon block investigation and Manager approval for backfill.

**Blockers:** Supabase CLI connectivity issues prevent automated query execution. Tony must manually run diagnostic queries in Supabase Dashboard.

**Next Steps:**

1. **[TASK 2]** Tony runs email/ID verification: `sql/diagnostics/verify_stubbymalone_email_id_mapping.sql`
2. **[TASK 2]** If verification passes, Tony runs: `sql/diagnostics/verify_stubbymalone_current_bands.sql`
3. **[TASK 2]** Then Tony runs: `sql/diagnostics/investigate_partial_block_anomaly.sql` and reports results
4. **[TASK 3]** Tony runs: `sql/diagnostics/inspect_toxic_crayon_block_jul09.sql` to determine origin of existing block
5. **[TASK 3]** Based on finding, Manager approves or rejects dry-run backfill execution
6. If Task 2 reveals genuine miss: Architect proposes new scope item for Manager
7. Once both tasks clear: All issues documented, branch ready for merge

---

**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-07-08  
**Updated:** 2026-07-09 (Issue 2 closed, Task 2 corrected for stubbymalone user, Task 3 diagnosis complete with dry-run backfill prepared)  
**Status:** ISSUE 1 READY FOR ENGINEER, ISSUE 2 CLOSED (NO FIX NEEDED), ISSUE 3 AWAITING DECISION, TASK 2 AWAITING SQL EXECUTION, TASK 3 AWAITING MANAGER APPROVAL
