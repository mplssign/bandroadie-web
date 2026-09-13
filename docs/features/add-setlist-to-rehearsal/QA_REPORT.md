# QA REPORT

## Feature Slug

`feature/add-setlist-to-rehearsal`

## Feature Title

Add a setlist to a rehearsal

## Cycle Number

5

## Final Verdict

APPROVED

## Validation Summary

Cycle 5 matches Tony's clarification and the corrected Architect addendum.
Confirmed rehearsal and confirmed gig cards retain the Cycle 4 badge behavior.
Potential rehearsal and potential gig cards render no `No Setlist Selected`
badge for null, non-null, or stale-name setlist states.

Validation used code-path analysis, diff inspection, analyzer execution, and
widget-test execution. QA did not launch or drive a running app; the required
runtime checks are listed in the owner-run punch list.

Overall regression risk: **LOW**.

## Architect Scope Review

- Branch, Architect plan, and Engineer report all identify
  `feature/add-setlist-to-rehearsal`; the Engineer report records Cycle 5 and
  `Ready For QA: Yes`.
- The implementation changes only the three Cycle 5-approved Dart files:
  `rehearsal_card.dart`, `potential_gig_card.dart`, and
  `dashboard_no_setlist_badge_test.dart`.
- `ARCHITECT_PLAN.md` and `ENGINEER_REPORT.md` are pipeline-owned Cycle 5
  documentation updates. The missing working-tree `QA_REPORT.md` was the
  Manager-declared removal of the committed Cycle 4 report and is replaced by
  this Cycle 5 report.
- No migration, dependency, model, repository, provider, controller, home
  wiring, editor/view drawer, platform configuration, or initialization file
  changed.
- `confirmed_gig_card.dart` has no diff. The only `rehearsal_card.dart` hunk is
  the potential-branch deletion, so both confirmed implementations are
  byte-identical to the Cycle 4 baseline.
- The test diff touches only Groups 2 and 4. Confirmed Groups 1 and 3, imports,
  fixtures, and their harnesses are byte-identical.

## Completeness Check

All Cycle 5 Architect tasks are complete:

- The complete 31-line potential-rehearsal badge spread was deleted. Location
  is immediately followed by the original `Spacer`.
- The complete 31-line potential-gig badge spread was deleted. The venue/city
  row is immediately followed by the original `Spacer`.
- The potential-rehearsal group contains null-ID and non-null-ID negative
  assertions, and only its redundant loading-race case was removed.
- The potential-gig group contains null-ID, non-null-ID, and null-ID with stale
  name negative assertions.
- All four groups remain with the required 3/2/2/3 split: 10 cases total.

No partial implementation, extra behavior, public test hook, shared helper,
golden test, or integration test was added.

## Behavior Verification

**Method:** code-path analysis plus widget-test execution; not runtime device or
browser testing.

- Confirmed rehearsal with `setlistId == null` renders the muted badge.
- Confirmed rehearsal with a non-null ID and resolved name renders the existing
  rose selected-setlist pill and no muted badge.
- Confirmed rehearsal with a non-null ID and null name renders neither pill,
  preserving loading-race behavior.
- Confirmed gig renders the muted badge only when `setlistId == null`.
- Potential rehearsal and potential gig source contain no badge label or badge
  branch, so neither can render it for any setlist ID state.
- A source-wide search finds exactly two production occurrences of
  `No Setlist Selected`: the confirmed rehearsal and confirmed gig cards.
- The focused tests exercise all required positive confirmed states and
  negative potential states, including the potential-gig stale-name edge case.

## Regression Check

| System | Risk | Evidence |
| --- | --- | --- |
| Rehearsals | LOW | Only the potential badge spread was deleted; confirmed rendering remains unchanged and all rehearsal badge tests pass. |
| Gigs | LOW | Only the potential badge spread was deleted; `ConfirmedGigCard` has no diff and all gig badge tests pass. |
| Potential RSVP/layout | LOW | The changed hunks end before the preserved `Spacer`; buttons, date navigation, focus nodes, handlers, async response state, and pulse controllers are untouched. |
| Setlists | LOW | No provider, query, RPC, route, model, or data contract changed. |
| Members/Auth/Routing | LOW | No membership, session, route, or initialization path changed. |
| Notifications | LOW | No repository, trigger, payload, or notification code changed. |
| Platforms | LOW | No platform-conditional or platform configuration code changed; visual parity remains owner-run. |

No RPC signature or parameter order changed. No Controller/FocusNode lifecycle,
`setState` path after an async gap, or rebuild trigger/frequency changed.

## Database Safety

Not applicable. Cycle 5 adds or changes no SQL, migration, RPC,
`SECURITY DEFINER` function, RLS policy, trigger, grant, index, schema, model,
or repository code. Migration-apply and `has_function_privilege` checks are not
required.

## Analyzer Results

`flutter analyze` over the three changed Dart files: **PASS** -
`No issues found!` at every severity.

No-write formatter check: both Cycle 5 hunks and the focused test are
formatter-conformant. The command also reports the same pre-existing
`PotentialChip` line wrap documented in Cycle 4, now at line 657 of
`potential_gig_card.dart`. It is outside the Cycle 5 hunk; changing it would be
unrelated churn forbidden by the plan.

## Test Results

- Focused dashboard badge test: **PASS**, 10 passed / 0 failed.
- Event editor regression test: **PASS**, 7 passed / 0 failed.
- Full Flutter suite: **PASS**, 321 passed / 0 failed.

These independent QA runs reproduce the Engineer's reported counts.

## Diff Safety Review

- Reviewed every uncommitted implementation and test hunk against `HEAD`.
- `git diff --check`: clean.
- No implementation `TODO`, `FIXME`, `debugPrint(`, secret, API key, private
  key, or credential-like value is present. The added Engineer report contains
  only a documentary statement that these artifacts are absent.
- No test scaffolding, accidental implementation deletion, generated output,
  migration, dependency, or unrelated implementation formatting churn exists.
- Confirmed implementation and test surfaces have no Cycle 5 hunk.
- The expected Cycle 4 QA report removal is pipeline setup, not an
  implementation deletion.

## Change Budget Review

Cycle 5 implementation/test delta:

| File | Actual | Architect budget | Assessment |
| --- | ---: | ---: | --- |
| `rehearsal_card.dart` | +0 / -31 | approximately -30 | Within budget |
| `potential_gig_card.dart` | +0 / -31 | approximately -30 | Within budget |
| `dashboard_no_setlist_badge_test.dart` | +7 / -30 (net -23) | approximately -25 | Within budget |
| **Total** | **+7 / -92 (net -85)** | **approximately -85** | **Matches budget** |

There are no new files, public classes/methods, symbols, or dependencies. The
two production files remain above the 500-line target at 954 and 978 lines,
respectively; the Engineer report supplies the required justification that this
is pre-existing, Cycle 5 reduces both files, and adjacent refactoring is
explicitly out of scope.

## Code Efficiency Review

- Cycle 5 is deletion-only in production and adds no helper, extension, utility,
  private widget, provider, field, parameter, wrapper, or future-facing flag.
- No equivalent-helper search is applicable because no symbol was introduced.
- The test keeps the minimum discriminating potential-rehearsal matrix and the
  required stale-name potential-gig discriminator without duplicate coverage.
- No fetch, grouping, deduplication, exception handling, or state ownership
  changed.

## Manual Verification Punch List

QA cannot exercise a running app. Tony should run these checks on at least one
native platform (macOS or iOS) plus Web.

1. Open Home with a confirmed rehearsal that has no setlist selected.
   **Expected:** The confirmed rehearsal card shows the left-aligned muted
   `No Setlist Selected` pill below Location.
2. Select a setlist for that confirmed rehearsal and reload Home.
   **Expected:** The existing rose selected-setlist pill shows the chosen name;
   the muted badge is absent.
3. Open Home with a confirmed gig that has no setlist selected.
   **Expected:** The confirmed gig card shows the left-aligned muted
   `No Setlist Selected` pill below Time.
4. Select a setlist for that confirmed gig and reload Home.
   **Expected:** The muted badge is absent.
5. Open Home with a potential rehearsal that has no setlist selected.
   **Expected:** No `No Setlist Selected` badge appears. Location flows to the
   bottom-anchored YES/NO row with the original `Spacer` layout.
6. Select a setlist for that potential rehearsal and reload Home.
   **Expected:** No badge appears; the potential-card layout is unchanged.
7. Open Home with a potential gig that has no setlist selected.
   **Expected:** No `No Setlist Selected` badge appears. The venue/city row
   flows to the bottom-anchored YES/NO row with the original `Spacer` layout.
8. Select a setlist for that potential gig and reload Home.
   **Expected:** No badge appears; the potential-card layout is unchanged.
9. Cold-start with a confirmed rehearsal that has a selected setlist.
   **Expected:** During setlist loading, neither badge flashes; after loading,
   the rose selected-setlist pill appears.
10. Repeat steps 1, 3, 5, and 7 on Web or a second native platform.
    **Expected:** Confirmed cards show the muted badge only when unselected;
    potential cards never show it for either setlist state.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.

Prior-cycle comparison: Cycle 4 was APPROVED with no findings. Cycle 1's
historical **[code-quality]** budget warning did not recur in Cycles 2-4 and
does not recur in Cycle 5. The known off-hunk `PotentialChip` formatter delta
was documented as non-blocking in Cycle 4 and is unchanged. No prior issue
category is repeated.