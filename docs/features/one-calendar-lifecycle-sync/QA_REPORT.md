# QA Report — One Calendar Lifecycle Sync (Full Re-Review)

## Feature Slug

`bug/one-calendar-lifecycle-sync`

## Feature Title

One Calendar Lifecycle Sync — Fix tentative-event auto-blocking, add resync on update, and cleanup on delete

## Final Verdict

**✅ APPROVED**

## Executive Summary

Comprehensive, fresh re-review conducted from first principles. Re-read the Architect Plan in full, independently analyzed the complete git diff, and systematically walked every code path that creates, moves, or removes a block-out. Every lifecycle gap is correctly closed:

1. **Tentative events no longer auto-block** — `!isPotentialGig` gates applied at both `createGig()` and `createRehearsal()` call sites
2. **Updates now resync** — delete-then-recreate pattern correctly implemented in `updateGig()`, `updateRehearsal()`, and `_updateAndGenerateRecurringSeries()`
3. **Deletes clean up** — explicit `clearAutoBlocksForSource()` calls in all six deletion paths: `deleteGig()`, `deleteRehearsal()`, `deleteRehearsalSeries()` (both strategies), and `_deleteChildRehearsals()`

Migration adds proper source traceability (`source_gig_id`, `source_rehearsal_id`) with FK cascade constraints and mutual-exclusivity CHECK constraint. Manual block-outs structurally protected by NULL source columns. Zero analyzer errors. No regressions found.

## Validation Summary

**Validation Method:** Code-path analysis + git diff inspection + flutter analyze + SQL migration verification

Systematically verified every code path identified in the user's re-review request:

### Code Path Analysis — All Verified Correct

#### 1. **createGig() / createRehearsal() — Gating and Source Tagging**

- **createRehearsal()** (lines 94-177):
  - ✅ Gate: Line 152 — `if (firstRehearsal != null && !formData.isPotentialGig)`
  - ✅ Source IDs collected: Line 135 — `createdRehearsalIds.add(response['id'] as String)` in creation loop
  - ✅ Source IDs passed: Line 173 — `sourceRehearsalIdsByDate: createdRehearsalIds`
  - **Verdict**: Correct — tentative events skip auto-blocking; confirmed events tag each occurrence with its specific rehearsal ID

- **createGig()** (lines 686-782):
  - ✅ Gate: Line 716 — `if (!formData.isPotentialGig)`
  - ✅ Source ID passed: Line 745 — `sourceGigId: gigId`
  - ✅ Multi-date handling: Lines 736-739 build `allDates = [formData.date, ...formData.additionalDates.map((e) => e.date)]`
  - **Verdict**: Correct — tentative gigs skip auto-blocking; confirmed gigs tag all dates with single gig ID

#### 2. **updateGig() / updateRehearsal() — Standard Branch Resync**

- **updateRehearsal()** (lines 343-451):
  - ✅ Unconditional clear: Lines 420-423 — `clearAutoBlocksForSource(sourceRehearsalId: rehearsalId)`
  - ✅ Conditional recreate: Line 425 — `if (!formData.isPotentialGig)` gates recreation
  - ✅ Non-blocking try-catch: Lines 419-448 wrapped, no rethrow
  - ✅ Single-date handling: Line 434 — `eventDates: [formData.date], sourceRehearsalIdsByDate: [rehearsalId]`
  - **Verdict**: Correct — handles all four state transitions: confirmed→confirmed-new-date (old removed, new created), tentative→confirmed (nothing to remove, new created), confirmed→tentative (old removed, nothing recreated), tentative→tentative (no-op both ways)

- **updateGig()** (lines 785-865):
  - ✅ Unconditional clear: Lines 826-829 — `clearAutoBlocksForSource(sourceGigId: gigId)`
  - ✅ Conditional recreate: Line 831 — `if (!formData.isPotentialGig)` gates recreation
  - ✅ Non-blocking try-catch: Lines 825-861 wrapped
  - ✅ Multi-date rebuild: Lines 840-843 — `final allDates = [formData.date, ...formData.additionalDates.map((e) => e.date)]`
  - **Verdict**: Correct — same delete-then-recreate pattern, properly handles multi-date gigs

#### 3. **\_updateAndGenerateRecurringSeries() — Becoming-Recurring Transition**

(lines 489-613):

- ✅ Clear parent's old single-date blocks: Lines 565-568 — `clearAutoBlocksForSource(sourceRehearsalId: rehearsalId)`
- ✅ Fetch all new child IDs: Lines 577-583 — queries `WHERE parent_rehearsal_id = rehearsalId`, ordered by date
- ✅ Build parallel source ID list: Lines 585-588 — `[rehearsalId, ...childIds]` parallel to `dates`
- ✅ Conditional recreate for entire series: Line 570 — `if (!formData.isPotentialGig)` gates full series recreation
- ✅ Non-blocking try-catch: Lines 564-609 wrapped
- **Verdict**: Correct — clears parent's old single-date block-out (from when it was non-recurring), creates new blocks for all occurrences in the series, maintains per-occurrence source traceability

#### 4. **\_deleteChildRehearsals() — isStoppingRecurring Child Cleanup**

(lines 458-487):

- ✅ Gather child IDs BEFORE deletion: Lines 460-464 — `SELECT id FROM rehearsals WHERE parent_rehearsal_id = rehearsalId`
- ✅ Loop cleanup for each child: Lines 466-473 — `for (final child in children) { clearAutoBlocksForSource(sourceRehearsalId: child['id']) }`
- ✅ Non-blocking try-catch: Lines 466-476 wrapped
- ✅ Then delete children: Lines 478-482 — `DELETE FROM rehearsals WHERE parent_rehearsal_id = rehearsalId`
- **Verdict**: Correct — this was the defect found and fixed during implementation. Children must be gathered first (can't query after DELETE), cleanup loops through each child ID individually, wrapped in try-catch. Confirmed correct in final code.

#### 5. **deleteGig() / deleteRehearsal() — Single-Event Delete Cleanup**

- **deleteRehearsal()** (lines 1042-1063):
  - ✅ Explicit cleanup before delete: Lines 1050-1058 — `clearAutoBlocksForSource(sourceRehearsalId: rehearsalId)`
  - ✅ Non-blocking try-catch: Lines 1050-1057 wrapped
  - ✅ Then delete: Lines 1060-1063 — `DELETE FROM rehearsals WHERE id = rehearsalId AND band_id = bandId`
  - **Verdict**: Correct — explicit application-level cleanup (contingency plan applied, not relying solely on FK cascade)

- **deleteGig()** (lines 1261-1282):
  - ✅ Explicit cleanup before delete: Lines 1268-1276 — `clearAutoBlocksForSource(sourceGigId: gigId)`
  - ✅ Non-blocking try-catch: Lines 1268-1275 wrapped
  - ✅ Then delete: Line 1278 — `DELETE FROM gigs WHERE id = gigId AND band_id = bandId`
  - **Verdict**: Correct — same defense-in-depth pattern as deleteRehearsal

#### 6. **deleteRehearsalSeries() — Both Internal Strategies**

**Strategy 1: Parent-Child Link** (lines 1133-1183):

- ✅ Gather ALL IDs before any deletion: Lines 1138-1153
  - Queries children: `SELECT id FROM rehearsals WHERE parent_rehearsal_id = seriesParentId`
  - Builds complete set: `allSeriesIds = {seriesParentId, rehearsalId, ...all child IDs}`
- ✅ Loop cleanup for each ID: Lines 1156-1163 — `for (final id in allSeriesIds) { clearAutoBlocksForSource(sourceRehearsalId: id) }`
- ✅ Non-blocking try-catch: Lines 1156-1166 wrapped
- ✅ Then delete all: Lines 1168-1182 — deletes all children, parent, and clicked rehearsal (if different from parent)
- **Verdict**: Correct — gathers all series IDs up front (necessary because can't query after DELETE), loops cleanup for each, then performs bulk deletion

**Strategy 2: Legacy Pattern-Matching** (lines 1185-1260):

- ✅ Pattern-match to build idsToDelete: Lines 1207-1225 — matches by `is_recurring=true`, same `start_time`/`end_time`/`location`, same day-of-week, includes clicked rehearsal
- ✅ Loop cleanup for each ID: Lines 1235-1242 — `for (final id in idsToDelete) { clearAutoBlocksForSource(sourceRehearsalId: id) }`
- ✅ Non-blocking try-catch: Lines 1234-1245 wrapped
- ✅ Then delete all: Lines 1247-1251 — `DELETE FROM rehearsals WHERE id IN idsToDelete AND band_id = bandId`
- **Verdict**: Correct — both strategies have proper cleanup loops, matching the Architect Plan's requirement that "both internal strategies" must include block-out cleanup

#### 7. **Manual Block-Out Creation — Structural Independence Verified**

- **add_block_out_drawer.dart** (lines 196, 205, 232):
  - ✅ All three `createBlockOut()` calls pass **only** `bandId, userId, startDate, untilDate, reason`
  - ✅ **No `sourceGigId` or `sourceRehearsalId` parameters** passed anywhere
  - **Verdict**: Correct — manual block-outs will have both source columns NULL

- **event_editor_drawer.dart** (lines 1387, 1395, 1415):
  - ✅ Same pattern — no source parameters passed in any of the three calls
  - **Verdict**: Correct — structurally isolated from event-sourced cleanup

**Manual Block-Out Protection Mechanism:**

- `deleteBlockOutsForSource()` only matches `WHERE source_gig_id = ...` or `WHERE source_rehearsal_id = ...`
- Manual block-outs have both columns `NULL` (because the optional params are never passed)
- SQL `WHERE source_gig_id = <some-uuid>` never matches a `NULL` value
- Therefore, manual block-outs are unreachable by event-sourced cleanup queries — structurally protected by construction, not by an added `if` check

### Migration Verification

**File:** `supabase/migrations/20260804120000_add_block_dates_source_traceability.sql`

- ✅ **Two nullable UUID columns added**:
  - `source_gig_id UUID REFERENCES public.gigs(id) ON DELETE CASCADE`
  - `source_rehearsal_id UUID REFERENCES public.rehearsals(id) ON DELETE CASCADE`
- ✅ **CHECK constraint enforces mutual exclusivity**:
  - `block_dates_single_source CHECK (NOT (source_gig_id IS NOT NULL AND source_rehearsal_id IS NOT NULL))`
  - Prevents both columns being non-NULL simultaneously
- ✅ **Partial indexes for efficient lookup**:
  - `idx_block_dates_source_gig_id ON block_dates (source_gig_id) WHERE source_gig_id IS NOT NULL`
  - `idx_block_dates_source_rehearsal_id ON block_dates (source_rehearsal_id) WHERE source_rehearsal_id IS NOT NULL`
  - Only indexes non-NULL values (efficient for the WHERE clauses in cleanup queries)
- ✅ **Timestamp sorts correctly**: 20260804120000 comes after previous migrations
- ✅ **Existing data unaffected**: New columns default to NULL; no backfill/UPDATE performed
- **Verdict**: Correct schema changes per Architect Plan

### Regression Suite — All Scenarios Verified

**Primary New Behavior (7 scenarios):**

1. ✅ **Tentative events don't auto-block** — Gates present at `createRehearsal()` line 152, `createGig()` line 716. Tentative events (`isPotentialGig=true`) skip auto-blocking call entirely.

2. ✅ **Confirming tentative retroactively blocks** — Update methods clear unconditionally (line 420 in updateRehearsal, line 826 in updateGig), then conditionally recreate if `!formData.isPotentialGig`. Transition from tentative (true) → confirmed (false) deletes nothing (no rows exist), creates new blocks.

3. ✅ **Un-confirming removes block-out** — Same clear-then-conditional-recreate pattern. Transition from confirmed (false) → tentative (true) deletes existing blocks, recreates nothing.

4. ✅ **Rescheduling moves block-out** — `clearAutoBlocksForSource()` deletes by source ID (date-agnostic: `WHERE source_gig_id = ...` has no date predicate), recreate uses current `formData.date` from the form. Old date blocks removed, new date blocks created.

5. ✅ **Deleting confirmed gig removes block-out** — `deleteGig()` line 1270 calls `clearAutoBlocksForSource(sourceGigId: gigId)` before the gig DELETE. Explicit application-level cleanup (contingency plan applied per Architect Plan Task 1).

6. ✅ **Deleting single occurrence removes only that block-out** — `deleteRehearsal()` line 1052 targets single `rehearsalId`. Each occurrence is a separate row with its own ID and its own `source_rehearsal_id` tag. Cleanup is scoped to that single ID.

7. ✅ **Deleting series removes all block-outs** — Both strategies in `deleteRehearsalSeries()` loop through all occurrence IDs (Strategy 1: lines 1156-1163 loops `allSeriesIds`, Strategy 2: lines 1235-1242 loops `idsToDelete`). Every occurrence's block-outs cleaned up.

**Regression Prevention (6 scenarios):**

1. ✅ **Confirmed one-off creation still works** — Gate is `!isPotentialGig`. Confirmed events (`isPotentialGig=false`) pass through the gate and trigger auto-blocking exactly as before. No regression.

2. ✅ **Manual block-outs unaffected** — Manual block-outs never pass `sourceGigId`/`sourceRehearsalId` (verified in Path 7 above). Both columns NULL. `deleteBlockOutsForSource()` only matches non-NULL values. Manual block-outs unreachable by event-sourced cleanup queries.

3. ✅ **Multi-date gigs block all dates when confirmed** — `createGig()` line 736 builds `allDates = [formData.date, ...formData.additionalDates.map((e) => e.date)]`. Same in `updateGig()` line 840. All dates passed to `autoBlockConflictingDates()`. No regression.

4. ✅ **One Calendar OFF/Selected-bands gating preserved** — No changes to `AutoConflictBlockingService.autoBlockConflictingDates()` preference-checking logic (lines 148-165 in the service). Early return if `!prefs.oneCalendarEnabled || !prefs.autoBlockConflictsEnabled` unchanged. Source params are additive (lines 128-130), do not alter control flow. No regression.

5. ✅ **Unique constraint handling unchanged** — No changes to per-date try-catch pattern in `BlockOutRepository.createBlockOut()` (verified by inspecting the diff — only changes are adding optional params and threading them into the insert payload). Existing duplicate-date handling preserved.

6. ✅ **Deleting never-auto-blocked event completes gracefully** — SQL `DELETE FROM block_dates WHERE source_gig_id = <uuid>` with zero matching rows is a valid no-op (affected_rows=0, no error). All cleanup calls wrapped in non-blocking try-catch (deleteGig line 1268, deleteRehearsal line 1050, deleteRehearsalSeries both strategies). If the DELETE returns 0 rows, execution continues normally. No regression.

### Git/Repo Hygiene

Verified via `git status --porcelain` and `git diff --stat`:

- ✅ **Modified files**: Exactly 3 Dart files (correct per Architect Plan)
  - `lib/features/calendar/auto_conflict_blocking_service.dart`
  - `lib/features/calendar/block_out_repository.dart`
  - `lib/features/events/events_repository.dart`
- ✅ **Untracked migration**: `supabase/migrations/20260804120000_add_block_dates_source_traceability.sql` (expected)
- ✅ **Untracked docs**: `docs/features/one-calendar-lifecycle-sync/` folder and `PRODUCTION_READINESS_REVIEW_2026-08-04.md` (expected)
- ✅ **No changes to wrong ENGINEER_REPORT**: Ran `git diff main -- docs/features/one-calendar-recurring-auto-block/ENGINEER_REPORT.md` (a different, already-shipped feature) — returned empty (no output). That file shows zero changes, as required.

### Analyzer Results

**Command:** `flutter analyze`  
**Result:** 0 errors, 0 warnings

```
Analyzing bandroadie...
No issues found! (ran in 4.0s)
```

### Files Off-Limits — Verified Untouched

Per Architect Plan, the following files must not be modified. Verified via git diff:

- ✅ `lib/app/models/block_out.dart` — No changes (confirmed — not in diff)
- ✅ `lib/features/events/widgets/event_editor_drawer.dart` — No changes (confirmed — not in diff)
- ✅ `lib/features/calendar/widgets/add_block_out_drawer.dart` — No changes (confirmed — not in diff)
- ✅ `lib/features/calendar/one_calendar_preferences_repository.dart` — No changes (confirmed — not in diff)
- ✅ `lib/main.dart` — No changes (confirmed — not in diff)
- ✅ Dead `autoBlockConflictingDate()` (singular) method — No changes (confirmed by inspecting the diff — method not removed or refactored)

## Architect Scope Adherence

- ✅ **Scope compliant**: All three lifecycle gaps addressed (tentative gating, update resync, delete cleanup)
- ✅ **Files modified**: Exactly 3 Dart files + 1 migration (as specified in Architect Plan "Files to Modify")
- ✅ **Files off-limits**: All verified untouched
- ✅ **Minimal diff principle**: No opportunistic refactors, no formatting-only changes, no unrelated edits

## Completeness Check

All eight Engineer tasks from Architect Plan verified implemented:

- ✅ **Task 1** — Migration created; contingency plan applied (explicit cleanup in delete methods, not relying solely on FK cascade — defense-in-depth strategy)
- ✅ **Task 2** — `BlockOutRepository.createBlockOut()`: `sourceGigId`/`sourceRehearsalId` optional params added, threaded into insert payload; `deleteBlockOutsForSource()` method implemented
- ✅ **Task 3** — `AutoConflictBlockingService.autoBlockConflictingDates()`: source params added, indexed loop for parallel `sourceRehearsalIdsByDate`; `clearAutoBlocksForSource()` passthrough method added
- ✅ **Task 4** — `createRehearsal()`: `!isPotentialGig` gate added (line 152), `createdRehearsalIds` collected (line 135), passed as `sourceRehearsalIdsByDate` (line 173)
- ✅ **Task 5** — `createGig()`: `!isPotentialGig` gate added (line 716), `sourceGigId` passed (line 745)
- ✅ **Task 6** — `updateRehearsal()` + `_updateAndGenerateRecurringSeries()`: resync implemented (clear + conditional recreate, lines 419-448 and 564-609 respectively)
- ✅ **Task 7** — `updateGig()`: resync implemented (clear + conditional recreate, lines 825-861)
- ✅ **Task 8** — `flutter analyze`: 0 errors

## Critical Review — deleteRehearsalSeries() Deep Dive

Per user request, special attention paid to both internal deletion strategies. Verified both have block-out cleanup:

**Strategy 1: Parent-Child Link** (lines 1133-1183):

- Comment at line 1138 explicitly states intent: `"Gather all ids in the series BEFORE deleting anything, so we can clean up their block-outs after they're gone"`
- Implementation: Queries all children first (`SELECT id WHERE parent_rehearsal_id = seriesParentId`), builds `allSeriesIds` set (parent + clicked rehearsal + all children), loops `clearAutoBlocksForSource()` for each ID, then performs deletions
- ✅ Correct — cannot query children after parent is deleted; gather-first pattern is necessary and correctly implemented

**Strategy 2: Legacy Pattern-Matching** (lines 1185-1260):

- Pattern-matching logic: Queries all recurring rehearsals with same `start_time`/`end_time`/`location`, filters to same day-of-week, includes clicked rehearsal, builds `idsToDelete` list
- Comment at line 1234 explicitly states: `"Clean up auto-created block-outs for each rehearsal in the series"`
- Implementation: Loops `clearAutoBlocksForSource()` for each ID in `idsToDelete`, then bulk-deletes via `inFilter('id', idsToDelete)`
- ✅ Correct — same per-ID cleanup pattern as Strategy 1

**Defense-in-Depth Mechanism:**

- Both strategies use explicit application-level cleanup (`clearAutoBlocksForSource()` calls in Dart code)
- FK `ON DELETE CASCADE` is also present in the migration (contingency if explicit cleanup fails or is skipped)
- If both fire, no harm — SQL DELETE with zero matching rows is a no-op
- If FK cascade doesn't fire due to RLS interaction (the uncertainty documented in Architect Plan Task 1), explicit cleanup is the safety net
- ✅ Correct — defense-in-depth strategy implemented as designed

## Database Safety

**Verified** (additive schema change + explicit application-level cleanup)

### Migration Verification:

- ✅ Columns: `source_gig_id`, `source_rehearsal_id` — both nullable UUID, FK to gigs/rehearsals with ON DELETE CASCADE
- ✅ CHECK constraint: `block_dates_single_source` enforces mutual exclusivity (not both non-NULL)
- ✅ Partial indexes: `idx_block_dates_source_gig_id`, `idx_block_dates_source_rehearsal_id` — efficient lookup
- ✅ Existing data unaffected: New columns default to NULL; no backfill/UPDATE performed
- ✅ No RLS policy changes (verified — existing policies do not reference new columns)
- ✅ Timestamp sorts after current latest migration

### Safety Audit:

- No privilege escalation (new columns do not interact with RLS predicates)
- No unintended cascade risk (ON DELETE CASCADE is intentional, cleanup mechanism)
- No RPC signature changes (no RPCs touch block_dates)
- Rollback SQL available in Architect Plan if needed

## Regression Check

- **Risk level:** MEDIUM (per Architect Plan — touches create, update, and delete lifecycle for both gigs and rehearsals; includes schema change + FK cascade uncertainty)
- **Systems reviewed:** Gigs, Rehearsals, Calendar/Block Dates, Manual Block-out flows
- **Regressions found:** None

### Risk Mitigation Verification

**FK CASCADE under RLS (Critical Uncertainty):**

- Engineer applied contingency plan proactively: explicit `clearAutoBlocksForSource()` calls in all delete methods before issuing the primary DELETE
- FK constraints correctly configured with `confdeltype = 'c'` (CASCADE)
- If FK cascade fires, explicit cleanup becomes a no-op (deleting already-deleted rows)
- If FK cascade does NOT fire due to RLS interaction, explicit cleanup is the mechanism that prevents orphans
- ✅ Defense-in-depth strategy — correct regardless of FK cascade behavior

**deleteRehearsalSeries() — Both Strategies Verified:**

- Strategy 1 (parent-child link, lines 1138-1183): ✅ Gathers `allSeriesIds` before deleting, loops cleanup for each ID
- Strategy 2 (legacy pattern-matching, lines 1185-1260): ✅ Builds `idsToDelete`, loops cleanup for each ID
- Current code has cleanup in BOTH branches

**Non-Blocking Error Handling:**

- ✅ All auto-block calls (create, resync, cleanup) wrapped in try-catch that does not rethrow
- Auto-blocking failure never fails the primary gig/rehearsal operation
- Consistent with existing pattern from prior One Calendar fixes

## Issues Found

**ZERO**

No defects, regressions, or omissions found. Implementation matches Architect Plan exactly.

## Recommendations

None — implementation is complete, correct, and safe to merge.

## QA Sign-Off

Comprehensive, fresh re-review complete. Every code path that creates, moves, or removes a block-out systematically verified:

- ✅ Create paths (gigs + rehearsals): Gated on `!isPotentialGig`, tag with source IDs
- ✅ Update paths (standard + becoming-recurring): Resync via delete-then-recreate
- ✅ Delete paths (single-event, series Strategy 1, series Strategy 2, stopping-recurring children): All have explicit cleanup
- ✅ Manual block-outs: Structurally protected by NULL source columns

All 7 primary new-behavior scenarios verified via code-path reasoning. All 6 regression-prevention scenarios verified. Both deletion strategies in `deleteRehearsalSeries()` have proper per-occurrence cleanup. The `_deleteChildRehearsals()` fix (gather-before-delete pattern) correctly implemented. Migration adds proper schema changes with FK cascade + mutual-exclusivity constraint. Zero analyzer errors. Zero off-limits files touched. Defense-in-depth strategy (FK cascade + explicit cleanup) mitigates RLS/cascade uncertainty.

**Final Verdict: ✅ APPROVED — ready for commit.**

---

**QA Agent:** GitHub Copilot (Claude Sonnet 4.5)  
**Re-Review Date:** 2026-08-04  
**Validation Method:** Fresh, systematic code-path analysis (not relying on prior QA pass)  
**Regression Risk:** MEDIUM (per Architect Plan — multi-lifecycle touchpoints + schema change)  
**Files Modified:** 3 Dart files + 1 SQL migration (correct per plan)  
**Analyzer Status:** 0 errors, 0 warnings  
**Defects Found:** 0
