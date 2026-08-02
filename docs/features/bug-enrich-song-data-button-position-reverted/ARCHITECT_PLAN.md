# ARCHITECT_PLAN

## 1. Feature Slug

`bug/enrich-song-data-button-position-reverted`

## 2. Problem Summary

In Song Details, the `Enrich Song Data` button currently renders in the fixed bottom action area below `Save`/`Done`, instead of above the metadata columns (`BPM`, `Duration`, `Tuning`, `Key`) in the scrollable content region. This regresses expected UX behavior and placement.

## 3. Root Cause

The position change was implemented in commit `0db426c` (`feat(songs): move and center Enrich Song Data button above metrics row`) on branch `feature/move-enrich-song-data-button`, but that commit is **not** in `origin/main`.

Evidence:

- `git show 0db426c -- lib/features/setlists/widgets/song_details_bottom_sheet.dart` shows the button moved from `_buildFixedBottomActions()` to the content column directly above `_buildMetricsRow()`.
- `git merge-base --is-ancestor 0db426c origin/main` returned non-zero (`1`), proving `0db426c` was never merged into `origin/main`.
- `git log --graph --decorate --oneline --all -- lib/features/setlists/widgets/song_details_bottom_sheet.dart` shows `0db426c` as a side branch commit diverging after `e87aa46`, while `main` advanced through `4cddaf3` without it.
- `git blame` on current button lines in `_buildFixedBottomActions()` points to `9704e71` for the enrich button block, and `git show 9704e71` confirms that commit introduced the button below Save in the bottom actions region.

Definitive classification:

- (a) committed and merged to `main`: **No**
- (b) committed then reverted/overwritten after merge to `main`: **No evidence**
- (c) never committed anywhere and lost: **No**
- Actual state: committed on a separate branch (`0db426c`) and never merged into `main`.

**Confidence:** `HIGH`

## 4. Reference Docs Consulted

Read from `docs/reference/notifications/` per Architect phase requirements:

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/notifications.md`

Note: These docs are not functionally relevant to this UI layout bug, but were read to satisfy mandated phase execution.

## 5. Existing System Analysis

Current UI structure in `lib/features/setlists/widgets/song_details_bottom_sheet.dart`:

- Scrollable body `Column` contains `_buildSongInfo()`, then `_buildMetricsRow()`, then `_buildNotesSection()`.
- Fixed bottom action area (`_buildFixedBottomActions()`) contains Save/Done, then `Enrich Song Data`, then Cancel.

Resulting behavior:

- The enrich button is anchored in the fixed footer and appears below Save.

Historical analysis:

- `9704e71` added enrichment flows and inserted `TextButton.icon('Enrich Song Data')` in `_buildFixedBottomActions()`.
- `0db426c` later moved that button above `_buildMetricsRow()` in the main content and removed it from fixed actions.
- `4cddaf3` updated Save/Done enrichment feedback but retained button-below-Save placement because it was based on mainline state without `0db426c`.

Stash/branch check:

- `git stash list` contains multiple historical entries; scan found enrich-string presence in `stash@{0}` merge stash, but not as authoritative merged state.
- Branch snapshot comparison confirms moved placement exists in `feature/move-enrich-song-data-button` and `origin/feature/move-enrich-song-data-button`, but not in `main`/`origin/main`.

## 6. Proposed Solution

Apply the minimal, explicit layout relocation in `song_details_bottom_sheet.dart`:

- Move the existing `Enrich Song Data` `TextButton.icon` block out of `_buildFixedBottomActions()`.
- Insert the same block in the scrollable body `Column` immediately after `_buildSongInfo()` and before `_buildMetricsRow()`.
- Keep `if (!widget.isReadOnly)` guards intact.
- Preserve current style tokens and callback (`_handleEnrichSong`) without behavior changes.

What must not change:

- Save/Done behavior (`_justEnriched`, `_hasChanges`, `_handleSave`) in fixed bottom actions.
- Cancel/Close logic.
- Enrichment orchestration/data write logic.
- Any theme/color behavior unrelated to placement.

## 7. Database Impact

`not applicable`

- Migrations: unaffected
- RLS: unaffected
- RPCs: unaffected
- Triggers: unaffected

## 8. Flutter Architecture Changes

No architecture changes.

- State management: unchanged (`ConsumerStatefulWidget`, Riverpod usage unchanged)
- Repositories/services: unchanged
- Widget composition: one existing button block relocated within same widget file

## 9. Files to Create

`none`

## 10. Files to Modify

| File                                                           | Description of change                                                                                                                           |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Relocate `Enrich Song Data` button from fixed bottom actions to scrollable content above `_buildMetricsRow()`; keep logic/styling/guards intact |

## 11. Files Off-Limits

| File                                                   | Reason                                            |
| ------------------------------------------------------ | ------------------------------------------------- |
| `lib/main.dart`                                        | Initialization order is guardrailed and unrelated |
| `lib/features/songs/**`                                | No enrichment service behavior change required    |
| `lib/features/setlists/setlist_detail_controller.dart` | No state-flow change required for placement fix   |
| `lib/app/theme/**`                                     | No theme/token update required                    |
| `supabase/migrations/**`                               | UI-only fix; DB changes forbidden                 |
| `supabase/functions/**`                                | UI-only fix; backend changes forbidden            |

## 12. System Impact Map

| System                                 | Impact                                                   |
| -------------------------------------- | -------------------------------------------------------- |
| Gigs                                   | unaffected                                               |
| Rehearsals                             | unaffected                                               |
| Setlists / Catalog                     | affected (Song Details UI layout only)                   |
| Members / RBAC                         | unaffected                                               |
| Auth / Session                         | unaffected                                               |
| Routing                                | unaffected                                               |
| Notifications                          | unaffected                                               |
| Platform (iOS / Android / Web / macOS) | affected (shared widget renders on all listed platforms) |

## 13. Regression Risk

`LOW`

Rationale:

- Single-file, presentation-layer relocation only.
- No changes to data writes, providers, repositories, routing, or initialization.
- Existing callback and styling reused; no new abstractions/dependencies.

## 14. Engineer Task Breakdown

1. In `song_details_bottom_sheet.dart`, locate scrollable content `Column` in `build()` where `_buildSongInfo()` and `_buildMetricsRow()` are currently adjacent.
2. Insert the existing `Enrich Song Data` `TextButton.icon` block (with current styles and `_handleEnrichSong`) between `_buildSongInfo()` and `_buildMetricsRow()`, including intentional spacing.
3. Remove the duplicated enrich button block from `_buildFixedBottomActions()` so that fixed footer contains only Save/Done and Cancel/Close controls.
4. Verify `widget.isReadOnly` behavior still hides the enrich button and preserves read-only UX.
5. Keep all non-layout behavior unchanged; do not alter enrichment logic, save logic, or theme tokens.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

No database migration is part of this fix; Tier 1 focuses on static verification and app analysis.

```bash
# -- PRE-DEPLOY TEST 1:
# Verify moved placement in source order: Enrich appears in scroll body before _buildMetricsRow().
# (Engineer/QA can use grep context or manual code inspection.)

# -- PRE-DEPLOY TEST 2:
# Verify fixed bottom actions no longer include Enrich button block.
# Confirm only Save/Done + Cancel/Close remain in _buildFixedBottomActions().

# -- PRE-DEPLOY TEST 3:
flutter analyze

# -- PRE-DEPLOY TEST 4:
# Diff scope check: only planned file is modified in source scope.
git diff -- lib/features/setlists/widgets/song_details_bottom_sheet.dart
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

No DB deploy is required for this feature; execute these as post-merge/runtime validation checks.

```bash
# -- POST-DEPLOY TEST 1:
# Runtime smoke: open Song Details and verify Enrich button is above BPM/Duration/Tuning/Key.
# Repeat in setlist and catalog entry paths.

# -- POST-DEPLOY TEST 2:
# Read-only mode: verify Enrich button is hidden, Save/Done behavior unchanged.

# -- POST-DEPLOY TEST 3:
# Enrichment flow: tap Enrich, run enrichment, verify Save/Done + Cancel behavior still matches current expected UX.

# -- POST-DEPLOY TEST 4:
# Production verification query (no bad data written expectation for UI-only change).
# Expect schema and write paths unchanged for song metadata columns.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'songs'
  AND column_name IN ('bpm', 'duration_seconds', 'tuning', 'musical_key')
ORDER BY column_name;
```

SQL test authoring rules note:

- No INSERT/UPDATE/DELETE SQL tests are required for this UI-only change.
- If any DB test is later added, it must follow transaction/cleanup/restore rules in full.

## 16. QA Regression Areas

- Primary: Song Details enrich button placement relative to metadata row and Save button.
- Setlist path and catalog path both render expected placement.
- Read-only mode hides enrich action and keeps Close behavior.
- Enrichment action still launches selector/results flow.
- Save/Done/Cancel state transitions still behave correctly after enrichment and manual edits.
- Cross-platform check: Web, iOS, Android, macOS (shared widget surface).

## 17. Rollout / Migration Strategy

No migration/deploy sequencing required beyond normal app release.

- Implement minimal UI relocation.
- Validate via Tier 1 + Tier 2 checks.
- Ship in next app/web release batch.

## 18. Out of Scope

- Any enrichment algorithm/service changes
- Any save-state logic redesign
- Any theme/color/contrast changes
- Any database, RLS, RPC, trigger, or edge-function modifications
- Any refactor of Song Details architecture beyond button relocation
