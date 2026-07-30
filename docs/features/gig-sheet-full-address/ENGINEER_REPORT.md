# Engineer Report

## Feature Slug
bug/gig-sheet-full-address

## Feature Title
Gig sheet bottom sheet does not display full venue address

## Goal
`ViewGigDrawer`'s location row only rendered `gig.location` (city), never the venue's street address or state. Added a new `Gig.fullLocationDisplay` getter that composes address + city/state, and switched the drawer to use it, so the bottom sheet shows the complete location without leaving the dashboard.

## Architect Tasks Completed
- [x] Task 1 — Added `fullLocationDisplay` getter to `lib/app/models/gig.dart`, directly after `locationDisplay`
- [x] Task 2 — Updated `lib/features/gigs/widgets/view_gig_drawer.dart:303` to use `gig.fullLocationDisplay`
- [x] Task 3 — Created `test/app/models/gig_test.dart` covering all 5 specified branch cases

## Files Created
- `test/app/models/gig_test.dart`

## Files Modified
- `lib/app/models/gig.dart`
- `lib/features/gigs/widgets/view_gig_drawer.dart`

## Analyzer Results
Command: `flutter analyze lib/app/models/gig.dart lib/features/gigs/widgets/view_gig_drawer.dart test/app/models/gig_test.dart`
Result: 0 errors / 0 warnings

## Test Results
Passed — `flutter test test/app/models/gig_test.dart`: 5/5 tests passed, covering:
- address + location + state all present → two lines
- address blank/null, location + state present → one line with state
- address + location present, state blank/null → one line, no state
- address + state blank/null, only location present → one line, city only
- address whitespace-only → treated as blank

## Verification
Manual steps performed:
- Diffed `lib/app/models/gig.dart` line-by-line to confirm `locationDisplay` getter body is byte-identical to before the change (PRE-DEPLOY TEST 3) — only the new `fullLocationDisplay` getter was inserted below it.
- Diffed `lib/features/gigs/widgets/view_gig_drawer.dart` to confirm the change is exactly the single-line data-source swap on the `Text` widget at line 303 — no other lines, structure, or style in the `Row`/`Expanded`/`IconButton` changed.
- Ran `dart format` on the three changed files; it initially reformatted unrelated pre-existing lines in both modified files (a `replaceAllMapped` call in `gig.dart` and an `Icon`/`BorderRadius.circular` call in `view_gig_drawer.dart`) due to a formatter version/style difference unrelated to this change. Reverted those unrelated hunks by hand to keep the diff scoped to exactly what the Architect plan specifies, then re-ran `flutter analyze` and `flutter test` to confirm the manual revert didn't break anything.
- Grepped `locationDisplay` call sites to confirm only `confirmed_gig_card.dart` and `potential_gig_card.dart` use it, and neither was touched.
- UI (bottom sheet rendering on device/simulator, Navigate button behavior, dashboard card visual check) was not manually exercised in this session — this is Tier 2 / POST-DEPLOY verification per Section 15 of the Architect plan, owned by QA.

## Deviations From Architect Plan
None. (Note: `dart format`'s default output disagreed with existing formatting on two unrelated lines in each modified file; those formatter-only changes were reverted by hand so the final diff matches the plan's "no other lines change" requirement exactly — see Verification above.)

## Blockers Encountered
None.

## Ready For QA
Yes
