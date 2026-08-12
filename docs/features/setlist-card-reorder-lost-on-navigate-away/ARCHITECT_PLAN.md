# Architect Plan — Setlist Card Reorder Lost on Navigate Away

## Feature Slug

`bug/setlist-card-reorder-lost-on-navigate-away`

---

## Problem Summary

Dragging a setlist card to reorder it on the Setlists tab appears to save, but if the user navigates away from the Setlists screen before roughly 500ms passes, the reorder is silently discarded. The database keeps the pre-drag order. This occurs because the widget's `dispose()` method cancels the pending debounce timer without triggering the scheduled persist call.

**User-reported sequence:**

1. Drag setlist card to new position on Setlists tab
2. Navigate to a different tab or screen immediately (< 500ms)
3. Return to Setlists tab
4. Observe: dragged setlist card has reverted to original position

---

## Root Cause

**Confidence: HIGH** (confirmed via direct code inspection)

**File:** `lib/features/setlists/setlists_tab_content.dart`

**Lines 93–97 (dispose method):**

```dart
@override
void dispose() {
  _reorderDebounceTimer?.cancel();  // ← Cancels timer, never triggers persist
  _entranceController.dispose();
  super.dispose();
}
```

**Reorder flow:**

- User drags setlist card → triggers `_handleReorder` (line 175)
- Handler calls `notifier.reorderLocal(oldIndex, newIndex)` immediately (optimistic local UI update)
- Handler cancels any existing `_reorderDebounceTimer`
- Handler schedules a new 500ms timer that will call `await notifier.persistReorder()` (lines 182-189)
- **If user navigates away before 500ms:** `dispose()` runs, cancels the timer, and the scheduled persist callback never executes
- Local state showed the reordered list, but the database was never updated

**Why the existing persist method is correct:**

- `persistReorder()` (defined in `SetlistsNotifier`, `setlists_screen.dart` lines 279-297) is sound
- It uses an atomic RPC write (`reorder_setlists`) verified correct server-side
- It has a pre-reorder snapshot mechanism (`_preReorderSnapshot`) that allows safe rollback on failure
- Verified directly: the RPC write path itself works correctly
- The bug is not "the write corrupted data" — it's "the write never got scheduled"

---

## Reference Docs Consulted

None applicable. This is a setlist card reordering bug, not a notification or domain-specific system requiring reference documentation. The reorder logic and RPC behavior were verified directly from source code.

**Reference implementation:** This bug is identical in root cause to `bug/song-reorder-lost-on-navigate-away` (commit `241321d`, already fixed on its own unmerged branch). The solution pattern has been validated there and is being applied here to the sibling screen.

---

## Existing System Analysis

### Current Behavior (Setlist Card Reorder Flow)

**Normal flow (user waits ≥500ms after drag):**

1. User drags setlist card on Setlists tab
2. `_handleReorder(oldIndex, newIndex)` called (line 175)
3. `notifier.reorderLocal(oldIndex, newIndex)` updates UI optimistically
4. `_reorderDebounceTimer` set to fire after 500ms
5. Timer fires → `await notifier.persistReorder()` executes
6. `persistReorder()` calls `_repository.reorderSetlists()` → `reorder_setlists` RPC
7. RPC performs atomic position update
8. Success: local state matches database

**Failure flow (user navigates away quickly):**

1. User drags setlist card on Setlists tab
2. `_handleReorder(oldIndex, newIndex)` called
3. `notifier.reorderLocal(oldIndex, newIndex)` updates UI optimistically
4. `_reorderDebounceTimer` set to fire after 500ms
5. **User navigates to different tab before 500ms**
6. Navigator pops/switches → `SetlistsTabContent` widget disposed
7. `dispose()` runs: `_reorderDebounceTimer?.cancel()` cancels the timer
8. **Scheduled `persistReorder()` callback never runs**
9. User sees reordered list locally, but database still has old order
10. On next tab visit, database order is fetched → reorder appears "lost"

### Single Reorder Path

**Key simplification vs. song-reorder fix:** This file has only one reorder path. There is no Catalog/mixed-items distinction at the setlist card level:

- Catalog is just one of the cards being reordered
- All setlist cards use the same reorder handler: `_handleReorder`
- All use the same persist method: `notifier.persistReorder()`
- No branching logic needed in `dispose()`

This was confirmed by reading lines 175-189 of `setlists_tab_content.dart` — there is only one `_handleReorder` method, and it always calls `persistReorder()`.

### No Existing Pattern in Codebase

Inspection of other debounce timer patterns in the codebase reveals:

- `lib/features/contacts/contacts_tab_content.dart` (line 86): cancels `_reorderDebounceTimer` in dispose, no flush
- `lib/features/setlists/setlist_detail_screen.dart` (line 186): FIXED on `bug/song-reorder-lost-on-navigate-away` branch (commit `241321d`) — now flushes pending reorder on dispose
- `lib/features/events/widgets/event_editor_drawer.dart` (lines 449–450): cancels gig name/city debounce timers in dispose, no flush

**Conclusion:** The song-reorder fix introduced the flush-on-dispose pattern. This plan applies the same validated pattern to the sibling screen.

---

## Proposed Solution

### Design Decision: Fire-and-Forget on Dispose

**Option chosen:** Fire the pending persist as an unawaited call at dispose time using `ref.read(...)`.

**Rationale:**

- `dispose()` is synchronous and cannot `await` an async persist call
- Current behavior: 100% of quick-exit reorders are lost
- Fire-and-forget: persist will attempt to run; failures won't be visible to user (acceptable since screen is gone)
- This is a **strict improvement** over current behavior
- Maintains existing snapshot/rollback mechanism — no bypass of safety mechanisms

**Implementation approach:**

1. In `dispose()`, check if `_reorderDebounceTimer` is active
2. If active:
   - Cancel the timer (cleanup)
   - Immediately call `ref.read(setlistsProvider.notifier).persistReorder()` without awaiting
   - Use `unawaited()` from `dart:async` to make the fire-and-forget intent explicit
3. If timer is inactive, no action needed (no pending reorder)

**Why this is safe:**

- `setlistsProvider` (defined in `setlists_screen.dart`, line 297) is a plain `NotifierProvider`, not `.autoDispose` — confirmed by direct inspection
- The notifier survives the widget's teardown long enough for the RPC to complete
- `persistReorder()` already has a snapshot/rollback mechanism (`_preReorderSnapshot`) that prevents data corruption
- Calling it again at dispose time just adds one more persist request
- Even if the persist fails (network error, etc.), it's logged — acceptable since user has already left the screen

**What must not change:**

- Do not refactor the reorder logic itself
- Do not modify `persistReorder()` method in `SetlistsNotifier`
- Do not touch `setlist_repository.dart` or any RPC/migration
- Keep the debounce mechanism (500ms) unchanged for normal operation

---

## Database Impact

**Not applicable.**

- No migrations required
- No RLS policy changes
- No RPC signature changes
- No trigger modifications
- Uses existing `reorder_setlists` RPC

The fix only changes when the existing persist method is called, not what it does.

---

## Flutter Architecture Changes

### State Management

No changes to Riverpod providers or state classes.

### Repositories

No changes to `SetlistRepository`.

### Controllers

No changes to `SetlistsNotifier`. The existing `persistReorder()` method is already public and correct.

### Widgets

**Modified:** `SetlistsTabContent` (`lib/features/setlists/setlists_tab_content.dart`)

- Update `dispose()` method to flush pending reorder before canceling timer

---

## Files to Create

**None.**

---

## Files to Modify

| File                                                   | What changes                                                                                                                                                                                           |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/setlists_tab_content.dart`      | Modify `dispose()` method (lines 93–97) to flush pending reorder: if `_reorderDebounceTimer` is active, cancel it and call `ref.read(setlistsProvider.notifier).persistReorder()` as an unawaited fire-and-forget call. |

---

## Files Off-Limits

| File                                              | Reason                                                            |
| ------------------------------------------------- | ----------------------------------------------------------------- |
| `lib/main.dart`                                   | Init order must not change (per guardrails)                       |
| `lib/features/setlists/setlists_screen.dart`      | `SetlistsNotifier.persistReorder()` method is already correct; no controller changes needed |
| `lib/features/setlists/setlist_repository.dart`   | Repository write path is confirmed correct                        |
| `supabase/migrations/*.sql`                       | No database schema or RPC changes required                        |

---

## System Impact Map

| System                                 | Impact                                                                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Gigs                                   | unaffected                                                                                                               |
| Rehearsals                             | unaffected                                                                                                               |
| Setlists / Catalog                     | **affected** — fixes setlist card reorder persistence on Setlists tab                                                    |
| Members / RBAC                         | unaffected                                                                                                               |
| Auth / Session                         | unaffected                                                                                                               |
| Routing                                | unaffected                                                                                                               |
| Notifications                          | unaffected                                                                                                               |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms use the same Setlists tab component                                                         |

---

## Regression Risk

**LOW**

**Rationale:**

- Only one file modified: `setlists_tab_content.dart`
- Change is localized to `dispose()` lifecycle method
- Does not touch reorder logic, persist logic, or any repository/RPC code
- Fire-and-forget persist call uses the same guarded method already proven correct
- No other features share this code path
- No auth, session, routing, or init order changes
- Worst-case failure mode: persist fails silently (same as current behavior for quick-exit, but with an _attempt_ logged)
- Pattern already validated on sibling screen (`bug/song-reorder-lost-on-navigate-away`)

**Existing safeguards remain intact:**

- Snapshot/rollback mechanism prevents data corruption
- RPC atomic writes prevent lock contention
- Error handling and revert-to-snapshot logic unchanged

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Verify Current Behavior

Read `lib/features/setlists/setlists_tab_content.dart` lines 93–97 to confirm current `dispose()` implementation matches the plan's description.

### Task 2: Verify Single Reorder Path

Confirm that this file has only one reorder path (unlike the song-reorder fix which had two paths):

- Read `_handleReorder` method (lines 175-189)
- Confirm it always calls `notifier.persistReorder()` on the debounce timer
- Confirm there is no branching logic based on item type (Catalog vs. non-Catalog)

**Expected result:** Single path confirmed — no conditional logic needed in `dispose()`.

### Task 3: Import Required Symbol

Add import at top of `setlists_tab_content.dart` if not already present:

```dart
import 'dart:async' show Timer, unawaited;
```

If the file already has `import 'dart:async';` without the `show` clause, update it to explicitly list `Timer` and `unawaited`.

### Task 4: Modify dispose() to Flush Pending Reorder

Replace lines 93–97 with:

```dart
@override
void dispose() {
  // Flush pending reorder if timer is active
  if (_reorderDebounceTimer != null && _reorderDebounceTimer!.isActive) {
    _reorderDebounceTimer!.cancel();

    // Fire-and-forget: attempt persist even though screen is disposed.
    // Uses the same guarded persist method to prevent data corruption.
    // Failure won't be visible to user (acceptable — screen is gone).
    unawaited(
      ref.read(setlistsProvider.notifier).persistReorder(),
    );
  }
  _entranceController.dispose();
  super.dispose();
}
```

**Rationale:**

- Check if timer is active before attempting flush
- Cancel timer to prevent double-fire (cleanup)
- Fire-and-forget persist using `unawaited()` (dispose is synchronous)
- No branching needed — single reorder path always uses `persistReorder()`
- Existing snapshot/rollback mechanism in `persistReorder()` prevents corruption

### Task 5: Verify No Syntax Errors

Run `flutter analyze` on modified file:

```bash
flutter analyze lib/features/setlists/setlists_tab_content.dart
```

Confirm 0 errors. (The analyzer may flag `unawaited` as unused — this is a false positive; the symbol IS used.)

### Task 6: Verify No Build Regressions

Run full analyzer:

```bash
flutter analyze
```

Confirm 0 errors.

### Task 7: Document the Change

In `ENGINEER_REPORT.md`, note:

- Result of Task 2 investigation: confirm single reorder path (no branching needed)
- Which dispose() implementation was used (fire-and-forget with `unawaited`, no conditional)
- Confirmation that `setlistsProvider` is NOT `.autoDispose` (verified at line 297 of `setlists_screen.dart`)
- Result of `flutter analyze`

---

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable.** No database migrations or edge functions modified.

### Tier 2 — Post-deployment

**Not applicable.** No database migrations or edge functions modified.

### Manual Testing (Required)

#### Test 1: Quick-Exit Reorder (Primary Bug Fix)

**Steps:**

1. Open Setlists tab
2. Drag a setlist card to a new position
3. Immediately (< 500ms) navigate to a different tab (Gigs, Rehearsals, or Contacts)
4. Return to Setlists tab
5. Observe: dragged setlist card is still in the new position (not reverted)

**Expected:** Reorder persists despite quick navigation away.

#### Test 2: Normal Reorder (No Regression)

**Steps:**

1. Open Setlists tab
2. Drag a setlist card to a new position
3. Wait 1 second (> 500ms)
4. Navigate away and return
5. Observe: dragged setlist card is still in the new position

**Expected:** Normal reorder flow still works (no regression from existing behavior).

#### Test 3: Multiple Quick Reorders

**Steps:**

1. Open Setlists tab
2. Drag setlist card A to position 1
3. Immediately drag setlist card B to position 2
4. Immediately drag setlist card C to position 3
5. Immediately (< 500ms after last drag) navigate away
6. Return to Setlists tab
7. Observe: all three reorders persisted (not reverted)

**Expected:** Most recent reorder persists; earlier reorders in the sequence may have been coalesced by the debounce, but no data corruption occurs.

#### Test 4: Catalog Position Preserved

**Steps:**

1. Open Setlists tab
2. Verify Catalog setlist is at the top (position 0)
3. Drag a non-Catalog setlist to a new position
4. Immediately navigate away
5. Return to Setlists tab
6. Observe: Catalog is still at the top, and dragged setlist is in the new position

**Expected:** Catalog position is not affected by reordering non-Catalog setlists.

#### Test 5: Cross-Platform Consistency

**Repeat Test 1 on:**

- iOS
- Android
- Web
- macOS

**Expected:** Reorder persists on all platforms.

---

## QA Regression Areas

What QA must specifically test:

1. **Setlist card reorder on Setlists tab (primary)**
   - Quick-exit reorder (< 500ms) persists
   - Normal reorder (> 500ms) still works
   - Multiple quick reorders coalesce correctly

2. **Catalog position stability**
   - Catalog always remains at the top
   - Non-Catalog reorders do not affect Catalog position

3. **Cross-platform behavior**
   - iOS, Android, Web, macOS all behave identically

4. **No regression in related screens**
   - Song reorder within setlist detail screen (already fixed on separate branch)
   - No other setlist operations affected (delete, duplicate, create)

---

## Rollout / Migration Strategy

**Not applicable.** This is a client-side widget fix with no backend changes.

**Deployment:**

- Standard app release
- No migration or edge function deploy required
- No user data migration needed

---

## Out of Scope

Explicitly listed:

1. **Song reorder within setlist detail** — already fixed on separate branch (`bug/song-reorder-lost-on-navigate-away`, commit `241321d`)
2. **Other debounce timers in codebase** — contacts reorder, event editor fields (different risk profile)
3. **Refactoring reorder logic** — existing logic is correct; only dispose() behavior changes
4. **Removing the debounce** — 500ms debounce is intentional to prevent rapid-fire RPC calls
5. **Awaiting the persist in dispose()** — impossible (dispose is synchronous); fire-and-forget is the correct pattern

---
