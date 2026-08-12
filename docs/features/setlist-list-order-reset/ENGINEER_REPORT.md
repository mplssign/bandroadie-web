# Engineer Report: Fix Setlist List Order Reverting to Alphabetical

## Implementation Status

**COMPLETE** — 2026-08-12

Branch: `bug/setlist-list-order-reset`  
Commit at start: `db716fe fix(architect): correct setlist sort logic to handle default position ties`

## Pre-Implementation Verification

### Git State

- ✅ Branch confirmed: `bug/setlist-list-order-reset`
- ✅ HEAD commit: `db716fe` (correct)
- ⚠️ Working tree status:
  - `M docs/features/setlist-list-order-reset/ARCHITECT_PLAN.md` — minor whitespace change (blank line before code block), does not affect implementation
  - `?? docs/features/setlist-list-order-reset/ENGINEER_REPORT.md` — this file (expected untracked)

### Task 2: Setlist.position Field Verification

File: `lib/features/setlists/models/setlist.dart`

**Result:** ✅ `Setlist.position` is a **non-null `int`** field

```dart
// Line 60
final int position;

// Line 69 (constructor)
this.position = 0,
```

**Analysis:**

- Field type: `int` (not `int?`)
- Default value: `0`
- Supports `.compareTo()` natively (no defensive null handling required)
- No deviation from plan necessary

## Files Modified

### lib/features/setlists/setlist_repository.dart

**Location:** Lines 499-504 (unconditional sort block)

**Before:**

```dart
      // Sort: Catalog first, then alphabetically
      setlists.sort((a, b) {
        if (a.isCatalog && !b.isCatalog) return -1;
        if (!a.isCatalog && b.isCatalog) return 1;
        return a.name.compareTo(b.name);
      });
```

**After:**

```dart
      // Sort: conditional based on position column availability
      if (hasPositionColumn) {
        // Position column exists — use three-tier sort:
        // 1. Catalog always first (regardless of its position value)
        // 2. Then by position ascending (respects manual reorder)
        // 3. Then alphabetically (deterministic tiebreak for default position = 0)
        setlists.sort((a, b) {
          // Catalog always first
          if (a.isCatalog != b.isCatalog) return a.isCatalog ? -1 : 1;
          // Then by position
          final posCompare = a.position.compareTo(b.position);
          if (posCompare != 0) return posCompare;
          // Then alphabetically (tiebreak when positions are equal/default)
          return a.name.compareTo(b.name);
        });
      } else {
        // Position column missing — fall back to alphabetical sort
        setlists.sort((a, b) {
          if (a.isCatalog && !b.isCatalog) return -1;
          if (!a.isCatalog && b.isCatalog) return 1;
          return a.name.compareTo(b.name);
        });
      }
```

**Change Summary:**

- Replaced unconditional 6-line sort with conditional 25-line sort
- When `hasPositionColumn == true`: Three-tier sort (Catalog first, then position ascending, then name alphabetically)
- When `hasPositionColumn == false`: Legacy Catalog-first-then-alphabetical sort (unchanged behavior)
- Preserved existing comment structure and context
- No changes to surrounding code or debug logging

## Implementation Details

### Three-Tier Sort Logic

**Tier 1: Catalog-First Guarantee**

```dart
if (a.isCatalog != b.isCatalog) return a.isCatalog ? -1 : 1;
```

- Explicitly checks `isCatalog` flag before any position comparison
- Ensures Catalog appears first even when its position is 0 (same as 89% of production setlists)

**Tier 2: Position-Based Order**

```dart
final posCompare = a.position.compareTo(b.position);
if (posCompare != 0) return posCompare;
```

- Respects manual reorder for bands that have dragged setlists (positions are 1, 2, 3...)
- Position comparison only affects sort when positions differ

**Tier 3: Alphabetical Tiebreaker**

```dart
return a.name.compareTo(b.name);
```

- Executes when positions are equal (common: 89% of production setlists have default position = 0)
- Provides deterministic, stable ordering to prevent PostgreSQL tie-order churn
- Reproduces exact pre-fix visual behavior for non-reordered bands

### Fallback Branch (Position Column Missing)

Preserved legacy sort logic unchanged:

```dart
setlists.sort((a, b) {
  if (a.isCatalog && !b.isCatalog) return -1;
  if (!a.isCatalog && b.isCatalog) return 1;
  return a.name.compareTo(b.name);
});
```

- Executes when `hasPositionColumn == false` (schema rollback or pre-migration environment)
- Matches original behavior: Catalog first, then alphabetically

## Verification Results

### Static Analysis

```bash
flutter analyze
```

**Result:** ✅ 0 errors

**Pre-existing issues (not introduced by this change):**

- 2 warnings in `bulk_entry_screen.dart` (unused import, unused variable)
- 2 info messages in `bulk_entry_screen.dart` and `original_song_screen.dart` (BuildContext across async gaps)

All issues exist in files not touched by this implementation.

### Exception Handler Consistency Audit

Verified all exception handlers that set `hasPositionColumn = false`:

| Line Range | Catch Block                             | Sets Flag                                 | Verified |
| ---------- | --------------------------------------- | ----------------------------------------- | -------- |
| 287-295    | `if (e.message.contains('position'))`   | ✅ Line 291: `hasPositionColumn = false;` | ✅       |
| 296-305    | `if (e.message.contains('is_catalog'))` | ❌ (not position-related)                 | ✅       |

**Conclusion:** The conditional sort will execute correctly. When the position column is missing, `hasPositionColumn` is set to `false` and the fallback alphabetical sort executes.

## Files Confirmed Unmodified

Per the Architect plan's "Files Off-Limits" section, verified these files remain untouched:

- ✅ `lib/main.dart` — no changes
- ✅ `lib/features/setlists/setlists_screen.dart` — no changes
- ✅ `lib/features/setlists/setlists_tab_content.dart` — no changes
- ✅ `lib/features/setlists/new_setlist_screen.dart` — no changes
- ✅ `lib/features/setlists/setlist_detail_screen.dart` — no changes
- ✅ `lib/features/setlists/setlist_detail_controller.dart` — no changes
- ✅ `supabase/migrations/*.sql` — no changes
- ✅ No RPC functions modified

## Deviations from Plan

**NONE**

All implementation tasks were completed exactly as specified in `ARCHITECT_PLAN.md`:

1. ✅ Verified current state (method location, variable declaration, sort block location)
2. ✅ Verified `Setlist.position` is non-null `int` (supports `.compareTo()`, no defensive handling needed)
3. ✅ Implemented three-tier conditional sort as specified
4. ✅ Verified exception handler consistency
5. ✅ Ran static analysis (0 errors)
6. ✅ Generated implementation report (this document)

## Next Steps (Post-Implementation)

Per the Architect plan's Verification Plan:

### Tier 1 — Pre-deployment Testing (Manual)

**Test 1: Fetch with position column — manually reordered band**

- Open Setlists tab for a band with unique positions (1, 2, 3...)
- Verify setlists display in user-defined order (not alphabetical)
- Verify Catalog appears first

**Test 2: Fetch with position column — band with default positions**

- Create/use a band with all setlists at position = 0
- Add setlists with names that differ from alphabetical order (e.g., "Zebra", "Alpha", "Beta")
- Verify Catalog appears first
- Verify remaining setlists appear in alphabetical order
- Verify order remains stable across pull-to-refresh and app restart

**Test 4: Recursive call idempotence**

- Delete Catalog for a test band (forces Catalog creation flow)
- Verify final list respects position order after recursive fetch
- Verify Catalog appears first

### Tier 2 — Post-deployment Validation (Production)

**Test 2: End-to-end reorder + fetch cycle**

- Drag setlist from position 2 to position 5
- Pull-to-refresh → verify order persists
- Close app completely → reopen → verify order persists

**Test 3: Cross-platform consistency**

- Repeat Test 2 on iOS, Android, macOS, Web
- Verify order persists across all platforms

## Implementation Confidence

**HIGH**

**Rationale:**

- Single-method, single-block change in fetch path
- Conditional logic explicitly handles both cases (position column present/absent)
- No state management, routing, or auth logic touched
- `Setlist.position` field is non-null, no edge cases with null handling
- Three-tier sort logic is deterministic and matches production data patterns
- Alphabetical tiebreak reproduces exact pre-fix behavior for 89% of bands (no user-visible churn)

**Risk factors accounted for:**

- Change is gated behind `hasPositionColumn` boolean with robust exception handling
- Legacy fallback path preserved unchanged for schema rollback scenarios
- Sort logic is idempotent (safe for recursive calls at any depth)

---

**Engineer:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-12  
**Branch:** `bug/setlist-list-order-reset`  
**Commit:** Implementation complete (not committed per Engineer rules)
