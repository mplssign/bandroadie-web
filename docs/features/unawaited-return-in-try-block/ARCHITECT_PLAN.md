# ARCHITECT_PLAN.md

## Feature Slug

`bug/unawaited-return-in-try-block`

---

## Problem Summary

Four sites in the codebase use the pattern `return asyncCall();` inside `try` blocks without awaiting the call. This causes any exception thrown by the async call to bypass the local `catch` handler entirely, propagating uncaught to the caller instead of being handled where the surrounding code structure implies it should be caught.

This defect was discovered during QA verification of the `feature/ci-analyze-test-gate` feature when `flutter analyze` was run on Flutter 3.47.1 (the CI runner's stable channel version). The analyzer flagged these 4 sites with the `unawaited_return_in_try_block` lint rule — a rule not active on local Flutter 3.44.6, explaining why this pre-existing issue was not visible during local development.

**Why this matters:**

- The code visually reads as if exceptions are caught and handled locally
- Runtime behavior silently contradicts that visual contract
- Recovery paths (deduplication, catalog creation, metadata correction) fail without logging
- Exception context is lost as errors propagate upward uncaught

---

## Root Cause

**Confidence Level:** HIGH (directly observable in code)

When a `try` block contains `return someAsyncCall();` without `await`, the Future object is returned immediately. The async work executes outside the scope of the try/catch. Any exception thrown by that Future propagates to the method's caller, not to the local `catch` handler.

**The 4 affected sites:**

1. **`lib/features/setlists/setlist_repository.dart:448`**  
   Inside Catalog deduplication recovery path:

   ```dart
   try {
     await deduplicateCatalogs(bandId);
     return _fetchSetlistsForBandInternal(bandId, depth + 1); // <- missing await
   } catch (e) {
     // This catch never runs if _fetchSetlistsForBandInternal throws
   ```

2. **`lib/features/setlists/setlist_repository.dart:467`**  
   Inside "no Catalog exists, create one" recovery path:

   ```dart
   try {
     await ensureCatalogSetlist(bandId);
     return _fetchSetlistsForBandInternal(bandId, depth + 1); // <- missing await
   } catch (e) {
     // This catch never runs if _fetchSetlistsForBandInternal throws
   ```

3. **`lib/features/setlists/setlist_repository.dart:486`**  
   Inside Catalog metadata correction recovery path:

   ```dart
   try {
     await _ensureCatalogMetadata(catalog.id, catalog.name);
     return _fetchSetlistsForBandInternal(bandId, depth + 1); // <- missing await
   } catch (e) {
     // This catch never runs if _fetchSetlistsForBandInternal throws
   ```

4. **`lib/features/setlists/setlist_detail_controller.dart:2218`**  
   Inside queued reorder re-persist path:
   ```dart
   try {
     await _specialItemRepo.reorderItems(...);
     _isItemReorderInFlight = false;
     if (_itemReorderPendingAfterFlight) {
       _itemReorderPendingAfterFlight = false;
       return persistItemReorder(); // <- missing await
     }
   } catch (e) {
     // This catch never runs if persistItemReorder throws
   ```

---

## Reference Docs Consulted

**Notification domain reference:** Not applicable (per explicit override — this feature does not involve notifications).

**Other reference docs consulted:** None required — this is a surgical lint fix with no architectural implications.

---

## Existing System Analysis

### Setlist Repository Recovery Paths (Sites 1-3)

`_fetchSetlistsForBandInternal()` is a recursive method that fetches all setlists for a band and performs three validation/recovery steps if integrity issues are detected:

1. **Multiple Catalogs detected** → run deduplication, then re-fetch (line 448)
2. **No Catalog exists** → create Catalog, then re-fetch (line 467)
3. **Catalog metadata wrong** → correct metadata, then re-fetch (line 486)

Each recovery path is wrapped in a `try/catch` that logs failure and continues with existing (possibly inconsistent) data rather than crashing. The catch handlers are defensive: they allow the app to remain functional even if the recovery operation fails.

**Current behavior:**

- The re-fetch call (`_fetchSetlistsForBandInternal`) is returned without awaiting
- If the re-fetch throws (e.g., network error, RLS failure, timeout), the exception bypasses the catch block
- The error propagates to the controller layer without the defensive logging
- The user may see a generic error instead of the specific "deduplication failed, continuing" message

### Setlist Detail Controller Queued Reorder (Site 4)

`persistItemReorder()` is a guarded async method that prevents concurrent reorder operations. If a reorder request arrives while another is in-flight, it sets a `_itemReorderPendingAfterFlight` flag and returns early. When the in-flight operation completes, it checks the flag and recursively calls itself to persist the queued reorder.

**Current behavior:**

- The recursive `persistItemReorder()` call is returned without awaiting (line 2218)
- If the recursive persist throws (e.g., constraint violation, network error), the exception bypasses the catch block at line 2230+
- The `_isItemReorderInFlight` and `_itemReorderPendingAfterFlight` flags are not reset
- The reorder UI remains stuck in "reordering" state, and subsequent reorder attempts are blocked

---

## Proposed Solution

Add `await` before each of the 4 `return` statements:

1. **Line 448:** `return _fetchSetlistsForBandInternal(bandId, depth + 1);`  
   → `return await _fetchSetlistsForBandInternal(bandId, depth + 1);`

2. **Line 467:** `return _fetchSetlistsForBandInternal(bandId, depth + 1);`  
   → `return await _fetchSetlistsForBandInternal(bandId, depth + 1);`

3. **Line 486:** `return _fetchSetlistsForBandInternal(bandId, depth + 1);`  
   → `return await _fetchSetlistsForBandInternal(bandId, depth + 1);`

4. **Line 2218:** `return persistItemReorder();`  
   → `return await persistItemReorder();`

**Effect:**

- Exceptions thrown during recursive calls are now caught by the local `catch` handlers
- Error logging executes as the code structure implies
- Defensive fallback behavior (continuing with existing data) works correctly
- UI state guards (flags, isReordering) are properly reset on error
- Runtime behavior matches visual contract of the code

**No other changes:**

- No refactoring of surrounding code
- No formatting changes outside the 4 lines
- No touching of the 8 other pre-existing lint issues
- No new abstractions

---

## Database Impact

**Not applicable.** Pure Dart code change, no involvement of:

- Migrations
- RLS policies
- RPC functions
- Database triggers
- Schema modifications

---

## Flutter Architecture Changes

### State Management

**No changes** to state structure, providers, or Riverpod setup.

### Widgets

**No changes** to any widgets.

### Repositories

**Modified:** `SetlistRepository` at 3 sites (lines 448, 467, 486)

- No signature changes
- No new methods
- Only internal behavior fix (error handling now works as intended)

### Controllers

**Modified:** `SetlistDetailController` at 1 site (line 2218)

- No signature changes
- No new methods
- Only internal behavior fix (recursive re-persist now properly caught on error)

---

## Files to Create

None.

---

## Files to Modify

| File                                                   | Lines | Change Description                                                            |
| ------------------------------------------------------ | ----- | ----------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_repository.dart`        | 448   | Add `await` before `return _fetchSetlistsForBandInternal(bandId, depth + 1);` |
| `lib/features/setlists/setlist_repository.dart`        | 467   | Add `await` before `return _fetchSetlistsForBandInternal(bandId, depth + 1);` |
| `lib/features/setlists/setlist_repository.dart`        | 486   | Add `await` before `return _fetchSetlistsForBandInternal(bandId, depth + 1);` |
| `lib/features/setlists/setlist_detail_controller.dart` | 2218  | Add `await` before `return persistItemReorder();`                             |

**Modification constraint:** Change only the 4 lines specified above. Do not touch any other code in these files, including:

- The 8 other pre-existing lint issues (`use_build_context_synchronously`, `sized_box_for_whitespace`, `unused_local_variable` in test files)
- Formatting or whitespace outside the 4 target lines
- Comments, imports, or any other declarations

---

## Files Off-Limits

| File                                                   | Reason                                                   |
| ------------------------------------------------------ | -------------------------------------------------------- |
| All files except the 2 listed above                    | Not required for this surgical fix                       |
| All test files                                         | Existing tests cover these paths; no test changes needed |
| `lib/main.dart`                                        | Initialization order must not change                     |
| Config files (`pubspec.yaml`, `analysis_options.yaml`) | Not applicable                                           |
| Database migrations                                    | Not applicable                                           |
| Asset files                                            | Not applicable                                           |

---

## System Impact Map

| System                                 | Impact         | Notes                                                                                                                     |
| -------------------------------------- | -------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | **unaffected** | No code in gigs domain touched                                                                                            |
| Rehearsals                             | **unaffected** | No code in rehearsals domain touched                                                                                      |
| Setlists / Catalog                     | **affected**   | Both modified files are in this domain; fix improves error handling in Catalog recovery paths and setlist reorder queuing |
| Members / RBAC                         | **unaffected** | No code in members/RBAC domain touched                                                                                    |
| Auth / Session                         | **unaffected** | No auth or session code touched                                                                                           |
| Routing                                | **unaffected** | No routing changes                                                                                                        |
| Notifications                          | **unaffected** | No notification code touched                                                                                              |
| Platform (iOS / Android / Web / macOS) | **unaffected** | Pure Dart change, no platform-specific code involved                                                                      |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Touches only 2 files, both in the setlist/catalog domain
- Changes only 4 lines, each a single-keyword addition (`await`)
- Does not modify control flow, data structures, method signatures, or API contracts
- Makes existing error handling work as intended (defensive improvement, not behavior change)
- All 4 sites already have `await` on the preceding statement — adding it to the return is consistent
- Existing test suite (176 tests, passing) already exercises these code paths
- No database, auth, session, routing, or initialization changes
- Other systems (gigs, rehearsals, members, notifications) completely unaffected

**Potential regression:** None expected. The only behavioral change is that exceptions now correctly trigger local catch handlers instead of propagating uncaught — which improves stability and makes runtime behavior match the code's visual structure.

---

## Engineer Task Breakdown

Execute in order. Each task is atomic and verifiable.

**Task 1:** Verify workspace state

- Confirm branch `bug/unawaited-return-in-try-block` is checked out
- Confirm working tree is clean
- Run `flutter --version` and document the Flutter version being used (note if < 3.47.1, as the lint may not be visible)

**Task 2:** Modify `lib/features/setlists/setlist_repository.dart` line 448

- Locate: `return _fetchSetlistsForBandInternal(bandId, depth + 1);` (inside deduplication try block)
- Change to: `return await _fetchSetlistsForBandInternal(bandId, depth + 1);`
- Verify: Line now begins with `return await`

**Task 3:** Modify `lib/features/setlists/setlist_repository.dart` line 467

- Locate: `return _fetchSetlistsForBandInternal(bandId, depth + 1);` (inside ensureCatalog try block)
- Change to: `return await _fetchSetlistsForBandInternal(bandId, depth + 1);`
- Verify: Line now begins with `return await`

**Task 4:** Modify `lib/features/setlists/setlist_repository.dart` line 486

- Locate: `return _fetchSetlistsForBandInternal(bandId, depth + 1);` (inside ensureCatalogMetadata try block)
- Change to: `return await _fetchSetlistsForBandInternal(bandId, depth + 1);`
- Verify: Line now begins with `return await`

**Task 5:** Modify `lib/features/setlists/setlist_detail_controller.dart` line 2218

- Locate: `return persistItemReorder();` (inside \_itemReorderPendingAfterFlight if block)
- Change to: `return await persistItemReorder();`
- Verify: Line now begins with `return await`

**Task 6:** Run static analysis

- Execute: `flutter analyze`
- Verify: No `unawaited_return_in_try_block` errors at the 4 modified locations
- Verify: No new errors introduced
- Document: Note if running Flutter < 3.47.1 (lint may not be visible, but fix is still correct)

**Task 7:** Run test suite

- Execute: `flutter test`
- Verify: All 176 tests pass (baseline count)
- Verify: No new test failures introduced

**Task 8:** Generate git diff

- Execute: `git diff`
- Verify: Diff shows exactly 4 lines changed, each adding `await` before an existing `return` statement
- Verify: No other changes present (no formatting, imports, comments touched)

**Task 9:** Document completion

- Create `ENGINEER_REPORT.md` in `docs/features/unawaited-return-in-try-block/`
- Include:
  - Flutter version used
  - `flutter analyze` output (full or filtered to relevant lines)
  - `flutter test` summary
  - Full `git diff` output
  - Confirmation all 4 tasks completed
  - Any notes if Flutter version < 3.47.1

---

## Verification Plan

### Pre-Deployment (Local)

**Test 1 — Static analysis (PRIMARY)**

```bash
flutter analyze
```

**Expected result:**

- Zero `unawaited_return_in_try_block` errors at:
  - `lib/features/setlists/setlist_repository.dart:448`
  - `lib/features/setlists/setlist_repository.dart:467`
  - `lib/features/setlists/setlist_repository.dart:486`
  - `lib/features/setlists/setlist_detail_controller.dart:2218`
- No new errors introduced by the change
- **NOTE:** If running Flutter < 3.47.1, this lint may not be visible locally. Document this explicitly. The fix is still correct.

**Test 2 — Full test suite**

```bash
flutter test
```

**Expected result:**

- All 176 tests pass (baseline)
- No new test failures

**Test 3 — Diff inspection**

```bash
git diff
```

**Expected result:**

- Exactly 4 lines changed, one in each file/location
- Each change adds ` await` (space + keyword) between `return` and the method call
- No other modifications (imports, formatting, comments, other code)

### Post-Deployment (Runtime)

Since this is a purely defensive fix (making error handling work correctly), there is no visible user-facing change when exceptions are NOT thrown. The fix only becomes observable during error conditions.

**Test 4 — Manual trace: Catalog deduplication error path**

1. Add a temporary `throw Exception('TEST');` at the start of `_fetchSetlistsForBandInternal` when `depth > 0`
2. Trigger the deduplication path (create duplicate Catalogs in database)
3. Open setlist screen
4. Verify console shows: `[SetlistRepository] Deduplication failed, continuing with existing data: Exception: TEST`
5. Verify app does NOT crash — setlist screen loads with existing data
6. Remove test exception
7. **This confirms the catch block now executes as intended**

**Test 5 — Manual trace: Queued reorder error path**

1. Add a temporary `throw Exception('TEST');` at the start of `persistItemReorder` when called recursively (check `depth` param or `_itemReorderPendingAfterFlight` state)
2. Rapid-fire reorder drag operations to trigger the queued reorder path
3. Verify console shows: `[SetlistDetail] Error persisting item reorder: Exception: TEST`
4. Verify `_isItemReorderInFlight` and `_itemReorderPendingAfterFlight` are reset (subsequent reorders work)
5. Remove test exception
6. **This confirms the catch block now executes and cleans up state correctly**

**Test 6 — Baseline functionality (no errors injected)**

1. Load setlist screen with multiple setlists
2. Drag-reorder songs in a setlist
3. Perform bulk song paste
4. Switch bands
5. Verify all operations complete without error
6. **This confirms the fix does not break normal (non-error) code paths**

---

## QA Regression Areas

QA must specifically verify:

1. **Setlist loading with Catalog integrity issues**
   - Multiple Catalogs (deduplication path, line 448)
   - Missing Catalog (creation path, line 467)
   - Catalog metadata wrong (correction path, line 486)
   - Confirm error messages appear in logs when recovery fails
   - Confirm app continues with existing data rather than crashing

2. **Setlist reorder queuing**
   - Rapid drag-reorder operations to trigger queued re-persist (line 2218)
   - Confirm UI state (isReordering flag) clears correctly
   - Confirm subsequent reorders are not blocked

3. **Baseline setlist operations**
   - Load setlists
   - Drag-reorder songs
   - Bulk song paste
   - Switch bands
   - Confirm no regressions in normal (non-error) paths

4. **Static analysis validation**
   - Run `flutter analyze` on Flutter 3.47.1+ (or document if unavailable)
   - Confirm zero `unawaited_return_in_try_block` errors at the 4 modified sites

5. **Test suite validation**
   - Run `flutter test`
   - Confirm all 176 tests pass

---

## Rollout / Migration Strategy

**Not applicable.** This is a client-only code change with no database, backend, or configuration impact.

**Deployment sequence:**

1. Merge to `main`
2. Standard web build + deploy (`./tools/deploy_web.sh`)
3. No special rollout required — change is defensive and improves error handling

**Compatibility:** No breaking changes, no API changes, no migration required.

---

## Out of Scope

Explicitly excluded from this feature:

1. **Other pre-existing lint issues** (8 total, documented in ci-analyze-test-gate QA report):
   - `use_build_context_synchronously` (multiple files)
   - `sized_box_for_whitespace` (multiple files)
   - `unused_local_variable` (test files)
   - These are tracked separately and out of scope for this surgical fix

2. **Refactoring** of `_fetchSetlistsForBandInternal` or `persistItemReorder`
   - Methods work correctly once error handling is fixed
   - No architectural changes needed

3. **Adding tests** for the error paths
   - Existing 176 tests cover the normal paths
   - Error injection tests (manual verification steps above) are sufficient for QA
   - No new test files required

4. **Touching any other files**
   - Only the 2 specified files, only the 4 specified lines

5. **Opportunistic cleanup**
   - No formatting, comment, or import changes
   - No "while we're here" modifications

---

**End of Plan**
