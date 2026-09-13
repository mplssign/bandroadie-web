# ENGINEER_REPORT - Improve event card background colors

## Feature Slug

`feature/event-card-background-colors`

## Feature Title

Improve event card background colors

## Cycle Number

1

## Goal

Increase the Home dashboard event-card background tint opacity while preserving each existing hue and leaving borders, animation, layout, typography, and interaction behavior unchanged.

## Architect Tasks Completed

1. Changed the Potential Gig fill from `0x14F97316` to `0x33F97316` and updated its inline alpha comment.
2. Changed the Potential Rehearsal fill from `0x14F97316` to `0x33F97316` and updated its inline alpha comment.
3. Changed the Confirmed Rehearsal fill from `0x140EA5E9` to `0x1F0EA5E9` and updated its inline alpha comment.
4. Changed the Confirmed Gig fill from `0x1422C55E` to `0x1F22C55E` and updated its inline alpha comment.
5. Left all borders, shadows, gradients, animation controllers, child widgets, and off-limits files unchanged.

## Files Created

- `docs/features/event-card-background-colors/ENGINEER_REPORT.md` (required pipeline report only)

## Files Modified

- `lib/features/home/widgets/potential_gig_card.dart`
- `lib/features/home/widgets/rehearsal_card.dart`
- `lib/features/home/widgets/confirmed_gig_card.dart`

## Analyzer Results

- `dart fix --dry-run`: `Nothing to fix!`
- `flutter analyze lib/features/home/widgets/potential_gig_card.dart`: no issues found.
- `flutter analyze lib/features/home/widgets/rehearsal_card.dart`: no issues found.
- `flutter analyze lib/features/home/widgets/confirmed_gig_card.dart`: no issues found.
- The three focused analyzer commands passed both before and after final source normalization.

## Test Results

- Full `flutter test`: 322 passed, 0 failed.
- The full suite passed both before and after the final source normalization.

## Code Efficiency/Bloat Check

- Final application diff: 3 files changed, 4 insertions, 4 deletions.
- The diff contains only the four approved color-literal and inline-comment replacements.
- No helpers, extensions, utilities, private widgets, providers, dependencies, state, or public API were added; helper-equivalence search was therefore not applicable.
- No file-size increase or justification is required.
- `dart format` was run only on the three modified Dart files. Formatter-only wrapping and unrelated pre-existing layout churn were restored to preserve the architect's exact four-line scope and grep-verifiable literals.
- `git diff --check` passed.

## Verification (manual steps performed)

- Confirmed the four old fill literals have zero matches under `lib/features/home/widgets/`.
- Confirmed exactly four new literal matches at the approved sites: two `0x33F97316`, one `0x1F22C55E`, and one `0x1F0EA5E9`.
- Confirmed both off-limits modal `0x14F97316` literals and the off-limits `AppCard` doc-comment `0x140EA5E9` literal remain present.
- Confirmed the final working diff contains only the three approved application files plus this required report and the architect plan already present in the feature-doc directory.
- No live visual check was performed; the architect marks it as an owner-run, non-QA-gating PR-test step.

Owner-run visual check (verbatim from the architect plan):

1. Run `flutter run -d macos` (or `flutter run -d chrome`) on the
   `feature/event-card-background-colors` branch.
2. Sign in with an active band that has:
   - at least one **potential gig** on the Home dashboard, and
   - at least one **potential rehearsal** on the Home dashboard, and
   - at least one **confirmed (upcoming) gig** on the Home dashboard, and
   - at least one **confirmed (upcoming) rehearsal** on the Home dashboard.
3. On the Home tab, scroll to the horizontal event-card rail.
   **Expected:** the Potential Gig card and Potential Rehearsal card both
   show a visibly brighter, more saturated orange fill than on `main` —
   the orange should read as "clearly orange" rather than "hint of
   orange," while the animated border pulse and the cream chip label
   remain unchanged.
4. Still on the Home tab, look at the Confirmed Gig card.
   **Expected:** the green fill is slightly more present than on `main`
   — a subtle bump, not a dramatic one; text, border, and no-setlist
   chip remain unchanged.
5. Look at the Confirmed Rehearsal card.
   **Expected:** the sky-blue fill is slightly more present than on
   `main` — same subtle bump as the Confirmed Gig; setlist chip and
   border unchanged.
6. Confirm on at least one other platform (iOS simulator, Android
   emulator, or web build) that the colors render identically, since
   the change is a single hex literal per site with no
   platform-conditional path.

## Deviations From Plan

- No implementation deviations.
- `rg` was unavailable in the shell, so the same scoped old/new and off-limits literal assertions were executed with standard `grep`.

## Blockers Encountered

None.

## Ready For QA

Yes.