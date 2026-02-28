# ARCHITECT PLAN — Bug: Dragging Set Break Throws Error

**Date:** 2026-02-28
**Status:** Root cause confirmed, fix proposed
**Severity:** High — blocks drag-and-drop for all special items (set breaks + pauses)

---

## 1. Problem Summary

Dragging a set break (or pause) to a new position in a non-Catalog setlist throws an error during persistence. Regular songs reorder correctly in the same list. The failure occurs because `SpecialItemCard` uses a **data-model position** for Flutter's `ReorderableDragStartListener.index`, rather than the actual **list index** provided by the `itemBuilder`. This is fundamentally different from how `ReorderableSongCard` handles the same mechanism—songs receive and use the correct `index` parameter.

A secondary contributing factor is the `reorder_setlist_positions` database trigger, which reindexes positions using 1-based `ROW_NUMBER()` after any delete, causing `item.position` to diverge from the 0-based list index that Flutter requires.

---

## 2. Root Cause (Line-Level)

### Primary Defect: Wrong index in `ReorderableDragStartListener`

**File:** `lib/features/setlists/widgets/special_item_card.dart`
**Lines:** ~97 (set break card) and ~165 (pause card)

```dart
// DEFECT — both _buildSetBreakCard and _buildPauseCard do this:
ReorderableDragStartListener(
  index: item.position,   // ← WRONG: uses data-model position, not list index
  child: ...
)
```

**Compare with the correct pattern in `ReorderableSongCard`:**

**File:** `lib/features/setlists/widgets/reorderable_song_card.dart`
**Line:** ~164

```dart
// CORRECT — uses the itemBuilder's index parameter
ReorderableDragStartListener(
  index: widget.index,    // ← RIGHT: uses list index passed from itemBuilder
  child: ...
)
```

`ReorderableSongCard` accepts an `index` parameter (line 36, `final int index;`) from the screen's `itemBuilder` callback. `SpecialItemCard` does **not** accept an `index` parameter at all — it only receives the `SetlistItem item` and reads `item.position`.

**Screen-side evidence** (`lib/features/setlists/setlist_detail_screen.dart`, lines ~1837–1845):

```dart
// Songs get the correct index:
child: ReorderableSongCard(
  song: song,
  index: index,       // ← itemBuilder's index (always correct)
  isDraggable: true,
  ...
),

// Special items do NOT receive index:
child: SpecialItemCard(
  item: item,         // ← no index parameter; card reads item.position internally
  isDraggable: true,
  ...
),
```

### Secondary Defect: 1-based position trigger

**File:** `lib/supabase/migrations/005_create_setlists_tables.sql`, lines 186–207

```sql
CREATE OR REPLACE FUNCTION reorder_setlist_positions()
RETURNS TRIGGER AS $$
BEGIN
  -- Comment says "starting from 1" — ROW_NUMBER() is 1-based
  WITH ordered_songs AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY position) as new_position
    FROM public.setlist_songs
    WHERE setlist_id = COALESCE(NEW.setlist_id, OLD.setlist_id)
  )
  UPDATE public.setlist_songs
  SET position = ordered_songs.new_position
  FROM ordered_songs
  WHERE public.setlist_songs.id = ordered_songs.id;
  RETURN COALESCE(NEW, OLD);
END;
```

This trigger fires `AFTER DELETE` on `setlist_songs`. It reindexes positions to `1, 2, 3, ...` (1-based). All client-side code uses 0-based positions. Flutter's `SliverReorderableList` uses 0-based indices.

After any delete in a setlist, positions become 1-based → `item.position` diverges from list index → `SpecialItemCard` registers the wrong drag index.

---

## 3. Why Songs Work But Set Breaks Fail

| Aspect | `ReorderableSongCard` (songs) | `SpecialItemCard` (set breaks/pauses) |
|---|---|---|
| Index source | `widget.index` (from itemBuilder) | `item.position` (from data model) |
| Receives index param | Yes (`final int index`) | **No** — reads position internally |
| After 1-based trigger | Still correct (uses itemBuilder index) | **Wrong** (uses 1-based position as 0-based index) |
| Last item after delete | index = N-1 ✅ | position = N → **out of bounds** (list has indices 0..N-1) |

**Concrete failure scenario (after any delete in the setlist):**

1. User deletes a song → `reorder_setlist_positions` trigger fires → positions become `[1, 2, 3]`
2. `loadSongs()` re-fetches → `SetlistItem.position` values are `[1, 2, 3]`
3. `SliverReorderableList` renders items at indices `[0, 1, 2]`
4. Set break at index 0 has `item.position = 1` → `ReorderableDragStartListener(index: 1)` — registers as index 1 instead of 0
5. Song at index 1 has `ReorderableSongCard(index: 1)` — also registers as index 1 → **two items claim index 1, no item claims index 0**
6. Set break at last index (2) has `item.position = 3` → `ReorderableDragStartListener(index: 3)` — **index 3 is out of bounds** for a 3-item list
7. Dragging the set break → Flutter assertion error or wrong item dragged → `onReorder` receives incorrect `oldIndex` → `reorderItemsLocal` operates on wrong item → `persistItemReorder` sends wrong order → potential unique constraint violation or corrupted state

Songs are unaffected because `ReorderableSongCard` always uses the correct `widget.index` from the `itemBuilder`.

---

## 4. Minimal Fix Strategy

### Fix 1 (Required): Add `index` parameter to `SpecialItemCard`

**File:** `lib/features/setlists/widgets/special_item_card.dart`

1. Add `final int index;` to the constructor (matching `ReorderableSongCard` pattern)
2. Replace `item.position` with `index` in both `ReorderableDragStartListener` calls:
   - `_buildSetBreakCard` (~line 97)
   - `_buildPauseCard` (~line 165)

**File:** `lib/features/setlists/setlist_detail_screen.dart`

3. Pass `index` from the `itemBuilder` callback to `SpecialItemCard`:
   ```dart
   SpecialItemCard(
     item: item,
     index: index,          // ← add this
     isDraggable: true,
     ...
   )
   ```

### Fix 2 (Recommended): Fix trigger to use 0-based positions

**File:** New migration (e.g., `lib/supabase/migrations/084_fix_reorder_positions_zero_based.sql`)

Change `ROW_NUMBER()` to `ROW_NUMBER() - 1` so positions are 0-based after delete:

```sql
CREATE OR REPLACE FUNCTION reorder_setlist_positions()
RETURNS TRIGGER AS $$
BEGIN
  WITH ordered_songs AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY position) - 1 as new_position
    FROM public.setlist_songs
    WHERE setlist_id = COALESCE(NEW.setlist_id, OLD.setlist_id)
  )
  UPDATE public.setlist_songs
  SET position = ordered_songs.new_position
  FROM ordered_songs
  WHERE public.setlist_songs.id = ordered_songs.id;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

Fix 2 makes positions consistent with all client code, but Fix 1 alone is sufficient to resolve the drag bug (since the card will use the correct list index regardless of position values).

---

## 5. Files To Modify

| File | Change | Risk |
|---|---|---|
| `lib/features/setlists/widgets/special_item_card.dart` | Add `index` param; use in both `ReorderableDragStartListener` calls | **Low** — additive change to widget API |
| `lib/features/setlists/setlist_detail_screen.dart` | Pass `index` to `SpecialItemCard` constructor | **Low** — uses already-available `index` variable |
| `lib/supabase/migrations/084_fix_reorder_positions_zero_based.sql` *(optional)* | `ROW_NUMBER() - 1` in trigger | **Low** — only affects post-delete position reindexing |

No schema changes required. No changes to reorder logic, RPC, or repository layer.

---

## 6. Risk Analysis

| Risk | Likelihood | Mitigation |
|---|---|---|
| Breaking existing `SpecialItemCard` usages | Very Low | `index` is only used by `ReorderableDragStartListener`; non-draggable usage passes `isDraggable: false` so the listener isn't rendered |
| Regression in song reorder | None | Song reorder path is completely unchanged |
| DB trigger change breaks existing data | Low | `ROW_NUMBER() - 1` is additive; existing 1-based positions still render correctly (positions are used for ordering, not indexing, in DB queries) |
| Concurrent drag+persist race | Unchanged | Debounce timer already handles this; not affected by this fix |

---

## 7. Verification Plan (Manual Test Steps)

### Pre-fix reproduction
1. Open a non-Catalog setlist with at least 1 song and 1 set break
2. Delete any song from the setlist (triggers 1-based reindex)
3. Try to drag the set break to a new position
4. **Expected:** Error during persistence; UI reverts or shows error message

### Post-fix verification
1. **Basic drag:** Open a non-Catalog setlist with songs + set breaks. Drag a set break to a different position. Confirm it persists without error.
2. **After delete:** Delete a song, then drag a set break. Confirm no error.
3. **Song drag still works:** In the same mixed setlist, drag a song. Confirm it persists correctly.
4. **Pause item:** Add a pause to the setlist. Drag it to a new position. Confirm it works.
5. **Multiple rapid drags:** Drag a set break, then immediately drag a song. Confirm debounce handles both correctly.
6. **Reload persistence:** Drag a set break, wait for persist, then navigate away and back. Confirm the new order was saved.
7. **Edge case — last item:** Place a set break at the last position. Drag it to the first position. Confirm no out-of-bounds error.

---

## Appendix: Full Trace

```
User drags set break grip icon
  → ReorderableDragStartListener(index: item.position)    ← BUG: should be itemBuilder index
    → SliverReorderableList receives wrong oldIndex
      → onReorder: _handleItemReorder(wrongOldIndex, newIndex)
        → notifier.reorderItemsLocal(wrongOldIndex, newIndex)
          → operates on wrong item in state.items list
            → state corrupted or RangeError if index out of bounds
              → persistItemReorder() sends wrong item order
                → reorderItems() updates positions incorrectly
                  → UNIQUE(setlist_id, position) violation or corrupted order
```

Correct flow (after fix):
```
User drags set break grip icon
  → ReorderableDragStartListener(index: index)             ← FIXED: uses itemBuilder index
    → SliverReorderableList receives correct oldIndex
      → onReorder: _handleItemReorder(correctOldIndex, newIndex)
        → notifier.reorderItemsLocal(correctOldIndex, newIndex)
          → correct item moved in state.items
            → persistItemReorder() sends correct item order
              → reorderItems() updates positions correctly ✅
```
