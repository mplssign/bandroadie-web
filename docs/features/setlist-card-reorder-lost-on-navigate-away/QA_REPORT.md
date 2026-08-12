# QA Report — Setlist Card Reorder Lost on Navigate Away

## Feature Slug

`bug/setlist-card-reorder-lost-on-navigate-away`

## Branch Verification

**Branch:** `bug/setlist-card-reorder-lost-on-navigate-away` ✓  
**Working Tree:** Clean except for expected changes ✓

```
Modified:   lib/features/setlists/setlists_tab_content.dart
Untracked:  docs/features/setlist-card-reorder-lost-on-navigate-away/ENGINEER_REPORT.md
```

---

## Verdict

**APPROVED**

The implementation matches the Architect plan exactly. All verification points pass. The dispose()-flush pattern is correctly applied to prevent data loss when users navigate away before the 500ms debounce timer fires.

---

## Verification Results

### ✓ Point 1: dispose() Only Fires Flush When Timer is Active

**Confirmed in code.**

The implementation correctly guards the flush logic:

```dart
if (_reorderDebounceTimer != null && _reorderDebounceTimer!.isActive) {
  _reorderDebounceTimer!.cancel();
  unawaited(ref.read(setlistsProvider.notifier).persistReorder());
}
```

**Analysis:**

- Normal dispose with no pending reorder: conditional check fails, no persist call triggered ✓
- Dispose with pending reorder: conditional check passes, flush fires ✓
- Timer already fired naturally: `.isActive` returns false, no double-fire ✓

This matches the Architect plan requirement that "a normal dispose with no pending reorder should not trigger a persist call."

---

### ✓ Point 2: Single Reorder Path Confirmed

**Confirmed in code** (lines 175-203 of `setlists_tab_content.dart`).

The `_handleReorder` method has **only one execution path:**

```dart
void _handleReorder(int oldIndex, int newIndex) {
  final notifier = ref.read(setlistsProvider.notifier);
  notifier.reorderLocal(oldIndex, newIndex);
  _reorderDebounceTimer?.cancel();
  _reorderDebounceTimer = Timer(const Duration(milliseconds: 500), () async {
    if (!mounted) return;
    final success = await notifier.persistReorder();
    if (!success && mounted) {
      showErrorSnackBar(context, message: 'Failed to reorder setlists');
    }
  });
}
```

**Key findings:**

- No branching logic based on item type (Catalog vs. non-Catalog)
- All setlist cards use the same handler
- All reorders unconditionally call `persistReorder()` after debounce
- Unlike the song-reorder fix (which had two paths for Catalog/mixed-items), this file has a single straightforward path

**Conclusion:** No conditional logic needed in `dispose()` — the Architect plan's single-path design is correct.

---

### ✓ Point 3: setlistsProvider is Plain NotifierProvider

**Confirmed in code** (line 297 of `lib/features/setlists/setlists_screen.dart`).

```dart
final setlistsProvider = NotifierProvider<SetlistsNotifier, SetlistsState>(
  SetlistsNotifier.new,
);
```

**Analysis:**

- Provider is NOT `.autoDispose` ✓
- Notifier survives widget teardown long enough for RPC to complete ✓
- Calling `ref.read(setlistsProvider.notifier).persistReorder()` from `dispose()` is safe ✓

This confirms the Architect plan's assertion that the fire-and-forget pattern is valid.

---

### ✓ Point 4: dart:async Import Has No show Clause

**Confirmed in code** (line 1 of `lib/features/setlists/setlists_tab_content.dart`).

```dart
import 'dart:async';
```

**Analysis:**

- Bare import with no `show` clause ✓
- Both `Timer` and `unawaited` are fully available ✓
- File also imports `package:flutter/material.dart` unrestricted (line 3), which re-exports `unawaited` ✓
- No `unused_shown_name` warning will occur ✓

The Engineer correctly followed Task 3 of the Architect plan: "Not applicable. The file already has `import 'dart:async';` without a `show` clause."

---

### ✓ Point 5: persistReorder() Has Snapshot/Rollback Safety

**Confirmed in code** (lines 234-293 of `lib/features/setlists/setlists_screen.dart`).

**Snapshot creation** (in `reorderLocal()`, line 244):

```dart
_preReorderSnapshot ??= List.of(state.setlists);
```

**Success path** (in `persistReorder()`, line 279):

```dart
await _repository.reorderSetlists(bandId: bandId, setlistIdsInOrder: ids);
_preReorderSnapshot = null; // Clear snapshot on success
return true;
```

**Failure path** (in `persistReorder()`, lines 286-289):

```dart
if (_preReorderSnapshot != null) {
  final revertState = state.copyWith(setlists: _preReorderSnapshot);
  state = revertState;
  _preReorderSnapshot = null;
}
return false;
```

**Analysis:**

- Snapshot is captured before any reorder operation ✓
- Snapshot is cleared on successful persist ✓
- Snapshot is used to rollback state on persist failure ✓
- Even if the fire-and-forget call from dispose() fails, the rollback mechanism prevents data corruption ✓

This confirms the Architect plan's assertion that "fire-and-forget failure from dispose doesn't leave state inconsistent."

---

### ✓ Point 6: No Other Files Modified

**Confirmed via git status.**

Only the expected file was modified:

- `lib/features/setlists/setlists_tab_content.dart` — dispose() method updated per Architect plan ✓

Documentation added:

- `docs/features/setlist-card-reorder-lost-on-navigate-away/ENGINEER_REPORT.md` — Engineer report per plan ✓
- `docs/features/setlist-card-reorder-lost-on-navigate-away/QA_REPORT.md` — This report ✓

**No off-limits files were touched:**

- `lib/main.dart` — unchanged ✓
- `lib/features/setlists/setlists_screen.dart` — unchanged ✓
- `lib/features/setlists/setlist_repository.dart` — unchanged ✓
- `supabase/migrations/*.sql` — unchanged ✓

---

## Implementation Review

### Code-Path Analysis

**dispose() implementation:**

The dispose method now checks if a reorder is pending before flushing:

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

**What changed:**

- **Before:** `_reorderDebounceTimer?.cancel();` (always canceled, never flushed)
- **After:** Conditional check → if timer is active, cancel + fire-and-forget persist

**What stayed the same:**

- Debounce duration (500ms) unchanged ✓
- Reorder logic (`_handleReorder`) unchanged ✓
- Persist logic (`persistReorder()`) unchanged ✓
- Snapshot/rollback mechanism unchanged ✓

---

## Completeness Check

### Architect Task Breakdown

All tasks completed per Engineer Report:

- [x] Task 1 — Verified current dispose() behavior ✓
- [x] Task 2 — Confirmed single reorder path (no branching) ✓
- [x] Task 3 — Not applicable (dart:async import already present) ✓
- [x] Task 4 — Modified dispose() to flush pending reorder ✓
- [x] Task 5 — Verified no syntax errors (`flutter analyze` on modified file) ✓
- [x] Task 6 — Verified no build regressions (`flutter analyze` on full project) ✓
- [x] Task 7 — Documented changes in Engineer Report ✓

**No skipped requirements. No partial implementations. No missing edge-case handling.**

---

## Behavior Verification

### Root Cause Addressed

**Bug:** User drags setlist card to new position, navigates away quickly (< 500ms), reorder is silently discarded.

**Root cause:** `dispose()` method canceled `_reorderDebounceTimer` without triggering the scheduled `persistReorder()` callback.

**Fix:** `dispose()` now checks if timer is active and, if so, fires `persistReorder()` as an unawaited call before cleanup.

**Validation method:** Code-path analysis (runtime testing is out of scope for QA per user instructions).

**Conclusion:** Root cause is directly addressed. The persist call that was being lost is now guaranteed to fire (even if as fire-and-forget).

---

## Regression Check

### System Impact Map Review

Per Architect plan, only one system is affected:

| System             | Impact     | Regression Risk |
| ------------------ | ---------- | --------------- |
| Setlists / Catalog | affected   | LOW             |
| All other systems  | unaffected | NONE            |

### Regression Analysis

**Setlists / Catalog:**

- Change is localized to `dispose()` lifecycle method
- Does not touch reorder logic, persist logic, or any repository/RPC code
- Fire-and-forget persist uses the same guarded method already proven correct
- Snapshot/rollback mechanism prevents data corruption even on failure
- Catalog position logic unchanged (Catalog is excluded from reorder RPC, per `persistReorder()` implementation)

**Auth and session behavior:** Unaffected (no auth/session code touched) ✓  
**Supabase RPC calls:** Unaffected (same RPC signature, parameter count, argument ordering) ✓  
**Initialization order:** Unaffected (no `main.dart` changes) ✓  
**Controller and FocusNode disposal:** Unaffected (`_entranceController.dispose()` still called correctly) ✓  
**setState after async gaps:** Not applicable (no `setState` calls in modified code) ✓  
**Rebuild triggers and frequency:** Unaffected (no state management changes) ✓

### Regression Risk Level

**LOW**

**Rationale:**

- Single file modified
- Change isolated to `dispose()` method
- Pattern already validated on sibling screen (`bug/song-reorder-lost-on-navigate-away`)
- Worst-case failure mode: persist fails silently (same as current behavior for quick-exit, but with an attempt made)
- Snapshot/rollback mechanism remains intact

---

## Manual Testing Required

The following manual tests from the Architect plan remain for Tony to execute on-device:

### Test 1: Quick-Exit Reorder (Primary Bug Fix)

**Steps:**

1. Open Setlists tab
2. Drag a setlist card to a new position
3. Immediately (< 500ms) navigate to a different tab
4. Return to Setlists tab
5. Observe: dragged setlist card is still in the new position (not reverted)

**Expected:** Reorder persists despite quick navigation away.

**Status:** Ready for manual testing.

---

### Test 2: Normal Reorder (No Regression)

**Steps:**

1. Open Setlists tab
2. Drag a setlist card to a new position
3. Wait 1 second (> 500ms)
4. Navigate away and return
5. Observe: dragged setlist card is still in the new position

**Expected:** Normal reorder flow still works (no regression).

**Status:** Ready for manual testing.

---

### Test 3: Multiple Quick Reorders

**Steps:**

1. Open Setlists tab
2. Drag setlist card A to position 1
3. Immediately drag setlist card B to position 2
4. Immediately drag setlist card C to position 3
5. Immediately (< 500ms after last drag) navigate away
6. Return to Setlists tab
7. Observe: all three reorders persisted

**Expected:** Most recent reorder persists; earlier reorders may have been coalesced by debounce, but no data corruption occurs.

**Status:** Ready for manual testing.

---

### Test 4: Catalog Position Preserved

**Steps:**

1. Open Setlists tab
2. Verify Catalog setlist is at the top (position 0)
3. Drag a non-Catalog setlist to a new position
4. Immediately navigate away
5. Return to Setlists tab
6. Observe: Catalog is still at the top, and dragged setlist is in the new position

**Expected:** Catalog position is not affected by reordering non-Catalog setlists.

**Status:** Ready for manual testing.

---

### Test 5: Cross-Platform Consistency

**Repeat Test 1 on:**

- iOS
- Android
- Web
- macOS

**Expected:** Reorder persists on all platforms.

**Status:** Ready for manual testing.

---

## Additional Observations

### Pattern Consistency

This is the third fix in a series applying the same dispose()-flush pattern:

1. **First:** `setlist_repository.dart` — sort logic flush on dispose
2. **Second:** `setlist_detail_screen.dart` — song reorder flush on dispose (commit `241321d`, branch `bug/song-reorder-lost-on-navigate-away`)
3. **Third (this fix):** `setlists_tab_content.dart` — setlist card reorder flush on dispose

**Pattern validation:**

- Same conditional check (`_timer != null && _timer!.isActive`)
- Same fire-and-forget approach (`unawaited(...)`)
- Same provider safety requirement (not `.autoDispose`)
- Same snapshot/rollback mechanism in persist method

This fix correctly applies the validated pattern to a new location.

---

### Why Fire-and-Forget is Acceptable

**Current behavior (before fix):**

- 100% of quick-exit reorders are lost
- User sees reordered list locally, but database keeps old order
- Silent data loss

**New behavior (after fix):**

- Persist attempt fires even on quick-exit
- Failure won't be visible to user (screen is disposed)
- Snapshot/rollback prevents corruption
- **Strict improvement over current behavior**

The Architect plan correctly identifies this as an acceptable trade-off: "acceptable since screen is gone."

---

## Documentation Quality

**Engineer Report:**

- All required sections present ✓
- Verification steps clearly documented ✓
- Before/after state comparison included ✓
- Analyzer results reported (0 new errors/warnings) ✓
- Deviations: None (correct) ✓
- Ready for QA: Yes ✓

**Architect Plan adherence:** 100% — no deviations, no scope creep.

---

## Final Checklist

- [x] Architect plan reviewed and used as validation authority
- [x] Guardrails reviewed (no violations detected)
- [x] Branch verified (`bug/setlist-card-reorder-lost-on-navigate-away`)
- [x] Working tree state verified (clean except expected changes)
- [x] Engineer Report reviewed (complete and accurate)
- [x] Git diff reviewed (matches Engineer Report)
- [x] All six verification points from user request confirmed
- [x] Implementation matches Architect plan exactly
- [x] No off-limits files modified
- [x] No architectural patterns changed
- [x] Change surface is minimal
- [x] All Architect tasks completed
- [x] No skipped requirements
- [x] Root cause directly addressed
- [x] Regression risk assessed: LOW
- [x] Manual tests documented for Tony

---

## Approval

**Status:** APPROVED

**Reasoning:**

- Implementation matches Architect plan exactly (no deviations)
- All six verification points pass
- Single reorder path confirmed (no branching needed)
- Fire-and-forget pattern correctly applied
- Snapshot/rollback safety mechanism intact
- No regressions introduced (code-path analysis)
- Only expected file modified
- Pattern validated on sibling screen
- Ready for manual device testing

**Next Steps for Tony:**

1. Commit changes: `git add lib/features/setlists/setlists_tab_content.dart docs/features/setlist-card-reorder-lost-on-navigate-away/`
2. Commit message: `fix(setlists): flush pending setlist card reorder on dispose`
3. Run manual Tests 1-5 on device (iOS, Android, Web, macOS)
4. Push branch and open PR if tests pass

---

**QA Validation Method:** Code-path analysis (per user instructions, runtime testing out of scope)  
**Report Generated:** 2026-08-12  
**QA Agent:** GitHub Copilot
