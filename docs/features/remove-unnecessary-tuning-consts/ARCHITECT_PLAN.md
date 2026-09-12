# ARCHITECT_PLAN

## Feature Slug
`bug/remove-unnecessary-tuning-consts`

## Feature Title
Resolve unnecessary const analyzer problems in tuning helpers

## Problem Summary
`flutter analyze` on synced `main` reports 47 `unnecessary_const` informational
diagnostics, all in [lib/features/setlists/tuning/tuning_helpers.dart](lib/features/setlists/tuning/tuning_helpers.dart)
between lines 203 and 283. VS Code's Problems view was reported as showing 49,
but the authoritative CLI run is 47; the 2-item discrepancy is analyzer-server
duplication in the IDE surface and is not architecturally significant. Expected
end state: `flutter analyze` clean, tuning behavior byte-for-byte identical.

## Root Cause
`_tuningBadgeColorMap` is declared as a top-level `const` map at
[tuning_helpers.dart#L201](lib/features/setlists/tuning/tuning_helpers.dart#L201):

```dart
const _tuningBadgeColorMap = <String, Color>{
  'standard': const Color(0xFF2563EB),
  ...
};
```

Inside a `const` collection literal every element expression is already
evaluated in a const context, so the inner `const` keyword on each
`Color(0xFF…)` value is redundant. The Dart `unnecessary_const` lint flags
each one — exactly 47 map entries, exactly 47 diagnostics.

The remaining 5 `const Color(...)` occurrences in the same file (lines 292,
303, 307, 318, 325) sit inside function bodies as return-value expressions
in non-const contexts; their `const` prefix is required and must be
preserved. `grep` confirms the file has 52 total `const Color(0x…)` matches
— 47 in the map + 5 in function bodies — matching the diagnostic count
exactly.

Confidence: **HIGH** — verified by direct read of lines 201–283 and by
counting `const Color(0x` matches in the file.

## Existing System Analysis
- [tuning_helpers.dart](lib/features/setlists/tuning/tuning_helpers.dart) is a
  pure Dart helpers file with no state, no I/O, and no platform-conditional code.
  It exposes `tuningBadgeColor`, `tuningBadgeTextColor`, `tuningShortLabel`,
  and capo parse/compose helpers.
- `_tuningBadgeColorMap` is a private `const Map<String, Color>` used by
  `tuningBadgeColor` for lowercase-normalized lookups.
- The `shortLabels` map inside `tuningShortLabel` (line 215) already uses the
  idiomatic form (`const` on the container, no `const` on values) and is
  clean under the same lint.
- [analysis_options.yaml](analysis_options.yaml) leaves `unnecessary_const`
  at its default `info` severity, so today these do not fail the
  Engineer/QA gates — but they are visible noise Manager wants removed.
- Existing test coverage:
  [test/app/theme/rose_primary_color_test.dart#L23](test/app/theme/rose_primary_color_test.dart#L23)
  asserts `tuningBadgeColor('open_e') == Color(0xFFBE123C)`. That entry is
  line 262 of the map — one of the 47 being edited — so the existing test
  already pins the value we care most about across this change.

## Proposed Solution
Remove the redundant `const ` keyword from each of the 47 `Color(0xFF…)`
values inside `_tuningBadgeColorMap` (lines 203–283 of
[tuning_helpers.dart](lib/features/setlists/tuning/tuning_helpers.dart)),
producing entries of the form `'standard': Color(0xFF2563EB),`. The map
container remains `const`; Dart's const-context rule guarantees the values
are still canonicalized at compile time. Do not touch any other line in
the file and do not touch any other file.

Deliberately not doing:
- Any refactor of the map (no reformat, no reordering, no key changes).
- Any change to `analysis_options.yaml` — promoting `unnecessary_const` to
  `error` is a separate policy decision outside this bug's scope.
- Any change to the 5 `const Color(...)` in function bodies at lines 292,
  303, 307, 318, 325 — those are non-const contexts and their `const` is
  required.

## Database Impact
n/a

## Flutter Architecture Changes
n/a

## Files to Create
n/a

## Files to Modify
- [lib/features/setlists/tuning/tuning_helpers.dart](lib/features/setlists/tuning/tuning_helpers.dart)
  — remove `const ` prefix from each of the 47 map values on lines 203–283.
  No other change. In-place character deletion only; line count unchanged.

## Files Off-Limits
- Any line of [tuning_helpers.dart](lib/features/setlists/tuning/tuning_helpers.dart)
  outside the 203–283 range. Specifically preserve the `const Color(...)`
  expressions at lines 292, 303, 307, 318, 325 — those are inside function
  bodies and their `const` is required.
- [analysis_options.yaml](analysis_options.yaml) — no lint-config change;
  the fix is at the code site, not the policy.
- [test/app/theme/rose_primary_color_test.dart](test/app/theme/rose_primary_color_test.dart)
  — existing coverage is sufficient; do not modify to accommodate the
  change (there is nothing to accommodate).
- All other source, tests, migrations, RPCs, edge functions, assets,
  lockfiles, and platform config — untouched.

## Change Budget
- Net line delta per file: **[tuning_helpers.dart](lib/features/setlists/tuning/tuning_helpers.dart) = 0**
  (47 lines edited in place; each loses exactly the 6-character prefix
  `const `; no lines added, no lines removed).
- Expected new files: **0**
- Expected new public classes/methods: **0**
- Expected new dependencies: **0**
- Expected new tests: **0** (existing `rose_primary_color_test` already
  pins the map entry at line 262; the change is a syntactic-only lint
  cleanup with zero runtime effect, so extra tests are make-work).

## System Impact Map
- Setlists: **affected — recompile only, zero runtime change**
- Gigs: unaffected
- Rehearsals: unaffected
- Members: unaffected
- Auth: unaffected
- Routing: unaffected
- Notifications: unaffected
- Platforms (iOS / Android / macOS / Web): **all affected — recompile only**;
  no platform-conditional code touched, init order untouched, no
  `--dart-define` change.

## Regression Risk
**LOW.** Purely a lint hygiene change on syntactic keywords Dart treats as
redundant inside a const collection literal. The compiled map, the
canonicalization of its `Color` values, and every lookup path are
byte-for-byte identical before and after. No auth, session, routing, init
order, DB, RLS, RPC, or migration is touched. Blast radius is confined to
the tuning-badge color lookup, which one existing test already pins.

## Engineer Task Breakdown
1. In [lib/features/setlists/tuning/tuning_helpers.dart](lib/features/setlists/tuning/tuning_helpers.dart),
   remove the `const ` keyword (6 characters including the trailing space)
   from the value expression of each of the 47 entries in
   `_tuningBadgeColorMap` on lines 203–283 inclusive. Each edited line
   goes from `'<key>': const Color(0xFF…),` to `'<key>': Color(0xFF…),`.
   Do not touch keys, values (hex), commas, comments, or blank lines. Do
   not touch line 201 (the map declaration) or lines 284+ (the closing
   brace and everything after). Do not modify any other file.

## Verification Plan

### Tier 1 — Pre-deploy (mechanical, no running app required)
1. `flutter analyze` — expect exit 0 with **no issues** reported. Explicit
   pre-change baseline: 47 `unnecessary_const` in
   [tuning_helpers.dart](lib/features/setlists/tuning/tuning_helpers.dart).
   Expected post-change: **0**.
2. `flutter test test/app/theme/rose_primary_color_test.dart` — expect all
   4 tests pass. The `Open E tuning color is unchanged (not brand primary)`
   case (asserts `tuningBadgeColor('open_e') == Color(0xFFBE123C)`) is the
   direct behavioral pin for the map entry at line 262.
3. `flutter test` — full suite passes; no test file was added, none
   modified, so this is a regression gate only.
4. Diff review: `git diff main -- lib/features/setlists/tuning/tuning_helpers.dart`
   must show **exactly** 47 modified lines, all in the 203–283 range, each
   losing only the substring `const ` before `Color(0xFF`. Every other
   character on the file, and every other file in the working tree, must
   be untouched. This is the definitive change-budget check.
5. Static grep audit: `grep -n 'const Color(0x' lib/features/setlists/tuning/tuning_helpers.dart | wc -l`
   must return **5** (the preserved function-body occurrences at lines
   292, 303, 307, 318, 325). Any other count means the edit was
   over-broad or under-broad.

### Tier 2 — Post-deploy
n/a — no RPC replacement, no schema change, no runtime behavior change to
verify against a live database.

### Owner-run punch list (Tony, at PR-test time)
n/a — no UI-observable change. Nothing to click. The Tier 1 checks above
fully cover the acceptance criterion.

## QA Regression Areas
- Static analysis: `flutter analyze` output count (target: 0).
- Unit test suite: `flutter test` full pass; specifically
  `test/app/theme/rose_primary_color_test.dart` must remain green.
- Change budget compliance: exactly 47 lines changed in exactly one file,
  each change limited to removing the `const ` prefix; 5 `const Color(...)`
  occurrences at lines 292, 303, 307, 318, 325 preserved verbatim.
- No collateral edits to `analysis_options.yaml`, tests,
  migrations, other Dart files, `pubspec.yaml`, or lockfiles.

## Rollout Strategy
Standard PR merge to `main`. No migration, no feature flag, no phased
rollout, no user comms. Change is a compile-time-syntactic cleanup with
zero runtime effect on any platform.

## Out of Scope
- Promoting `unnecessary_const` (or any other info-level lint) to `error`
  in [analysis_options.yaml](analysis_options.yaml). That is a separate
  policy decision.
- Any refactor of `_tuningBadgeColorMap` structure, key normalization, or
  color values.
- The 5 `const Color(...)` occurrences at lines 292, 303, 307, 318, 325 —
  those are correct and required.
- Any other analyzer warnings, formatting drift, or code-style cleanup
  elsewhere in the tuning subsystem.
- Any change to test coverage for tuning helpers; existing coverage is
  sufficient for this bug.
