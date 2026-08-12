# Architect Plan — Song Reorder Lost on Navigate Away

## Feature Slug

`bug/song-reorder-lost-on-navigate-away`

---

## Problem Summary

Dragging a song to reorder it inside a setlist appears to save, but if the user navigates away from the setlist detail screen before roughly 500ms passes, the reorder is silently discarded. The database keeps the pre-drag order. This occurs because the widget's `dispose()` method cancels the pending debounce timer without triggering the scheduled persist call.

**User-reported sequence:**

1. Drag song in setlist detail to new position
2. Exit to Setlists list screen immediately (< 500ms)
3. Pull-to-refresh the list
4. Re-enter the setlist
5. Observe: dragged song has reverted to original position

---

## Root Cause

**Confidence: HIGH** (confirmed via direct code inspection)

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Lines 186–191 (dispose method):**

```dart
@override
void dispose() {
  _reorderDebounceTimer?.cancel();  // ← Cancels timer, never triggers persist
  _entranceController.dispose();
  _sortAnimController.dispose();
  _searchController.dispose();
  _searchFocusNode.dispose();
  super.dispose();
}
```

**Reorder flow:**

- User drags song → triggers either `_handleReorder` (line 675, legacy songs-only) or `_handleItemReorder` (line 979, actively-used mixed-items path)
- Handler calls `notifier.reorderItemsLocal(oldIndex, newIndex)` immediately (optimistic local UI update)
- Handler cancels any existing `_reorderDebounceTimer`
- Handler schedules a new 500ms timer that will call `await notifier.persistItemReorder()` (or `persistReorder()` for legacy path)
- **If user navigates away before 500ms:** `dispose()` runs, cancels the timer, and the scheduled persist callback never executes
- Local state showed the reordered list, but the database was never updated

**Why the existing persist methods are correct:**

- `persistItemReorder()` (controller line 2190) and `persistReorder()` (controller line 1084) are sound
- They use atomic two-phase RPC writes (`reorder_setlist_items`, `reorder_setlist_songs`) verified correct server-side
- They have in-flight guards (`_isItemReorderInFlight`, `_itemReorderPendingAfterFlight`) that prevent UNIQUE constraint violations during rapid consecutive drags _within_ a single session
- Verified directly against production: existing `setlist_songs` rows are internally consistent (unique sequential positions, no corruption), confirming the RPC write path itself works correctly
- The bug is not "the write corrupted data" — it's "the write never got scheduled"

---

## Reference Docs Consulted

None applicable. This is a setlist reordering bug, not a notification or domain-specific system requiring reference documentation. The reorder logic and RPC behavior were verified directly from source code and production database state.

---

## Existing System Analysis

### Current Behavior (Setlist Song Reorder Flow)

**Normal flow (user waits ≥500ms after drag):**

1. User drags song in setlist detail
2. `_handleItemReorder(oldIndex, newIndex)` called (line 979)
3. `notifier.reorderItemsLocal(oldIndex, newIndex)` updates UI optimistically
4. `_reorderDebounceTimer` set to fire after 500ms
5. Timer fires → `await notifier.persistItemReorder()` executes
6. `persistItemReorder()` calls `_specialItemRepo.reorderItems()` → `reorder_setlist_items` RPC
7. RPC performs two-phase atomic position update (negative positions first, then final positions keyed on ID array order)
8. Success: local state matches database

**Failure flow (user navigates away quickly):**

1. User drags song in setlist detail
2. `_handleItemReorder(oldIndex, newIndex)` called
3. `notifier.reorderItemsLocal(oldIndex, newIndex)` updates UI optimistically
4. `_reorderDebounceTimer` set to fire after 500ms
5. **User taps back button before 500ms**
6. Navigator pops route → `SetlistDetailScreen` widget disposed
7. `dispose()` runs: `_reorderDebounceTimer?.cancel()` cancels the timer
8. **Scheduled `persistItemReorder()` callback never runs**
9. User sees reordered list locally, but database still has old order
10. On next screen visit, database order is fetched → reorder appears "lost"

### Shared Timer Constraint

Both `_handleReorder` (legacy songs-only, line 675) and `_handleItemReorder` (mixed-items, line 979) use the **same** `_reorderDebounceTimer` field. A single fix at the `dispose()` level covers both call sites.

### No Existing Pattern in Codebase

Inspection of other debounce timer patterns in the codebase reveals:

- `lib/features/contacts/contacts_tab_content.dart` (line 86): cancels `_reorderDebounceTimer` in dispose, no flush
- `lib/features/setlists/setlists_tab_content.dart` (line 94): cancels `_reorderDebounceTimer` in dispose, no flush
- `lib/features/events/widgets/event_editor_drawer.dart` (lines 449–450): cancels gig name/city debounce timers in dispose, no flush

**Conclusion:** No existing "flush pending write on dispose" pattern exists. This fix introduces a new pattern for BandRoadie.

---

## Proposed Solution

### Design Decision: Fire-and-Forget on Dispose

**Option chosen:** Fire the pending persist as an unawaited call at dispose time using `ref.read(...)`.

**Rationale:**

- `dispose()` is synchronous and cannot `await` an async persist call
- Current behavior: 100% of quick-exit reorders are lost
- Fire-and-forget: persist will attempt to run; failures won't be visible to user (acceptable since screen is gone)
- This is a **strict improvement** over current behavior
- Maintains existing in-flight guards — no bypass of safety mechanisms

**Implementation approach:**

1. In `dispose()`, check if `_reorderDebounceTimer` is active
2. If active:
   - Cancel the timer (cleanup)
   - Immediately call `ref.read(setlistDetailProvider.notifier).persistItemReorder()` (or `persistReorder()` for legacy path) without awaiting
   - Use `unawaited()` from `dart:async` to make the fire-and-forget intent explicit
3. If timer is inactive, no action needed (no pending reorder)

**Why this is safe:**

- The persist methods (`persistItemReorder`, `persistReorder`) already have in-flight guards that prevent concurrent writes
- Calling them again at dispose time just adds one more queued persist request
- If a persist is already in-flight, `persistItemReorder()` sets `_itemReorderPendingAfterFlight = true` and returns immediately (no double-write)
- If no persist is in-flight, the persist executes normally
- Even if the persist fails (network error, etc.), it's logged server-side and in debug console — acceptable since user has already left the screen

**What must not change:**

- Do not refactor the reorder logic itself
- Do not modify `persistItemReorder()` or `persistReorder()` methods
- Do not touch `special_item_repository.dart`, `setlist_repository.dart`, or any RPC/migration
- Keep the debounce mechanism (500ms) unchanged for normal operation

---

## Database Impact

**Not applicable.**

- No migrations required
- No RLS policy changes
- No RPC signature changes
- No trigger modifications
- Uses existing `reorder_setlist_items` and `reorder_setlist_songs` RPCs (or their fallback paths)

The fix only changes when the existing persist methods are called, not what they do.

---

## Flutter Architecture Changes

### State Management

No changes to Riverpod providers or state classes.

### Repositories

No changes to `SetlistRepository` or `SpecialItemRepository`.

### Controllers

No changes to `SetlistDetailNotifier`. The existing `persistItemReorder()` and `persistReorder()` methods are already public and correct.

### Widgets

**Modified:** `SetlistDetailScreen` (`lib/features/setlists/setlist_detail_screen.dart`)

- Update `dispose()` method to flush pending reorder before canceling timer

---

## Files to Create

**None.**

---

## Files to Modify

| File                                               | What changes                                                                                                                                                                                                                                                               |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart` | Modify `dispose()` method (lines 186–191) to flush pending reorder: if `_reorderDebounceTimer` is active, cancel it and call `ref.read(setlistDetailProvider.notifier).persistItemReorder()` (or `persistReorder()` for legacy path) as an unawaited fire-and-forget call. |

---

## Files Off-Limits

| File                                                   | Reason                                                            |
| ------------------------------------------------------ | ----------------------------------------------------------------- |
| `lib/main.dart`                                        | Init order must not change (per guardrails)                       |
| `lib/features/setlists/setlist_detail_controller.dart` | Persist methods are already correct; no controller changes needed |
| `lib/features/setlists/setlist_repository.dart`        | Repository write path is confirmed correct                        |
| `lib/features/setlists/special_item_repository.dart`   | Repository write path is confirmed correct                        |
| `supabase/migrations/*.sql`                            | No database schema or RPC changes required                        |

---

## System Impact Map

| System                                 | Impact                                                                                                                                           |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Gigs                                   | unaffected                                                                                                                                       |
| Rehearsals                             | unaffected                                                                                                                                       |
| Setlists / Catalog                     | **affected** — fixes song reorder persistence in setlist detail screen for both normal setlists (mixed-items path) and Catalog (songs-only path) |
| Members / RBAC                         | unaffected                                                                                                                                       |
| Auth / Session                         | unaffected                                                                                                                                       |
| Routing                                | unaffected                                                                                                                                       |
| Notifications                          | unaffected                                                                                                                                       |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms use the same setlist detail screen                                                                                  |

---

## Regression Risk

**LOW**

**Rationale:**

- Only one file modified: `setlist_detail_screen.dart`
- Change is localized to `dispose()` lifecycle method
- Does not touch reorder logic, persist logic, or any repository/RPC code
- Fire-and-forget persist call uses the same guarded methods already proven correct
- No other features share this code path
- No auth, session, routing, or init order changes
- Worst-case failure mode: persist fails silently (same as current behavior for quick-exit, but with an _attempt_ logged)

**Existing safeguards remain intact:**

- In-flight guards prevent UNIQUE constraint violations
- Two-phase RPC prevents lock contention
- Band-switch safety checks in persist methods
- Error handling and revert-to-last-good logic unchanged

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Verify Current Behavior

Read `lib/features/setlists/setlist_detail_screen.dart` lines 186–191 to confirm current `dispose()` implementation matches the plan's description.

### Task 2: Determine Active Reorder Path

Confirm which reorder path is actively used. Both paths share a single `_reorderDebounceTimer`, so `dispose()` must flush using whichever persist method corresponds to the pending timer.

**Investigation result:**

At line 2756, the widget determines which path to use:

```dart
final useItems = state.items.isNotEmpty;
```

Then at line 2886:

```dart
onReorderItem: useItems ? _handleItemReorder : _handleReorder,
```

**Two paths:**

1. **Mixed-items path** (`state.items.isNotEmpty == true`):
   - Handler: `_handleItemReorder` (line 979)
   - Persist method: `persistItemReorder()`
   - Used for: non-Catalog setlists (normal setlists with songs, breaks, pauses)

2. **Songs-only path** (`state.items.isEmpty == true`):
   - Handler: `_handleReorder` (line 675)
   - Persist method: `persistReorder()`
   - Used for: Catalog setlist (lines 530-559 in controller: Catalog sets `items: const []`)

**Critical implication for dispose():**

For the Catalog, `state.items` is empty. If `dispose()` unconditionally calls `persistItemReorder()`:

- `persistItemReorder()` reads `state.items` (controller line 2208: `final itemIds = state.items.map((i) => i.id).toList()`)
- Passes empty array to `_specialItemRepo.reorderItems()`
- Repository line 304: `if (itemIdsInOrder.isEmpty) return;` — early exit, no persist
- **Catalog reorder is silently lost**

Therefore, `dispose()` must call the persist method that matches `state.items.isNotEmpty`, mirroring the widget's logic.

### Task 3: Import Required Symbol

Add import at top of `setlist_detail_screen.dart` if not already present:

```dart
import 'dart:async' show Timer, unawaited;
```

### Task 4: Modify dispose() to Flush Pending Reorder

Replace lines 186–191 with:

```dart
@override
void dispose() {
  // Flush pending reorder if timer is active
  if (_reorderDebounceTimer != null && _reorderDebounceTimer!.isActive) {
    _reorderDebounceTimer!.cancel();

    // Determine which persist method to call based on which path is active.
    // Line 2756: `final useItems = state.items.isNotEmpty;`
    // Line 2886: `onReorderItem: useItems ? _handleItemReorder : _handleReorder`
    // Must mirror that logic here to avoid silent no-op for Catalog (items is empty).
    final state = ref.read(setlistDetailProvider);
    final shouldUseMixedItems = state.items.isNotEmpty;

    // Fire-and-forget: attempt persist even though screen is disposed.
    // Uses the same guarded persist methods to prevent double-writes.
    // Failure won't be visible to user (acceptable — screen is gone).
    if (shouldUseMixedItems) {
      unawaited(
        ref.read(setlistDetailProvider.notifier).persistItemReorder(),
      );
    } else {
      // Songs-only path (Catalog or legacy)
      unawaited(
        ref.read(setlistDetailProvider.notifier).persistReorder(),
      );
    }
  }
  _entranceController.dispose();
  _sortAnimController.dispose();
  _searchController.dispose();
  _searchFocusNode.dispose();
  super.dispose();
}
```

**Rationale:**

- `state.items.isNotEmpty` exactly mirrors the widget's logic at line 2756
- For Catalog: `items` is empty → calls `persistReorder()` (songs-only RPC)
- For non-Catalog: `items` is populated → calls `persistItemReorder()` (mixed-items RPC)
- Avoids silent no-op where `persistItemReorder()` would early-return on empty `itemIds` (repository line 304)

### Task 5: Verify No Syntax Errors

Run `flutter analyze` on modified file:

```bash
flutter analyze lib/features/setlists/setlist_detail_screen.dart
```

Confirm 0 errors.

### Task 6: Verify No Build Regressions

Run full analyzer:

```bash
flutter analyze
```

Confirm 0 errors.

### Task 7: Document the Change

In `ENGINEER_REPORT.md`, note:

- Result of Task 2 investigation: which reorder path is used when (based on `state.items.isNotEmpty`)
- Confirmation that Catalog uses the songs-only path (`persistReorder()`) because `items` is empty
- Which dispose() implementation was used (fire-and-forget with `unawaited`, conditional on `items.isNotEmpty`)
- Confirmation that both reorder paths are covered by the conditional flush logic
- Result of `flutter analyze`

---

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable.** No database migrations or edge functions modified.

### Tier 2 — Post-deployment

**Not applicable.** No database migrations or edge functions modified.

### Manual Testing (Required)

#### Test 1: Quick-Exit Reorder (Primary Bug Fix)

**Precondition:** Setlist with 5+ songs, not the Catalog.

**Steps:**

1. Open setlist detail
2. Drag song from position 2 to position 4
3. **Immediately** (< 500ms) tap back button to return to Setlists list
4. Re-enter the setlist
5. **Expected:** Song is at position 4 (reorder persisted)
6. **Previous behavior:** Song reverted to position 2 (reorder lost)

#### Test 2: Normal Reorder (Unchanged Behavior)

**Precondition:** Setlist with 5+ songs.

**Steps:**

1. Open setlist detail
2. Drag song from position 1 to position 3
3. Wait 1 second (allow debounce to complete)
4. Navigate away
5. Re-enter setlist
6. **Expected:** Song is at position 3 (reorder persisted, as before)

#### Test 3: Rapid Consecutive Drags

**Precondition:** Setlist with 5+ songs.

**Steps:**

1. Open setlist detail
2. Drag song A to new position
3. Immediately drag song B to new position (< 500ms gap)
4. Immediately drag song C to new position (< 500ms gap)
5. **Immediately** tap back button (< 500ms after last drag)
6. Re-enter setlist
7. **Expected:** Final order matches last drag (song C position), no corruption
8. Check debug console for in-flight guard messages ("Item reorder already in-flight, queued")

#### Test 4: App Backgrounding (iOS/Android)

**Platform:** iOS or Android

**Steps:**

1. Open setlist detail
2. Drag song to new position
3. **Immediately** swipe up to home screen (< 500ms)
4. Return to app
5. Navigate away from setlist detail
6. Re-enter setlist
7. **Expected:** Song reorder persisted (dispose flush triggered when app backgrounded)

#### Test 5: Catalog Quick-Exit Reorder (Critical Path)

**Precondition:** Catalog setlist (the special per-band Catalog).

**Why this test is critical:** Catalog uses `items: const []` (empty), so `useItems = false` at line 2756. The Catalog reorder path uses `_handleReorder` → `persistReorder()`, not `persistItemReorder()`. If `dispose()` unconditionally calls `persistItemReorder()`, the Catalog quick-exit reorder would silently no-op (repository line 304 early-returns on empty `itemIdsInOrder`).

**Steps:**

1. Open the Catalog setlist detail (Setlists tab → "Catalog")
2. Drag a song from position 1 to position 3
3. **Immediately** (< 500ms) tap back button to return to Setlists list
4. Re-enter the Catalog
5. **Expected:** Song is at position 3 (reorder persisted via `persistReorder()` path)
6. **Without the fix:** Song would revert to position 1 (because `persistItemReorder()` no-ops on empty items)

**Verification:**

- Check debug console for `[SetlistDetail] Persisted reorder` (not `Persisted item reorder`)
- Confirm no error messages or silent failures

---

## QA Regression Areas

QA must specifically test:

### Primary Test Case

- **Song reorder with quick exit** (< 500ms) in setlist detail screen
- Confirm reorder persists even when navigating away immediately
- Test on **both** normal setlists (mixed-items path) and **Catalog** (songs-only path)
- Test on all platforms: iOS, Android, macOS, Web

### Setlist Reorder Integrity

- Drag multiple songs consecutively and exit quickly
- Verify no position conflicts or UNIQUE constraint errors
- Check debug console logs for proper in-flight guard behavior
- Test in both Catalog and non-Catalog setlists

### Related Reorder Features (No Regression)

- **Setlist list reorder** (drag setlists in Setlists tab) — should be unaffected
- **Member reorder** (drag members in Contacts tab) — should be unaffected (note: same bug likely exists there, but out of scope)
- **Catalog sort** (tuning-based sort in Catalog setlist) — should be unaffected

### Dispose Lifecycle

- Rapidly enter/exit setlist detail multiple times
- Verify no memory leaks or controller disposal errors
- Check that timers are properly canceled (no lingering callbacks)

---

## Rollout / Migration Strategy

**Not applicable.** This is a client-side bug fix with no database or backend changes. Standard web deployment via `./tools/deploy_web.sh` after QA approval. Mobile apps will receive the fix in the next release cycle.

---

## Out of Scope

1. **Fixing the same bug in other screens:**
   - Contacts tab member reorder (same bug pattern observed at `contacts_tab_content.dart` line 86)
   - Setlists list reorder (same bug pattern observed at `setlists_tab_content.dart` line 94)
   - These are out of scope for this specific feature. Can be addressed in separate tickets if prioritized.

2. **Reducing the debounce delay:**
   - The 500ms debounce is intentional to avoid spamming the database during rapid drags.
   - Changing the delay is a separate UX decision, not part of this bug fix.

3. **Optimistic UI feedback improvements:**
   - Adding a "Saving..." indicator during debounce period
   - Showing a "Reorder failed" toast if the persist fails
   - Out of scope; current behavior is optimistic with silent failure (acceptable per project conventions)

4. **Refactoring dispose-flush pattern into a shared utility:**
   - No existing pattern in the codebase; introducing a shared abstraction would be premature generalization.
   - If this pattern is needed in 3+ places, consider refactoring in a future cleanup ticket.

---

**End of Plan**
