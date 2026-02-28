# QA REPORT — Bug: Dragging Set Break Throws Error

**Date:** 2026-02-28
**Plan:** `docs/features/bug_drag_set_break/ARCHITECT_PLAN.md`
**Engineer Report:** `docs/features/bug_drag_set_break/ENGINEER_REPORT.md`
**Verdict:** PASS

---

## Verification Summary

### 1. Primary Fix: `ReorderableDragStartListener` uses builder index, not `item.position`

| Check | Result |
|---|---|
| `_buildSetBreakCard` uses `index` (line 99) | **PASS** |
| `_buildPauseCard` uses `index` (line 168) | **PASS** |
| `index` is a `required` constructor parameter (line 18) | **PASS** |
| Screen passes `itemBuilder` index at call site (line 1814) | **PASS** |

### 2. No other drag listeners reference `item.position`

Searched all `.dart` files for `item.position` in drag-related contexts. Zero matches. The only three `ReorderableDragStartListener` usages in the codebase:

| File | Index source | Status |
|---|---|---|
| `special_item_card.dart` line 99 (set break) | `index` (builder param) | **Correct** |
| `special_item_card.dart` line 168 (pause) | `index` (builder param) | **Correct** |
| `reorderable_song_card.dart` line 165 | `widget.index` (builder param) | **Correct** (unchanged) |

### 3. Regression Checks

| Scenario | Risk | Verification |
|---|---|---|
| Song reorder | None | `ReorderableSongCard` was not modified. Uses `widget.index` as before. |
| Mixed list reorder | None | `_handleItemReorder` / `reorderItemsLocal` unchanged. Operates on `oldIndex/newIndex` from Flutter framework. |
| Set break reorder | Fixed | `SpecialItemCard` now receives correct 0-based index. |
| Non-draggable `SpecialItemCard` | None | When `isDraggable: false`, `ReorderableDragStartListener` is not rendered; `index` is unused. |

### 4. Duplicate Keys

| Key | Scope | Uniqueness |
|---|---|---|
| `ValueKey(item.listKey)` on Padding wrapper | Combines `type.dbValue` + `id` | Unique — `id` is the `setlist_songs` row PK |
| `Key('dismiss_special_${item.id}')` on Dismissible | Uses row PK | Unique |
| `ValueKey(item.listKey)` on song Padding wrapper | `'song-$id'` | Unique — different prefix from special items |

**No duplicate keys.** PASS.

### 5. Rebuild Behavior

`SpecialItemCard` is a `StatelessWidget`. The `index` parameter is an `int` — value type comparison. If the item doesn't move, `index` won't change, and Flutter's diffing skips the rebuild. If the item does move (e.g., during reorder), `index` correctly changes and the widget rebuilds with the new index. No unintended rebuild behavior introduced.

**PASS.**

### 6. Index Drift on Fast Scroll

`SliverReorderableList` is lazy-building. The `itemBuilder` provides the correct `index` per invocation. `index` is passed directly to `SpecialItemCard` as a constructor arg — no caching, no stale state. Each render pass gets a fresh index from the builder.

**PASS.**

### 7. Analyzer Warnings

```
flutter analyze lib/features/setlists/widgets/special_item_card.dart lib/features/setlists/setlist_detail_screen.dart
→ No issues found!
```

**PASS.**

### 8. Performance (50+ item lists)

No change to performance characteristics:
- `SpecialItemCard` remains `StatelessWidget` (no added state, no animation controllers)
- `index` is an `int` — zero allocation overhead
- No new listeners, streams, or providers introduced
- `SliverReorderableList` lazy-building behavior unchanged

**PASS.**

---

## Stress Test Scenarios (Logic Review)

### Rapid drag + scroll
- `onReorder` is debounced (500ms timer in `_handleItemReorder`)
- `reorderItemsLocal` applies immediately (optimistic) using framework-provided indices
- Rapid drags reset the timer; local state stays consistent
- `lastKnownGoodItems` snapshot restores on persistence failure
- **No issue.**

### Drag across viewport boundaries
- Handled entirely by `SliverReorderableList` framework internals
- `index` from `itemBuilder` is always correct for the current viewport render
- **No issue.**

### Large list (50+ items)
- `SliverReorderableList` only builds visible items (lazy)
- `index` is a simple int parameter — no scaling concern
- **No issue.**

### Drag after adding new set break
- New item inserted → `items` list updated → widget tree rebuilds
- Fresh `itemBuilder` invocation provides correct 0-based indices for all items
- **No issue.**

### Drag after deleting items
- **This was the original failure scenario.**
- DB trigger reindexes positions to 1-based after delete
- Before fix: `item.position` (1-based) was used as drag index → index mismatch → crash
- After fix: `index` from `itemBuilder` (always 0-based) is used → correct behavior
- **Fixed.**

### Reorder after app relaunch
- `loadSongs()` fetches fresh data; `item.position` values may be 1-based from DB
- `itemBuilder` provides 0-based indices regardless of stored positions
- `SpecialItemCard` uses `index` param, ignoring `item.position` for drag
- **No issue.**

---

## Persistence Logic Safety

### UI index → DB position flow

1. User drags item → Flutter reports `oldIndex` / `newIndex` (0-based, from registered drag indices)
2. `reorderItemsLocal` removes at `oldIndex`, inserts at adjusted index, re-indexes positions to 0-based using `entry.key`
3. `persistItemReorder` sends ordered list of DB row IDs (`itemIdsInOrder`)
4. `reorderItems` in `SpecialItemRepository` sets `position: i` (0-based) for each ID in order
5. Two-phase update (1000+i → i) avoids unique constraint violations

**The `index` parameter in `SpecialItemCard` has zero interaction with persistence logic.** It is consumed only by `ReorderableDragStartListener` to register the item with Flutter's reorder framework. The persistence path operates on list order of IDs, not on any `index` value from widgets.

**No mismatch between UI index and DB position.** PASS.

### Uniqueness Safety

- `listKey` uses `'${type.dbValue}-$id'` — guaranteed unique by DB primary key
- Two-phase position update in `reorderItems` avoids unique constraint violations
- No changes to key generation or persistence logic

**PASS.**

---

## Critical Issues

None.

---

## Warnings

| # | Warning | Severity |
|---|---|---|
| W1 | DB trigger `reorder_setlist_positions` still uses 1-based `ROW_NUMBER()`. While the UI fix makes this non-blocking, the inconsistency between 0-based client positions and 1-based post-delete DB positions is technical debt. Consider applying Architect Plan Fix 2 in a future migration. | Low |

---

## Suggestions

None. The fix is minimal, correct, and aligned with the existing pattern in `ReorderableSongCard`.

---

## Manual Test Checklist

Before merging to staging, manually verify:

- [ ] Open a non-Catalog setlist with songs + set breaks
- [ ] Drag a set break to a new position → persists without error
- [ ] Drag a pause to a new position → persists without error
- [ ] Drag a song to a new position → still works (regression check)
- [ ] Delete a song, then drag a set break → works (original failure scenario)
- [ ] Delete a set break, then drag another set break → works
- [ ] Add a new set break, then drag it immediately → works
- [ ] Close and reopen the setlist → order is preserved
- [ ] Rapid drag multiple items in succession → no crash, debounce fires correctly
- [ ] Scroll through a long setlist (20+ items) and drag from bottom to top → no index drift

---

## Verdict

**PASS — Safe to merge to staging.**

The implementation correctly applies Fix 1 from the Architect Plan. Both `ReorderableDragStartListener` calls in `SpecialItemCard` now use the builder-provided `index` instead of `item.position`. The fix is minimal (4 edit sites, 2 files), introduces no new dependencies, and does not touch reorder persistence, key generation, or song card behavior. No analyzer warnings. No regression risk identified.
