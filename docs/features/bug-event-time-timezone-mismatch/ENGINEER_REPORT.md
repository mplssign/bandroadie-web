# Engineer Report

## Feature Slug

bug/event-time-timezone-mismatch

## Feature Title

Event Time Timezone Mismatch

## Goal

Fix event-time UI so cards, calendar entries, and availability prompts show the band’s configured wall-clock time instead of the device-local conversion. Preserve filtering/sorting behavior and keep the existing UTC paths unchanged.

## Architect Tasks Completed

- [x] Task 1 — Updated the six event display call sites to use `TimeFormatter.formatRange(...)` and removed the now-unused date/bandTimezone locals from each method.
- [x] Task 2 — Marked `formatRangeLocal` and `toLocal` as deprecated for event-time display and documented the band-time display rule and UTC filtering rule.
- [x] Task 3 — Confirmed the UTC conversion code in `TimezoneHelper.toUtc` and repository/controller filtering logic remained unchanged.
- [x] Task 4 — Verified the project analyzer passes with 0 errors.
- [x] Task 5 — Created and verified the engineer report file on disk.

## Files Created

- none

## Files Modified

- lib/features/home/widgets/rehearsal_card.dart
- lib/features/home/widgets/confirmed_gig_card.dart
- lib/features/home/widgets/potential_gig_card.dart
- lib/features/calendar/widgets/calendar_event_card.dart
- lib/features/gigs/widgets/availability_prompt_modal.dart
- lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart
- lib/app/utils/time_formatter.dart
- lib/app/utils/timezone_helper.dart

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 warnings

## Test Results

Not run

## Code Efficiency / Bloat Check

Confirmed no dead code, unused imports/variables/parameters, redundant restating comments, single-use wrapper abstractions, or unnecessary defensive checks in the diff.

## Verification

Manual steps performed:

- Reviewed the six event-display call sites and confirmed each was switched from `formatRangeLocal(...)` to `formatRange(...)`.
- Confirmed the deprecation notes in `time_formatter.dart` and `timezone_helper.dart` cite the band-time display policy and preserve `toUtc` as the authoritative filtering/sorting path.
- Verified there are no remaining `formatRangeLocal(...)` call sites in `lib` event-display widgets.
- Ran `flutter analyze` and confirmed 0 errors.

## Remediation Pass (2026-08-31)

- Issue found by QA: this branch was not cleanly based on `main`; it included unrelated commit `6f805c1` from the setlist-picker keyboard feature.
- Corrective action taken:
  - Confirmed branch ancestry mismatch and commit leakage (`git merge-base main bug/event-time-timezone-mismatch`, `git log --oneline main..HEAD`).
  - Safely stashed only this feature scope (8 source files + `docs/features/bug-event-time-timezone-mismatch/`).
  - Deleted and recreated local branch `bug/event-time-timezone-mismatch` from current `main` tip.
  - Reapplied stashed timezone-fix changes; did not reapply any setlist-picker files.
  - Removed carried-over `QA_REPORT.md` from this feature folder per remediation instructions.
- Re-verification results after branch recreation:
  - `git log --oneline main..HEAD` => no commits.
  - `git diff --stat main` => only the 8 intended source files.
  - `flutter analyze` => 0 errors.

## Before / After Notes by Call Site

- lib/features/home/widgets/rehearsal_card.dart — Before: `TimeFormatter.formatRangeLocal(_currentStartTime, rehearsal.endTime, _currentDate, widget.bandTimezone)`. After: `TimeFormatter.formatRange(_currentStartTime, rehearsal.endTime)`.
- lib/features/home/widgets/confirmed_gig_card.dart — Before: `TimeFormatter.formatRangeLocal(widget.gig.startTime, widget.gig.endTime, widget.gig.date, widget.bandTimezone)`. After: `TimeFormatter.formatRange(widget.gig.startTime, widget.gig.endTime)`.
- lib/features/home/widgets/potential_gig_card.dart — Before: `TimeFormatter.formatRangeLocal(_currentStartTime, widget.gig.endTime, _currentDate, widget.bandTimezone)`. After: `TimeFormatter.formatRange(_currentStartTime, widget.gig.endTime)`.
- lib/features/calendar/widgets/calendar_event_card.dart — Before: `TimeFormatter.formatRangeLocal(widget.event.startTime, widget.event.endTime, widget.event.date, widget.bandTimezone)`. After: `TimeFormatter.formatRange(widget.event.startTime, widget.event.endTime)`.
- lib/features/gigs/widgets/availability_prompt_modal.dart — Before: `TimeFormatter.formatRangeLocal(widget.gig.startTime, widget.gig.endTime, widget.gig.date, widget.bandTimezone)`. After: `TimeFormatter.formatRange(widget.gig.startTime, widget.gig.endTime)`.
- lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart — Before: `TimeFormatter.formatRangeLocal(widget.rehearsal.startTime, widget.rehearsal.endTime, widget.rehearsal.date, widget.bandTimezone)`. After: `TimeFormatter.formatRange(widget.rehearsal.startTime, widget.rehearsal.endTime)`.

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes
