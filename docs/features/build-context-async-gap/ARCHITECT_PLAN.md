# Architect Plan — Guard BuildContext use after async gap (2 sites)

**Feature Identifier:** `bug/build-context-async-gap`  
**Type:** Bug fix  
**Branch:** `bug/build-context-async-gap`  
**Status:** Ready for Engineer

---

## Problem Summary

`flutter analyze` flags 2 `use_build_context_synchronously` warnings where `BuildContext` is used after an `await` (async gap) without a `mounted` check. If the widget is disposed while the preceding await is in flight (e.g., user navigates away during a song-existence check), using `context` afterward can throw or act on a defunct element.

---

## Root Cause

**Confidence:** HIGH

Both affected methods follow this pattern:

```dart
for (final item in items) {
  final exists = await _songExists(...);  // async gap here

  if (exists) {
    // handle existing
    continue;
  }

  final shouldEnrich = await showEnrichmentConfirmDialog(context, ...);  // ← context used without guard
  ...
}
```

If the widget unmounts during the `_songExists` await, the subsequent `showEnrichmentConfirmDialog(context, ...)` call uses a defunct `BuildContext`. The fix is to insert `if (!mounted) return;` immediately before the `showEnrichmentConfirmDialog` call, aborting the loop if the widget was disposed.

This pattern is already used elsewhere in both files — e.g., `if (mounted) setState(...)` — confirming this is the established lifecycle guard pattern for the codebase.

---

## Exact Sites (verified against `main`)

1. **`lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart:382`**
   - Async gap: line 372 (`await _songExists(row.title, row.artist)`)
   - Unguarded `context` use: line 382 (`showEnrichmentConfirmDialog(context, ...)`)
   - Fix location: insert `if (!mounted) return;` at line 381 (right before the dialog call)

2. **`lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart:214`**
   - Async gap: line 199 (`await _songExists(title, artist)`)
   - Unguarded `context` use: line 214 (`showEnrichmentConfirmDialog(context, ...)`)
   - Fix location: insert `if (!mounted) return;` at line 213 (right before the dialog call)

---

## Solution Design

### Minimal Change Principle

Insert a single line at each site: `if (!mounted) return;`

This guard:

- Aborts the loop iteration if the widget was disposed during the `_songExists` await
- Is a no-op when the widget is still mounted (the common case)
- Follows the existing pattern already present in both files for `setState` calls
- Does not change behavior on the normal (mounted) path

### Files to Modify

1. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
2. `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`

**No other files are in scope.** Do not touch:

- Any other files with analyzer warnings (e.g., `sized_box_for_whitespace` in `reorderable_song_card.dart`, `unused_local_variable` in test files)
- The `showEnrichmentConfirmDialog` function itself
- The `_songExists` method
- Any other part of these two files

---

## Implementation Tasks

### Task 1: Fix `bulk_entry_screen.dart`

**File:** `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

**Location:** After line 380 (the closing `}` of the `if (exists)` block), insert:

```dart
        // New song - always show confirmation dialog (Ask behavior)
        if (!mounted) return;
        final shouldEnrich = await showEnrichmentConfirmDialog(
```

**Exact edit:**

- Insert `if (!mounted) return;` as a new line between the comment `// New song - always show confirmation dialog (Ask behavior)` and the `final shouldEnrich = await showEnrichmentConfirmDialog(` line.

---

### Task 2: Fix `original_song_screen.dart`

**File:** `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`

**Location:** After line 212 (the closing `}` of the `if (exists)` block), insert:

```dart
      // New song - always show confirmation dialog (Ask behavior)
      if (!mounted) return;
      final shouldEnrich = await showEnrichmentConfirmDialog(
```

**Exact edit:**

- Insert `if (!mounted) return;` as a new line between the comment `// New song - always show confirmation dialog (Ask behavior)` and the `final shouldEnrich = await showEnrichmentConfirmDialog(` line.

---

## Database Impact

**Not applicable.** This is pure Flutter widget lifecycle management. No migrations, RLS, RPC, or triggers involved.

---

## System Impact Map

| System             | Impact                                                     |
| ------------------ | ---------------------------------------------------------- |
| Gigs               | unaffected                                                 |
| Rehearsals         | unaffected                                                 |
| Setlists / Catalog | affected (bulk entry + original song add-to-setlist flows) |
| Members / RBAC     | unaffected                                                 |
| Auth / Session     | unaffected                                                 |
| Routing            | unaffected                                                 |

---

## Verification Plan

**Engineer must confirm:**

1. **`flutter analyze`:** 0 `use_build_context_synchronously` warnings at these 2 sites
2. **No new issues introduced:** Analyzer output should not show new warnings or errors
3. **`flutter test`:** All existing tests pass
4. **Code-path analysis:** Verify the guard placement does not change behavior on the normal (mounted) path — the `if (!mounted) return;` is a no-op when the widget is still mounted, which is the common case

**QA must verify:**

1. Analyzer confirms the lint is resolved at both sites
2. No regression in bulk entry or original song flows
3. No new analyzer warnings introduced

**No manual QA required.** The lint itself is proof the guard is correctly placed. Code-path analysis is sufficient to confirm the guard does not alter normal behavior.

---

## Constraints

- **Scope:** Fix ONLY these 2 sites
- **No refactors:** Do not refactor `_songExists`, `showEnrichmentConfirmDialog`, or any other code
- **No opportunistic cleanup:** Do not fix the `sized_box_for_whitespace` or `unused_local_variable` analyzer issues
- **Minimal diff surface:** Each fix is a single line insertion

---

## Edge Cases

**What if `_songExists` takes a long time and the user navigates away?**

- Without the guard: `showEnrichmentConfirmDialog(context, ...)` would use a defunct context, potentially throwing or acting on a disposed widget.
- With the guard: The loop aborts cleanly via `if (!mounted) return;`, preventing the error.

**What if the user stays on the screen?**

- The guard is a no-op (`mounted` is `true`), so behavior is unchanged.

---

## Approval

This plan is ready for Engineer implementation.

**Architect:** GitHub Copilot  
**Date:** 2026-08-23
