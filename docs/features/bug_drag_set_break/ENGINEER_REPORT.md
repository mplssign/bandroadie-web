# ENGINEER REPORT — Bug: Dragging Set Break Throws Error

**Date:** 2026-02-28
**Plan:** `docs/features/bug_drag_set_break/ARCHITECT_PLAN.md`
**Status:** Implemented — Fix 1 (Required) applied. Fix 2 (DB trigger) deferred per plan guidance.

---

## Summary of Implementation

Applied the Architect Plan's **Fix 1** — added an `index` parameter to `SpecialItemCard` so that `ReorderableDragStartListener` uses the correct 0-based list index from Flutter's `itemBuilder`, instead of the data-model `item.position` which can diverge (especially after 1-based reindex triggers).

Two files modified, four edit sites total. No schema changes, no RPC changes, no refactoring.

---

## Files Modified

### 1. `lib/features/setlists/widgets/special_item_card.dart`

| Change | Detail |
|---|---|
| Added `final int index;` field | New required constructor parameter, matching `ReorderableSongCard` pattern |
| Updated constructor | `required this.index` added |
| `_buildSetBreakCard` | `ReorderableDragStartListener(index: item.position)` → `ReorderableDragStartListener(index: index)` |
| `_buildPauseCard` | `ReorderableDragStartListener(index: item.position)` → `ReorderableDragStartListener(index: index)` |

### 2. `lib/features/setlists/setlist_detail_screen.dart`

| Change | Detail |
|---|---|
| `SpecialItemCard` construction (line ~1812) | Added `index: index` to pass the `itemBuilder` index to the card |

---

## Database Changes

None. The Architect Plan's Fix 2 (0-based trigger migration) was marked as optional/recommended. Fix 1 alone fully resolves the bug since the card now uses the correct list index regardless of stored position values.

---

## RPC Changes

None.

---

## Acceptance Criteria Checklist

| # | Criterion | Status |
|---|---|---|
| 1 | `SpecialItemCard` accepts an `index` parameter | Done |
| 2 | Set break card uses `index` for `ReorderableDragStartListener` | Done |
| 3 | Pause card uses `index` for `ReorderableDragStartListener` | Done |
| 4 | Screen passes `itemBuilder` index to `SpecialItemCard` | Done |
| 5 | No other `SpecialItemCard` call sites exist (verified via grep) | Confirmed — only 1 production call site |
| 6 | `flutter analyze` passes on both modified files | Passed — "No issues found!" |
| 7 | No schema or RPC changes | Confirmed |
| 8 | Song reorder path untouched | Confirmed — `ReorderableSongCard` not modified |

---

## Regression Risk Assessment

| Risk | Likelihood | Notes |
|---|---|---|
| `SpecialItemCard` breaks in other usages | None | Only one call site in production code; verified via codebase grep |
| Song reorder regression | None | `ReorderableSongCard` was not modified |
| Non-draggable `SpecialItemCard` regression | None | When `isDraggable: false`, `ReorderableDragStartListener` is not rendered, so `index` is unused |
| `index` parameter is `required` | Safe | The only call site already has access to `index` from `itemBuilder` |

---

## Handoff Notes for QA

- Follow the **Verification Plan** in the Architect Plan (Section 7) for manual test steps.
- Key scenarios: basic drag, drag after delete, mixed song+break drag, last-item edge case.
- The DB trigger (1-based `ROW_NUMBER()`) remains unchanged — a future cleanup migration can address it, but it is no longer a functional issue since the card ignores `item.position` for drag indexing.
