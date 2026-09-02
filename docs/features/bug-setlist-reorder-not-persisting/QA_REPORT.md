# QA REPORT — bug-setlist-reorder-not-persisting

---

## Cycle 2 (current)

| Field | Value |
|---|---|
| **Feature Slug** | `bug-setlist-reorder-not-persisting` |
| **Feature Title** | Setlist reorder not persisting |
| **Cycle Number** | 2 |
| **Branch** | `bug/setlist-reorder-not-persisting` |
| **QA Date** | 2026-09-02 |
| **Final Verdict** | ✅ APPROVED |

---

## Validation Summary

The Cycle 1 critical finding (fix not committed) is **resolved**. Commit `03bb7f7`
(`fix(setlists): use cached state on re-navigation to stop reorder race`) is present on
`origin/bug/setlist-reorder-not-persisting` and confirmed by `git diff main...bug/setlist-reorder-not-persisting`.

The diff is a single-token change — `forceReload: true` → `forceReload: false` — exactly as the
Architect plan specifies. All scope, completeness, behavior, regression, and safety checks pass.

---

## Architect Scope Review

- **Slugs match**: `bug-setlist-reorder-not-persisting` confirmed in both ARCHITECT_PLAN.md and
  ENGINEER_REPORT.md (Cycle 2) ✓
- **Branch naming**: `bug/setlist-reorder-not-persisting` — correct format ✓
- **Plan loaded and reviewed in full** ✓
- **Off-limits files not touched**: Only `lib/features/setlists/setlist_detail_screen.dart` appears
  in the diff; `setlist_detail_controller.dart`, all repositories, all migrations — untouched ✓
- **DB changes required**: None per plan; none present ✓

---

## Completeness Check

| Architect Task | Status |
|---|---|
| Change `forceReload: true` → `forceReload: false` in `SetlistDetailScreen.initState()` | ✅ Committed at line 146, confirmed in source and diff |

Source file (`lib/features/setlists/setlist_detail_screen.dart` line 146) reads `forceReload: false`.
Commit `03bb7f7` is on the branch and pushed to origin. No tasks are missing.

---

## Behavior Verification

*Code-path analysis* — no runtime device testing performed.

**Fix is correct.** `loadSetlist(id, name, forceReload: false)` in the controller enters the
short-circuit guard at line 354:

```dart
if (_setlistId == id && !forceReload) {
  return; // returns cached state; no DB fetch
}
```

When the user drags and backs out, `dispose()` fires `unawaited(persistItemReorder())`. The new
screen instance calls `loadSetlist(..., forceReload: false)` in its `initState` post-frame
callback. Because `_setlistId` already equals the setlist's ID and `forceReload` is now `false`,
the controller returns the cached (correctly reordered) state immediately — no DB SELECT is
issued, so there is no race to lose.

All Architect-specified navigation scenarios verified by code-path analysis:

| Scenario | Expected | Status |
|---|---|---|
| First open of any setlist | `_setlistId == null` → full reload | ✓ |
| Navigate back to same setlist after drag | `_setlistId == id` → cached state, no DB fetch | ✓ (bug fix) |
| Navigate A → B (different setlist) | ID mismatch → reload B | ✓ |
| Navigate B → A | ID mismatch → reload A (prior persist long done) | ✓ |
| Band switch | Provider re-initialises; `_setlistId = null`; next open reloads | ✓ |
| App restart | Provider re-initialises; same as band switch | ✓ |

---

## Regression Check

| System | Risk | Notes |
|---|---|---|
| Setlists (non-Catalog) | LOW | Fix eliminates stale-reload race; all other navigation paths unaffected |
| Setlists (Catalog) | LOW | Same single-line fix; Catalog reorder already worked via fallback |
| Auth / Routing | LOW | No changes |
| Other features | LOW | No changes |
| All platforms (iOS / Android / macOS / web) | LOW | Single-flag change; no platform-conditional code |

---

## Database Safety

Not applicable. No migration files, RPC changes, or schema modifications are present. The
`reorder_setlist_items` RPC, `setlist_songs` positions, and all RLS policies are unchanged and
were confirmed correct in the Architect plan.

---

## Analyzer Results

Ran against the committed file:

```
flutter analyze lib/features/setlists/setlist_detail_screen.dart
Analyzing setlist_detail_screen.dart...
No issues found! (ran in 2.3s)
```

0 errors, 0 warnings, 0 hints.

---

## Test Results

Plan does not require running the test suite; the changed line has no existing test coverage.
Not run.

---

## Diff Safety Review

`git diff main...bug/setlist-reorder-not-persisting` — single hunk, one token changed:

```diff
-            forceReload: true,
+            forceReload: false,
```

- No secrets or API keys ✓
- No debug artifacts or print statements added ✓
- No unrelated formatting churn ✓
- No file deletions ✓

---

## Code Efficiency Review

Single-token substitution. No new code, no dead code, no new imports, no wrapper abstractions,
no defensive checks. No bloat findings.

---

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.

---

## Cycle 1 Archive

The Cycle 1 report (verdict: REQUIRES CHANGES) is preserved below for audit continuity.

---

### Cycle 1 — REQUIRES CHANGES (2026-09-02)

**Final Verdict**: ❌ REQUIRES CHANGES

**Summary**: The fix (`forceReload: true` → `forceReload: false`) was logically correct and
present in the working tree, but was never committed to the feature branch. `git diff
main...bug/setlist-reorder-not-persisting` was empty (zero bytes). The branch HEAD (`a0d8a69`)
was identical to `main`. Fix existed only as an unstaged working-tree modification.

**Issues Found (Cycle 1)**:

| # | Category | Description |
|---|---|---|
| C-1 | `implementation-gap` | Fix not committed — branch HEAD identical to `main`; `git diff main...bug` empty; only an unstaged working-tree hunk was present. |

**Required Actions (Cycle 1)**:
1. Stage and commit `lib/features/setlists/setlist_detail_screen.dart` with the `forceReload: false` change.
2. Push to `origin/bug/setlist-reorder-not-persisting`.
3. Re-submit for QA (Cycle 2).

C-1 is resolved in Cycle 2 by commit `03bb7f7`.
