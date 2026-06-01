# QA Report — bug/rehearsal-edit-setlist-spinner

**Commit reviewed:** `de94631`
**Branch:** `main` (after merging `bug/cleanup-p1-p2-p3` via merge commit `a84d426`)
**QA date:** 2026-05-27
**Verdict:** ✅ APPROVED

---

## Phase 0 — Rules Loaded

- `docs/agents/GUARDRAILS.md` — read in full. ✅
- `docs/agents/QA.md` — read in full. ✅

---

## Phase 1 — Workspace State

```
git log --oneline -3
de94631 (HEAD -> main) fix(setlists): guard stateOrNull in loadSetlists() to fix infinite spinner
a84d426 merge: bug/cleanup-p1-p2-p3
19b35e6 fix(setlists,members,profile): remove dead code, fix silent errors, reactive setlists
```

Commit `de94631` is confirmed at HEAD on `main`. Working tree is clean.

---

## Phase 2 — Documents Loaded

Both required documents were loaded from the correct slug path:

- `docs/features/bug/rehearsal-edit-setlist-spinner/ARCHITECT_PLAN.md` — ✅ present, read in full
- `docs/features/bug/rehearsal-edit-setlist-spinner/ENGINEER_REPORT.md` — ✅ present, read in full

Feature slug matches across both documents and the working commit message. ✅

---

## Phase 3 — Validation Baseline (Architect Plan §13)

Extracted from Plan §13:

| #   | Criterion                                                                                   |
| --- | ------------------------------------------------------------------------------------------- |
| 1   | `flutter analyze` passes with 0 errors                                                      |
| 2   | Edit Rehearsal sheet: Setlist section loads and shows setlist pills (no indefinite spinner) |
| 3   | Creating a new setlist from the sheet still works                                           |
| 4   | Switching bands: `setlistsProvider` reloads correctly                                       |
| 5   | `SetlistsScreen` loads and displays setlists correctly                                      |
| 6   | `setlistsProvider.notifier.refresh()` shows loading indicator during refresh                |

- **Files expected to change:** `lib/features/setlists/setlists_screen.dart`
- **Files off-limits:** `setlist_repository.dart`, all migrations/RLS files, `pubspec.yaml`, `pubspec.lock`, all other source files
- **Database impact:** Not applicable
- **Architecture changes:** None

---

## Phase 4 — Scope Review

### Files changed in commit `de94631`

```
git show de94631 --name-only
docs/features/bug/rehearsal-edit-setlist-spinner/ARCHITECT_PLAN.md  (new — docs)
docs/features/bug/rehearsal-edit-setlist-spinner/ENGINEER_REPORT.md (new — docs)
lib/features/setlists/setlists_screen.dart                           (modified — source)
```

**Source code:** Exactly one source file modified — `lib/features/setlists/setlists_screen.dart`. ✅

**Docs:** Two docs files added (`ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`). These are Architect/Engineer deliverables expected by the workflow; they are not source changes. ✅

**Off-limits files:** `setlist_repository.dart`, migrations, schema, RLS files, `pubspec.yaml`, `pubspec.lock` — none touched. ✅

---

## Phase 5 — Completeness Check

### Plan §10 exact edit — confirmed present

**Diff (from `git show de94631 -- lib/features/setlists/setlists_screen.dart`):**

```diff
-    // Update state to loading
-    state = state.copyWith(isLoading: true, clearError: true);
+    // Only set loading explicitly if the notifier is already initialized.
+    // When called directly from build(), state is uninitialized and reading it
+    // throws StateError. build() already returns isLoading: true for that path.
+    if (stateOrNull != null) {
+      state = state.copyWith(isLoading: true, clearError: true);
+    }
```

Guard is at line 108 in the post-fix file, immediately after the `bandId` null guard and before the `try` block — matching the Plan §10 exact edit description. ✅

No task in the Architect plan was skipped or partially implemented. ✅

---

## Phase 6 — Behavior Verification

**Method of verification:** Code-path analysis. Runtime device testing was not performed.

### Root cause addressed

The root cause identified by the Architect was: `state = state.copyWith(...)` at line 106 (pre-fix) running synchronously during `build()` before Riverpod had initialized the provider state, causing `StateError` and silently aborting `loadSetlists()`.

The fix uses `stateOrNull` — Riverpod's explicitly documented safe API for `build()` context — as a guard:

- **`build()` call path:** `stateOrNull == null` → guard skips the `state.copyWith(...)` mutation → `loadSetlists()` proceeds past the guard to the first `await` without error → `build()` returns `SetlistsState(isLoading: true)` as the initial state → async resumes, fetch completes, post-`await` state assignments succeed. ✅
- **Post-build call path (refresh, band switch):** `stateOrNull` is the current non-null `SetlistsState` → guard allows the mutation → loading indicator is shown during refresh as before. ✅

The `try` block, `_repository.fetchSetlistsForBand(bandId)` call, and all success/error state assignments (`state.copyWith(setlists:..., isLoading: false)`, all `catch` branches) are outside the guard and unchanged. ✅

### Criterion 2 — Indefinite spinner

Code-path analysis confirms the provider now resolves to a loaded or error state after the async fetch completes. The `buildSetlistSelector()` in `event_form_fields.dart` checks `setlistsState.isLoading`; this will now transition to `false` once the fetch resolves. **Confirmed via code-path analysis only; not validated on a device.**

### Criterion 3 — New setlist creation from sheet

No changes to navigation or post-creation refresh paths. `duplicateSetlist()` calls `loadSetlists()` which is now safe post-build. ✅ (code-path analysis)

### Criterion 4 — Band switching

`build()` watches `activeBandIdProvider`; Riverpod re-runs `build()` on band switch. The fixed `loadSetlists()` is safe to call from `build()`. ✅ (code-path analysis)

### Criterion 5 — SetlistsScreen load

Post-fix `build()` returns `SetlistsState(isLoading: true)`; async completes with populated `setlists`. `SetlistsScreen` displays correctly. ✅ (code-path analysis)

### Criterion 6 — `refresh()` loading indicator

`refresh()` delegates to `loadSetlists()`. When called post-build, `stateOrNull` is non-null → the guard passes → `state = state.copyWith(isLoading: true, clearError: true)` executes → UI shows loading indicator. ✅ (code-path analysis)

---

## Phase 7 — Regression Check

### System impact (per Architect §8)

**Database:** Not applicable — no queries, RPC calls, or schema changed.

**Riverpod state shape:** `SetlistsState` is unchanged. `setlistsProvider` type and API are unchanged. ✅

**`build()` method:** Return value and body are identical to the post-P3 state. ✅

**`deleteSetlist()`:** Unchanged. Reads and writes `state` only after the first `await` (the `_repository.deleteSetlist()` call returns), by which time `state` is always initialized. ✅

**`reorderLocal()`:** Unchanged. Called only from UI interaction, always post-build. ✅

**`persistReorder()`:** Unchanged. Called only post-build. ✅

**`refresh()`:** Delegates to `loadSetlists()`. Correct behavior confirmed above in Phase 6 §Criterion 6. ✅

**`duplicateSetlist()`:** Calls `loadSetlists()` internally after the first `await`. At that point `state` is initialized. ✅

**Async lifecycle (GUARDRAILS §5):** No `setState` calls — this is a `Notifier`, not a `StatefulWidget`. No `FocusNode`, `TextEditingController`, or `ScrollController` involved. ✅

**Auth / Supabase:** No changes to auth flow, RPC calls, or RLS. ✅

**Initialization order:** Unchanged. ✅

### Regression risk: **LOW**

The change is a two-line conditional wrapper around a single existing assignment. No logic was moved, added, or removed outside the guard.

---

## Phase 8 — Database Safety

Not applicable. No migrations, schema changes, RLS policies, or RPC function signatures were modified.

---

## Phase 9 — Static Analysis

```
flutter analyze
Analyzing bandroadie...
No issues found! (ran in 4.6s)
```

**Result: PASS — 0 errors, 0 warnings.** ✅

---

## Phase 10 — Diff Safety Review

Inspected `git show de94631`:

- No secrets or API keys. ✅
- No environment variables or config outside approved scope. ✅
- No debug artifacts left in production code (the existing `kDebugMode` debug prints in `loadSetlists()` were present pre-fix and are not new). ✅
- No test scaffolding in production code. ✅
- No accidental file deletions. ✅
- Commit message format matches `fix(scope): description` convention. ✅

---

## Summary

| Check                                                | Result       |
| ---------------------------------------------------- | ------------ |
| Commit confirmed at HEAD                             | ✅ `de94631` |
| Only `setlists_screen.dart` changed (source)         | ✅ Confirmed |
| Guard wraps only the pre-`await` state mutation      | ✅ Confirmed |
| `try` block and fetch call unchanged                 | ✅ Confirmed |
| All other `SetlistsNotifier` methods untouched       | ✅ Confirmed |
| `build()` return value unchanged                     | ✅ Confirmed |
| `flutter analyze` 0 errors                           | ✅ Confirmed |
| No secrets, debug artifacts, or unintended deletions | ✅ Confirmed |
| Database safety                                      | N/A          |
| Regression risk                                      | LOW          |

---

## Verdict

**APPROVED**

The implementation matches Plan §10 exactly. The root cause is correctly addressed via Riverpod's `stateOrNull` safe API. Change surface is minimal (4 added lines, 2 removed). Static analysis passes with 0 issues. No regressions identified.

> **Note:** Runtime behavior (Edit Rehearsal sheet spinner resolution, device testing on iOS/Android/macOS) was not exercised — all verification above is via code-path analysis. The Architect plan does not require device testing as a QA gate.
