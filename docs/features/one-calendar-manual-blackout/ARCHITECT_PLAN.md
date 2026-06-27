# ARCHITECT_PLAN.md
## Feature Slug
`bug/one-calendar-manual-blackout`

---

## Problem Summary

With One Calendar enabled, manually created blackout dates in Band A do not appear in
Band B. Gig-created blockouts propagate correctly — the manual creation path does not.

**Reproduction:**
1. Enable One Calendar in Settings.
2. Open Band A → manually add 2 blockout dates.
3. Switch to Band B → those blockout dates are absent.

**Expected:** Manual blockouts propagate to all other bands (consistent with gig-created
blockouts) when One Calendar is on. No propagation when One Calendar is off.

---

## Root Cause

**Confidence: HIGH — confirmed via direct code reading.**

The live path for manual blockout creation is `event_editor_drawer.dart._saveBlockOut()`
(lines 1021–1108). This method:

1. Creates the blockout for `widget.bandId` only.
2. Refreshes the calendar for `widget.bandId`.
3. Shows a success snackbar.
4. Returns — **no One Calendar propagation step exists.**

A second file, `lib/features/calendar/widgets/add_block_out_drawer.dart`, contains correct
One Calendar propagation code. However, **this file is dead code** — it is never imported
or referenced anywhere in the codebase. It has no callers. The `EventEditorDrawer` in
`lib/features/events/widgets/event_editor_drawer.dart` is the sole live path for manual
blockout creation.

The gig-creation path (`events_repository.dart` lines 631–656) calls
`AutoConflictBlockingService.autoBlockConflictingDate()` which correctly writes blockout
rows into every other band. That service uses the identical underlying
`BlockOutRepository.createBlockOut()` call, confirming that cross-band writes are
structurally possible and not blocked by RLS.

**Failure mode:** Primary write path missing — the event editor never calls the propagation
path at all.

---

## Reference Docs Consulted

No dedicated calendar reference exists under `docs/reference/`. The following files were
read in full during investigation:

- `docs/reference/architecture/database_schema.md`
- `docs/reference/architecture/supabase_functions.md`
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`
- `supabase/migrations/20260626005216_add_user_calendar_preferences.sql`
- `supabase/migrations/20260626010000_fix_calendar_preferences_rpc.sql`
- `supabase/migrations/20260128210000_notification_triggers.sql`

---

## Existing System Analysis

### Data model

`block_dates` table columns: `id, user_id, band_id, date (DATE), reason (TEXT NOT NULL),
created_at, updated_at`. Unique constraint: `(user_id, band_id, date)`.

Each row is scoped to a single `(user_id, band_id)` pair. Cross-band sharing is
implemented by writing **one row per target band** — not by using a shared row or a
null `band_id`.

### One Calendar preferences

`user_calendar_preferences` table:
- `one_calendar_enabled` (default `true`) — master toggle controlling manual blockout
  propagation and calendar unification.
- `auto_block_conflicts_enabled` (default `true`) — separate toggle controlling whether
  gig/rehearsal creation auto-blocks dates on other bands.
- `apply_to_mode` (`all_bands` / `selected_bands`) — controls which bands receive
  propagated blockouts.

RPC: `get_or_create_calendar_preferences()` — SECURITY DEFINER, no parameters, uses
`auth.uid()`. Deployed in migration `20260626010000`.

Client method: `OneCalendarPreferencesRepository.getBandIdsToApplyBlockOut(userBandIds)`
— returns the list of target bands for propagation. Returns `[]` if
`one_calendar_enabled = false`. Returns `userBandIds` in `all_bands` mode. Returns the
intersection of `selectedBandIds` and `userBandIds` in `selected_bands` mode.

### Gig flow (reference — WORKS)

`events_repository.dart` (lines 631–656) → `AutoConflictBlockingService.autoBlockConflictingDate()`:
1. Checks `prefs.oneCalendarEnabled && prefs.autoBlockConflictsEnabled` (both required).
2. Fetches all band IDs from `band_members` for the current user (no status filter).
3. Calls `getBandIdsToApplyBlockOut(userBandIds)` to get propagation targets.
4. Removes `eventBandId` from the target list.
5. Calls `_blockOutRepository.createBlockOut(bandId: otherBandId, ...)` for each.

### Manual blockout flow (BROKEN)

`event_editor_drawer.dart._saveBlockOut()` (lines 1021–1086):
1. Creates blockout for `widget.bandId` only.
2. Calls `calendarProvider.invalidateAndRefresh(bandId: widget.bandId)`.
3. Returns — **no propagation**.

### Calendar display layer

`CalendarNotifier._loadEventsForBand(bandId)` queries:
```dart
supabase.from('block_dates').select().eq('band_id', bandId).order('date');
```
This is correct. Once rows with `band_id = Band B ID` exist in `block_dates`, they
will appear on Band B's calendar. The display layer requires no changes.

### RLS on `block_dates`

The gig flow proves cross-band INSERT is already permitted by RLS — both flows use the
identical `BlockOutRepository.createBlockOut()` path. No RLS changes are required.

---

## Proposed Solution

**Minimal scope: modify `_saveBlockOut()` in `event_editor_drawer.dart` only.**

After the primary blockout is created (for `widget.bandId`), add a One Calendar
propagation block that mirrors the pattern from `add_block_out_drawer.dart` (the dead
file). Specifically:

1. Read `oneCalendarPreferencesRepositoryProvider`.
2. Read `activeBandProvider` to get `userBands` (all active bands for the user).
3. Call `getBandIdsToApplyBlockOut(userBandIds)` — returns `[]` when One Calendar is
   off, so the `if (off)` case is handled implicitly.
4. Remove `widget.bandId` from the target list.
5. For each remaining band ID, call `repository.createBlockOut(...)`.
6. Wrap in try-catch (non-blocking — must not fail the primary save).

Two new imports are required in `event_editor_drawer.dart`:
- `package:bandroadie/features/calendar/one_calendar_preferences_repository.dart`
- `package:bandroadie/features/bands/active_band_controller.dart`

**What must not change:**
- The primary `createBlockOut()` call for `widget.bandId`.
- The calendar refresh call immediately after.
- `_deleteBlockOut()` — see Edge Cases below.
- `AutoConflictBlockingService` — not touched.
- `BlockOutRepository` — not touched.
- `add_block_out_drawer.dart` — leave as-is (dead code cleanup is out of scope).

---

## Database Impact

**Migration: not required.**

All tables, RPCs, and indexes needed already exist:
- `block_dates` — pre-existing.
- `user_calendar_preferences` — created in `20260626005216`.
- `get_or_create_calendar_preferences()` RPC — created in `20260626010000`.
- `getBandIdsToApplyBlockOut()` client method — exists in repository.

RLS policies on `block_dates` — no changes needed. Cross-band INSERT already works
(confirmed by gig propagation path).

---

## Flutter Architecture Changes

| Component | Change |
|-----------|--------|
| `EventEditorDrawer` (ConsumerStatefulWidget) | `_saveBlockOut()` — add propagation block after primary write |
| `OneCalendarPreferencesRepository` | No change — called via existing provider |
| `ActiveBandState.userBands` | No change — read via `ref.read(activeBandProvider)` |
| `BlockOutRepository.createBlockOut()` | No change — called with target band IDs |
| `CalendarNotifier` | No change — display path already correct |

State management: No new providers, notifiers, or state objects. The propagation block
uses `ref.read()` (fire-once, inside a save handler) — correct per Flutter/Riverpod
lifecycle rules.

---

## Files to Create

None.

---

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/events/widgets/event_editor_drawer.dart` | Add 2 imports; add One Calendar propagation block inside `_saveBlockOut()` after the primary `createBlockOut()` call |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/calendar/widgets/add_block_out_drawer.dart` | Dead code — no callers. Leave as-is; cleanup is out of scope |
| `lib/features/calendar/auto_conflict_blocking_service.dart` | Gig path — works correctly, must not change |
| `lib/features/calendar/block_out_repository.dart` | Repository is correct — no change needed |
| `lib/features/calendar/one_calendar_preferences_repository.dart` | Repository is correct — no change needed |
| `supabase/migrations/*` | No database changes required |
| `lib/main.dart` | Init order must not change |

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Calendar / Block Dates | affected (write path only — `_saveBlockOut`) |
| Platform (iOS / Android / Web / macOS) | affected (same Flutter code path on all platforms) |

---

## Regression Risk

**LOW**

- Single method modified in one file.
- No new abstractions, providers, or database objects.
- Propagation block is wrapped in a non-blocking try-catch — failure cannot break the
  primary save.
- No auth, routing, or init order involved.
- Only blockout creation is affected; gig creation, rehearsal creation, and all other
  event operations are unchanged.
- `getBandIdsToApplyBlockOut()` returns `[]` when One Calendar is off, so the off-case
  is a no-op with no additional writes or side effects.

---

## Engineer Task Breakdown

Tasks must be completed in order.

**Task 1 — Add imports to `event_editor_drawer.dart`**

Add to the existing import block (maintain alphabetical grouping):
```dart
import '../../bands/active_band_controller.dart';
import '../../calendar/one_calendar_preferences_repository.dart';
```

**Task 2 — Add One Calendar propagation to `_saveBlockOut()`**

Location: `event_editor_drawer.dart`, inside `_saveBlockOut()`, immediately after the
closing brace of the `if (_isEditMode ...) { ... } else { ... }` block (currently
at approximately line 1086), and **before** the `ref.read(calendarProvider.notifier)
.invalidateAndRefresh(...)` call.

Insert the following block verbatim:

```dart
      // One Calendar propagation: if enabled, replicate blockout to other bands.
      // Wrapped in try-catch — must not fail the primary save.
      try {
        final prefsRepo = ref.read(oneCalendarPreferencesRepositoryProvider);
        final userBandIds = ref
            .read(activeBandProvider)
            .userBands
            .map((b) => b.id)
            .toList();
        final bandIds =
            await prefsRepo.getBandIdsToApplyBlockOut(userBandIds);
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

**Important:** Do not change any surrounding code. The `repository` variable is already
declared at line 1061. The `userId` variable is already declared at line 1056. The
`_selectedDate`, `_blockOutUntilDate`, and `_notesController` are already in scope.

**Task 3 — Verify with `flutter analyze`**

Run `flutter analyze` and confirm 0 errors before reporting complete.

---

## Verification Plan

### Tier 1 — Pre-deployment (no schema changes required for this fix)

No SQL migrations are deployed for this fix. Tier 1 SQL tests are not applicable.

**Code-level pre-check (run before testing in-app):**

```
-- PRE-DEPLOY TEST 1: Confirm get_or_create_calendar_preferences RPC exists
SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'get_or_create_calendar_preferences';
-- Expected: 1 row

-- PRE-DEPLOY TEST 2: Confirm user_calendar_preferences table exists with expected columns
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_calendar_preferences'
ORDER BY ordinal_position;
-- Expected: id, user_id, one_calendar_enabled (true default), apply_to_mode (all_bands default),
--           selected_band_ids, auto_block_conflicts_enabled (true default), created_at, updated_at

-- PRE-DEPLOY TEST 3: Confirm block_dates table allows INSERT for current user in multiple bands
-- (Manual verification — confirm user is an active member of at least 2 bands)
SELECT bm.band_id, bm.status
FROM band_members bm
WHERE bm.user_id = auth.uid()
  AND bm.status = 'active';
-- Expected: 2+ rows for the test user
```

### Tier 2 — Post-deployment (after code is deployed / hot-reloaded)

```
-- POST-DEPLOY TEST 1: Confirm flutter analyze passes
-- Run: flutter analyze
-- Expected: 0 errors

-- POST-DEPLOY TEST 2: Functional — manual blockout propagation (happy path)
-- 1. Enable One Calendar → All Bands in Settings.
-- 2. Open Band A calendar.
-- 3. Tap a date → Add Block Out → save.
-- 4. Switch to Band B → open same date on calendar.
-- Expected: blockout for the current user appears on Band B's calendar.

-- POST-DEPLOY TEST 3: One Calendar OFF — no propagation
-- 1. Disable One Calendar in Settings.
-- 2. Open Band A calendar → Add Block Out → save.
-- 3. Switch to Band B → check same date.
-- Expected: blockout does NOT appear on Band B's calendar.

-- POST-DEPLOY TEST 4: Database verification after test 2
-- (Run in Supabase SQL editor after the happy-path manual test)
SELECT band_id, user_id, date, reason
FROM block_dates
WHERE user_id = '<test-user-id>'
ORDER BY date, band_id;
-- Expected: rows for both Band A ID and Band B ID for the created date.

-- POST-DEPLOY TEST 5: Confirm propagated row has correct band_id
SELECT COUNT(*) AS propagated_count
FROM block_dates
WHERE user_id = '<test-user-id>'
  AND band_id = '<band-b-id>'
  AND date = '<test-date>';
-- Expected: 1 (or more if multi-day range was created)
```

---

## QA Regression Areas

1. **Manual blockout creation — primary path**: Create a blockout in Band A; confirm it
   appears in Band B with One Calendar on.
2. **One Calendar off**: Create blockout in Band A; confirm it does NOT appear in Band B.
3. **Selected bands mode**: Set One Calendar to "Selected bands only", exclude Band B;
   confirm blockout does not propagate to Band B.
4. **Multi-day range**: Create a 3-day blockout in Band A; confirm all 3 dates appear
   in Band B.
5. **Gig propagation regression**: Create a gig in Band A; confirm blockout still
   appears in Band B (gig path must be unaffected).
6. **Primary save not broken**: If propagation fails (e.g., test user removed from Band B
   mid-session), the blockout must still be saved in Band A and the success message shown.
7. **Edit mode**: Edit an existing blockout in Band A; the propagated copy in Band B
   should not be automatically synced (see Out of Scope — document the known limitation).
8. **Delete**: Delete a blockout in Band A; confirm blockout in Band B is not deleted
   (current behavior — delete is scoped to current band only, see Out of Scope).
9. **RBAC — contributor**: Contributor attempting to create a blockout should still be
   blocked by the existing RBAC guard in `_saveBlockOut()`.
10. **`flutter analyze`**: 0 errors after change.

---

## Rollout / Migration Strategy

No database migration. The change is Flutter-only. Standard deployment applies:
1. Merge to `main`.
2. Run `./tools/deploy_web.sh` for web.
3. Native builds pick up the change at next build/submission.
4. No data backfill needed — existing manual blockouts are already band-scoped; they
   will not be retroactively propagated. Only new blockouts created after the fix go
   through the propagation path.

---

## Edge Cases

### Delete across bands

`_deleteBlockOut()` in `event_editor_drawer.dart` deletes only from `widget.bandId`.
If a user created a blockout in Band A (which propagated to Band B), deleting it in
Band A does NOT remove the copy in Band B.

**Expected behaviour (current, accepted for this bug fix):** Each band's copy is
independent after creation. Deleting from Band A leaves Band B's copy intact.

**Rationale:** The acceptance criteria covers propagation on creation only. Delete
behaviour parity is a follow-on feature request and is explicitly Out of Scope here.

**If future cross-band delete is required**, `_deleteBlockOut()` should be updated
to: (a) check `oneCalendarEnabled`; (b) if enabled, show a dialog offering "This band
only" vs "All bands"; (c) if "All bands", iterate `getBandIdsToApplyBlockOut()` and
call `deleteBlockOutSpan()` for each. The dead-code `add_block_out_drawer.dart`
contains a reference implementation of this dialog pattern at lines 317–359.

### Edit mode across bands

The edit path (delete old span → create new span) currently updates only the current
band. The propagated copies in other bands are not updated on edit. This is a known
gap. Out of scope for this fix.

### `add_block_out_drawer.dart` (dead code)

This file contains a complete, correct implementation of the One Calendar blockout
drawer including both propagation and cross-band delete. It was written but never wired
into the app. It should not be deleted or wired up as part of this fix (doing so would
require routing/navigation changes). A separate cleanup task can remove this file or
promote it to production in a future iteration.

---

## Out of Scope

- Cross-band delete propagation (`_deleteBlockOut()` change).
- Cross-band edit synchronisation (edit mode updating propagated copies).
- Retroactive backfill of existing manual blockouts.
- Removing or wiring up `add_block_out_drawer.dart`.
- Any changes to the gig propagation path (`AutoConflictBlockingService`).
- Any new notification triggers for propagated blockouts.
