# QA Report

## Feature Slug

existing-song-enrichment

## Feature Title

Phase 2.1 — Existing Song Data Enrichment (Single, Multi-Select, Catalog-Wide Entry Points)

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

Performed a scoped QA pass against the requested files and end-to-end enrichment flow requirements from ARCHITECT_PLAN.md, explicitly excluding areas already approved today (selector info-row/button polish and spinner exception-safety path, plus the RPC redeploy fix itself). Validation method was code-path analysis plus analyzer execution. `flutter analyze` completed with 0 errors and 1 info-level lint.

## Scope Note (Per Request)

The following were treated as pre-approved and not re-reviewed in this pass:

- `docs/features/enrichment-selector-info-rows/QA_REPORT.md` approved UI polish scope
- RPC fix redeploy verification in `docs/features/existing-song-enrichment/QA_REPORT_REDEPLOY_REVIEW_v2.md`

## Architect Scope Review

- Scope adherence: **partially compliant**
- Files reviewed in this pass:
  - `lib/features/setlists/setlist_repository.dart`
  - `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
  - `lib/features/songs/song_enrichment_service.dart`
  - `lib/features/songs/services/song_enrichment_orchestrator.dart`
  - `lib/features/songs/widgets/enrichment_results_overlay.dart`
  - `lib/features/songs/widgets/enrichment_progress_overlay.dart` (excluding spinner behavior already approved)
  - Enrichment-related handlers in `lib/features/setlists/setlist_detail_screen.dart` (excluding already-approved toolbar/select-mode/spinner polish)
- Files off-limits from Architect plan were not reviewed for changes in this pass.

## Completeness Check

- All Architect tasks implemented: **no**
- Missing/incorrect behavior:
  - Single-song flow does not trigger the same post-update refresh propagation used by multi-select/catalog-wide paths.
  - Orchestration error handling is too coarse for mixed-provider enrichment and drops partial success when one provider call fails.

## Behavior Verification

- Validation method: code-path analysis
- Runtime/device validation: not performed in this pass
- Result: **deviations found** (see Issues Found)

## Regression Check

- Risk level: **MEDIUM**
- Systems reviewed:
  - Catalog enrichment orchestration and per-field result accounting
  - Song details entry-point behavior
  - Repository RPC update wrapper
  - Progress/results overlays
- Regressions found: listed below

## Database Safety

Not re-litigated in this pass per explicit scope instruction (RPC fix already verified/deployed in separate approved review).

## Analyzer Results

Command: `flutter analyze`

Result: **0 errors**, 1 info:

- `lib/features/setlists/setlist_detail_screen.dart:1449` (`use_build_context_synchronously`)

## Test Results

Not run (no additional automated tests were added in this QA pass).

## Diff Safety Review

- Secrets: none found in reviewed diff
- Debug artifacts: none blocking in reviewed diff
- Unrelated changes: present in workspace/branch, but excluded per requested review scope

## Issues Found

### Critical (must fix before commit)

1. Partial enrichment results are discarded if one provider call throws for a song.
   - Location: `lib/features/songs/services/song_enrichment_orchestrator.dart:166-203`, `:206-227`
   - Problem: BPM/Key lookup and Duration lookup share one `try` block. If Duration lookup throws after BPM/Key succeeded, `hadError` is set and all requested fields are marked `error` for that song; no RPC update is attempted for successful fields.
   - Why this violates plan intent: Phase 2.1 requires robust per-song error handling and accurate fill-missing enrichment reporting. Current behavior converts recoverable partial success into full-song failure.
   - Required change: isolate provider failures per field (or per provider call), preserve successful fetched values, and still apply fill-missing updates for fields that resolved.

### Warnings (should fix)

1. Single-song enrichment path does not broadcast update events after successful enrichment.
   - Location: `lib/features/setlists/widgets/song_details_bottom_sheet.dart:520-563`
   - Problem: unlike multi-select/catalog-wide handlers in `setlist_detail_screen.dart` (which broadcast `SongUpdateEvent`), this path only shows results overlay and exits.
   - User impact: catalog/list views can remain stale after a successful single-song enrichment until a separate refresh/navigation occurs.
   - Required change: trigger the same refresh propagation pattern used in other enrichment entry points.

2. Async context lint remains in catalog-wide handler.
   - Location: `lib/features/setlists/setlist_detail_screen.dart:1448-1449`
   - Problem: `Navigator.of(context)` is used after an `await` without a post-await mounted guard at that exact boundary.
   - Impact: currently analyzer-info only, but this is lifecycle-fragile code.
   - Suggested change: add `if (!mounted) return;` immediately after awaiting progress overlay creation (or avoid storing navigator from potentially stale context).

## Required Changes Summary

1. Refactor orchestrator lookup/update flow to support partial success per song when one provider fails.
2. Add post-enrichment refresh/broadcast behavior to single-song entry path.
3. Address the async context lifecycle lint in catalog-wide handler.
