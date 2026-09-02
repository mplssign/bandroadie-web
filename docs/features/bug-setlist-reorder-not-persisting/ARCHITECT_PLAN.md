# ARCHITECT PLAN — bug/setlist-reorder-not-persisting

| Field | Value |
|---|---|
| **Feature Slug** | `bug-setlist-reorder-not-persisting` |
| **Branch** | `bug/setlist-reorder-not-persisting` |
| **Type** | Bug |
| **Date** | 2026-09-02 |
| **Platforms affected** | iOS (confirmed TestFlight, v26.8.29); likely all platforms |

---

## Problem Summary

When a user manually drags songs to a new order in a non-Catalog setlist, the new order is not
saved to the database. Navigating away and back returns the original pre-drag order. Confirmed by
TestFlight feedback from me.vesel@gmail.com on the "Future Songs" setlist (10 songs, iPhone 14 SE,
iOS 26.3).

---

## Root Cause

**Confidence: HIGH** — confirmed by tracing the full call chain in source code.

`SetlistDetailScreen.initState()` calls `loadSetlist()` with `forceReload: true`
unconditionally. This causes a fresh Supabase DB fetch (`loadSongs()`) every single time the
setlist detail screen widget is created — including when the user navigates back to the same setlist
they just left.

When the user drags and then backs out before the 500 ms debounce timer fires, `dispose()` fires
`unawaited(persistItemReorder())` to flush the in-flight persist. The new screen is simultaneously
initialised, schedules `loadSetlist(forceReload: true)` in a `WidgetsBinding.addPostFrameCallback`,
and issues a DB SELECT. These two async operations — the persist HTTP call and the reload HTTP call
— race. The SELECT can return (with old positions) before the RPC WRITE commits, so the freshly
loaded state overwrites the in-progress optimistic state with stale data from the DB.

Even if the user waits for the debounce to fire before backing out, the `forceReload: true` on
return still wins the race against the persist call that is already in-flight.

### Supporting evidence

```
// setlist_detail_screen.dart  ~line 143
WidgetsBinding.instance.addPostFrameCallback((_) {
  ref.read(setlistDetailProvider.notifier).loadSetlist(
        widget.setlistId,
        widget.setlistName,
        forceReload: true,          // ← races with in-flight persist
      );
});
```

```
// dispose() ~line 194 — called when user backs out
if (_reorderDebounceTimer != null && _reorderDebounceTimer!.isActive) {
  _reorderDebounceTimer!.cancel();
  ...
  unawaited(                         // ← fire-and-forget; racing with above
    ref.read(setlistDetailProvider.notifier).persistItemReorder(),
  );
}
```

The `setlistDetailProvider` is a **non-autoDispose** `NotifierProvider`, so its state (including
the reordered `items`) persists across screen navigations. The custom `state` setter updates
`_cachedState` on every mutation. `loadSetlist(forceReload: false)` already short-circuits when
the same setlist ID is already loaded, returning the cached state without hitting the DB.

---

## Existing System Analysis

### Persist path (non-Catalog, e.g., "Future Songs")

| Layer | What happens |
|---|---|
| UI drag | `_handleItemReorder(oldIndex, newIndex)` → `reorderItemsLocal()` updates `state.items` optimistically |
| Debounce | 500 ms `Timer`; callback guards `if (!mounted) return;` |
| `dispose()` flush | If timer still active: cancel + `unawaited(persistItemReorder())` |
| `persistItemReorder()` | Reads `state.items.map((i) => i.id)` — these are `setlist_songs.id` UUIDs (confirmed: `SetlistItem.id` is the row ID, not `songs.id`) |
| `specialItemRepo.reorderItems()` | Calls `reorder_setlist_items` RPC with `p_row_ids` (correct param name, correct ID type) |
| `reorder_setlist_items` RPC | Validates row ownership, two-phase position update, returns `{success: true}` |

The persist path for non-Catalog is **correct end-to-end**. The RPC, IDs, and param names are
all right. The bug is not in the persist logic — it is in `forceReload: true` wiping the cached
(correctly reordered) state and reloading from DB before the persist can commit.

### Persist path (Catalog)

`persistReorder()` calls `reorderSongs()` with `p_song_ids` instead of `p_row_ids` (parameter
name mismatch — function signature is `reorder_setlist_songs(p_setlist_id uuid, p_row_ids uuid[])`).
This causes the RPC call to fail with PostgreSQL error `42883` (function not found for that
signature). The code catches `42883` and falls back to `_reorderSongsFallback()`, which performs
direct two-phase `UPDATE setlist_songs SET position = ? WHERE setlist_id = ? AND song_id = ?`.
The fallback is correct for the Catalog because it matches by `song_id` (the `songs.id` FK, which
is what `SetlistSong.id` maps to). Catalog reorder **does persist**, just via the fallback path with
spurious error logs. This is a secondary issue, addressed in the Out-of-Scope section.

### `loadSetlist()` cache behaviour

```dart
void loadSetlist(String id, String name, {bool forceReload = false}) {
  if (_setlistId == id && !forceReload) {
    // ← returns cached _cachedState immediately; no DB fetch
    return;
  }
  ...
  state = SetlistDetailState(setlistId: id, setlistName: name, isLoading: true);
  Future.microtask(() => loadSongs());
}
```

With `forceReload: false`, every state write flows through the overridden `set state(...)` which
keeps `_cachedState` up-to-date. Navigating back to the same setlist returns the cached state — which
already has the new song order — without touching the DB.

---

## Proposed Solution

**Change `forceReload: true` to `forceReload: false`** in `SetlistDetailScreen.initState()`.

### Why this is the minimal correct fix

`loadSetlist` already handles all reload scenarios correctly when `forceReload` is false:

| Scenario | Behaviour with `forceReload: false` |
|---|---|
| First ever open of any setlist | `_setlistId == null != widget.setlistId` → full reload ✓ |
| Navigate back to same setlist | `_setlistId == widget.setlistId` → cached state (fixes the bug) ✓ |
| Navigate from setlist A to setlist B | `_setlistId == A.id != B.id` → reload B ✓ |
| Navigate B → A | `_setlistId == B.id != A.id` → reload A (any prior persist long finished) ✓ |
| Band switch | `build()` clears `_setlistId` / state; next open reloads ✓ |
| Song added/removed on screen | Explicit `loadSongs()` calls in mutation handlers remain unchanged ✓ |
| App restart | Provider re-initialises; `_setlistId = null`; next open reloads ✓ |

No scenario loses fresh data that it currently has. The only change is that a *same-setlist
round-trip* no longer discards the correctly reordered in-memory state.

---

## Database Impact

**Not applicable.** No schema, RPC, policy, trigger, migration, or edge function changes are
required. The `reorder_setlist_items` RPC, `setlist_songs` positions, and all RLS policies are
correct as deployed.

---

## Flutter Architecture Changes

| Change | File | Detail |
|---|---|---|
| `forceReload: true` → `forceReload: false` | `lib/features/setlists/setlist_detail_screen.dart` | Single keyword change in `initState` |

No new providers, controllers, repositories, models, or widgets are introduced.

No changes to `setlist_detail_controller.dart`, `special_item_repository.dart`,
`setlist_repository.dart`, or any other file.

---

## Files to Create

None.

---

## Files to Modify

| File | Change |
|---|---|
| `lib/features/setlists/setlist_detail_screen.dart` | Line ~149: `forceReload: true,` → `forceReload: false,` |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/features/setlists/setlist_detail_controller.dart` | Persist logic (both paths) is correct; do not touch |
| `lib/features/setlists/setlist_repository.dart` | Fallback path works; param name fix is out of scope (see below) |
| `lib/features/setlists/special_item_repository.dart` | RPC call is correct; no changes needed |
| All Supabase migrations | No DB changes required |
| All other feature files | Not in scope |

---

## System Impact Map

| System | Status | Notes |
|---|---|---|
| Setlists (non-Catalog) | **Affected** | Bug fix; same-setlist re-navigation uses cached state |
| Setlists (Catalog) | **Affected** | Same fix applies; Catalog reorder already worked via fallback |
| Gigs | Unaffected | |
| Rehearsals | Unaffected | |
| Members / Auth / Routing | Unaffected | |
| Notifications | Unaffected | |
| Platforms (iOS / Android / macOS / web) | All platforms benefit; no platform-conditional code touched |

---

## Regression Risk

**LOW.**

- One keyword changed in one non-critical path.
- The `loadSetlist` method's existing `_setlistId != id` guard already provides a reload for new
  setlists, band switches, and app restarts.
- Explicit `loadSongs()` calls in all mutation handlers (add song, delete song, move song) are
  unaffected.
- No auth, session, routing, init-order, or DB logic is touched.

---

## Engineer Task Breakdown

> Execute in order; each task is atomic and independently testable.

1. **In `lib/features/setlists/setlist_detail_screen.dart` `initState()`**, change:
   ```dart
   forceReload: true,
   ```
   to:
   ```dart
   forceReload: false,
   ```
   That is the complete code change.

2. **Run `flutter analyze`** — confirm zero new warnings or errors.

3. **Smoke test on device / simulator** (see Verification Plan Tier 2 below).

4. **Commit** with message:  
   `fix(setlists): use cached state on re-navigation to stop reorder race`

---

## Verification Plan

### Tier 1 — Pre-deploy (read-only SQL, no side effects)

Confirm the `reorder_setlist_items` function has correct grants and will accept authenticated calls.
Run from Supabase SQL editor (read-only `SELECT`):

```sql
-- Verify function exists with expected signature
SELECT
  p.proname              AS fn_name,
  pg_get_function_arguments(p.oid) AS signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('reorder_setlist_items', 'reorder_setlist_songs');
-- Expected: both rows present; signature = "p_setlist_id uuid, p_row_ids uuid[]"

-- Verify 'authenticated' role can execute
SELECT
  has_function_privilege(
    'authenticated',
    'public.reorder_setlist_items(uuid, uuid[])',
    'EXECUTE'
  ) AS items_ok,
  has_function_privilege(
    'authenticated',
    'public.reorder_setlist_songs(uuid, uuid[])',
    'EXECUTE'
  ) AS songs_ok;
-- Expected: both true
```

### Tier 2 — Post-deploy device tests

**Test A — Normal reorder (timer fires while on screen):**
1. Open any non-Catalog setlist with ≥3 songs.
2. Drag song from position 1 to position 3 using the grip handle.
3. Wait 600 ms (debounce + buffer).
4. Press Back.
5. Immediately re-open the same setlist.
6. **Assert**: songs appear in the dragged order. ✓

**Test B — Quick-back reorder (back before debounce fires):**
1. Open the same setlist.
2. Drag a different song to a new position.
3. Press Back within 300 ms (before the 500 ms debounce fires).
4. Wait 2 seconds (allow `unawaited` persist to complete).
5. Re-open the same setlist.
6. **Assert**: songs appear in the dragged order. ✓  
   *(Debug mode: confirm `[SetlistDetail] ✓ Persisted reorder successfully` in console.)*

**Test C — Cross-setlist navigation (ensures fresh reload still works):**
1. Open setlist A; drag songs.
2. Wait 600 ms. Press Back.
3. Open setlist B; verify its order is independent.
4. Press Back. Re-open setlist A.
5. **Assert**: setlist A still shows the order from step 1. ✓  
   *(This navigation triggers a reload of A since B was loaded in between.)*

**Test D — Catalog setlist (verify existing fallback unaffected):**
1. Open the Catalog.
2. Verify songs display correctly (Catalog uses songs-only path; cannot drag-reorder in Catalog).
3. **Assert**: no regressions in Catalog display. ✓

**Test E — App restart persistence:**
1. Reorder a setlist, wait 600 ms, press Back.
2. Kill and re-launch the app.
3. Re-open the setlist.
4. **Assert**: new order persists (loaded from DB). ✓

---

## QA Regression Areas

- Setlist detail screen rendering on first launch after install.
- Opening a setlist immediately after switching bands.
- Adding a song to a setlist and verifying the song appears at the end.
- Deleting a song and verifying the remaining songs are correctly ordered.
- Set break / pause insertion and ordering.
- Tuning-group sort mode toggle (non-Catalog).

---

## Rollout Strategy

1. Merge to `main` after code review.
2. Deploy as part of the next regular release build (no special deployment needed — Flutter-only change).
3. Monitor TestFlight / Crashlytics for any regression reports; the change is trivially reversible
   (one keyword).

---

## Out of Scope

### Secondary issue: `reorderSongs()` RPC parameter name mismatch

`SetlistRepository.reorderSongs()` calls `reorder_setlist_songs` with `p_song_ids` instead of
`p_row_ids`. This is a **pre-existing defect** that does not affect the reported bug:

- The failure mode is `42883` → caught → fallback path → correct two-phase `UPDATE` using `song_id`
  matching → Catalog reorder *does* persist.
- Fixing the param name alone would **break** the Catalog path because `persistReorder()` passes
  `songs.id` values (from `SetlistSong.id`) while the RPC validates against `setlist_songs.id` (row
  UUIDs). A correct RPC call requires `setlist_songs.id` row UUIDs, which `SetlistSong` does not
  currently carry.
- The full fix for the Catalog path (if needed) would require: (a) adding a `rowId` field to
  `SetlistSong` populated from `setlist_songs.id` at fetch time, AND (b) correcting the param name
  in `reorderSongs()`. This is a separate, larger change and is out of scope here.
- **Recommended action**: leave the Catalog path as-is (fallback works). File a separate tech-debt
  ticket to align `persistReorder()` with the items path pattern.

### Stale data from concurrent external modifications

If another device/user modifies the setlist while the user is viewing it, `forceReload: false`
means the local user will not see those changes until they navigate away and back. This was also
true before this fix (no polling or realtime subscription is in place). Out of scope.
