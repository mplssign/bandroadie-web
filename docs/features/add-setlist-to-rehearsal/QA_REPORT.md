# QA REPORT

## Feature Slug

`feature/add-setlist-to-rehearsal`

## Feature Title

Add a setlist to a rehearsal

## Cycle Number

4

## Final Verdict

APPROVED

## Validation Summary

Cycle 4 matches the Architect addendum. The implementation adds the literal
`No Setlist Selected` badge to confirmed and potential rehearsal/gig dashboard
cards only when the authoritative event `setlistId` is null. The confirmed
rehearsal selected-setlist pill remains unchanged, rehearsal name-loading races
cannot flash the empty-state badge, and stale gig `setlistName` data cannot
suppress it.

QA performed code-path analysis and widget-test execution, not manual device or
browser testing. Changed-file analysis is clean, the focused dashboard test
passes 11/11, focused plus Cycle 1-3 event regression coverage passes 18/18,
and the full suite passes 322/322. Overall regression risk is **LOW**.

The Manager-held `pipeline.lock` was neither acquired nor modified.

## Architect Scope Review

- The branch, Architect plan, and Engineer report all identify
  `feature/add-setlist-to-rehearsal`; the Engineer report is Cycle 4 and states
  `Ready For QA: Yes`.
- Production changes are limited to the three plan-approved dashboard widget
  files: `rehearsal_card.dart`, `confirmed_gig_card.dart`, and
  `potential_gig_card.dart`.
- The only new file is the plan-approved
  `test/features/home/widgets/dashboard_no_setlist_badge_test.dart`.
- The Cycle 4 Architect addendum and Engineer report are expected documentation
  updates. The Manager's deletion of the committed Cycle 3 QA report was the
  requested duplicate-session safeguard exception; this file is its fresh
  Cycle 4 replacement.
- `PR_BODY.md` retains only Tony's pre-existing formatter change: a final
  newline. No implementation content was written there.
- No view/editor drawer, calendar, home wiring, model, repository, provider,
  migration, edge function, dependency, platform configuration, or init-order
  file changed.

## Completeness Check

All Cycle 4 Architect tasks are complete:

- Confirmed rehearsal: an `else if (rehearsal.setlistId == null)` branch adds
  the left-aligned muted badge after the byte-identical existing selected pill.
- Potential rehearsal: an ID-only gated, centered badge sits between Location
  and the existing `Spacer`.
- Confirmed gig: an ID-only gated, left-aligned badge follows Time.
- Potential gig: an ID-only gated, centered badge sits between venue/city and
  the existing `Spacer`.
- The new test has the required four top-level groups and 11 cases in the
  required 3/3/2/3 split.
- The test covers unselected and selected states, both rehearsal loading-race
  variants, confirmed rehearsal selected-pill preservation, and the potential
  gig stale-name case.

No partial task, extra behavior, public test hook, shared production helper,
golden file, or integration test was added.

## Behavior Verification

**Method:** code-path analysis plus widget-test execution; not runtime device or
browser testing.

- The exact label is `No Setlist Selected` at all four render sites.
- All four gates read only `setlistId == null`.
- Confirmed rehearsal with non-null ID and name renders the existing rose pill
  and no empty-state badge.
- Confirmed rehearsal with non-null ID and null name renders neither pill,
  preserving loading-race suppression.
- Potential rehearsal with non-null ID suppresses the badge regardless of the
  resolved name.
- Both gig variants suppress the badge for a non-null ID and show it for a null
  ID. A stale non-null `setlistName` therefore does not override the
  authoritative null ID.
- Every badge uses the specified 32px height, chip radius, 1.5px white 40%
  border, transparent background, footnote w600 text at 75% white, 12px
  horizontal padding, one line, and ellipsis.
- Confirmed variants use `IntrinsicWidth` with left alignment. Potential
  variants add `Center` and remain immediately before the existing `Spacer`.
- The potential-card chip, animated date/time labels, location/venue row,
  `Spacer`, response buttons, date-navigation controls, focus nodes, response
  handlers, and pulse controllers are unchanged in the diff.

## Regression Check

Overall risk: **LOW**.

| System | Risk | Evidence |
| --- | --- | --- |
| Rehearsals | LOW | Both dashboard variants use the required ID-only gate; selected-pill and loading-race tests pass. Editor/view behavior is untouched. |
| Gigs | LOW | Both dashboard variants use the required ID-only gate; selected/unselected and stale-name behavior are confirmed. Editor/view behavior is untouched. |
| Potential-card RSVP/layout | LOW | Only a centered child was inserted before the existing `Spacer`; RSVP, navigation, focus, async response, and animation code is byte-identical. Both potential widgets pump successfully and the full suite passes. |
| Setlists | LOW | No provider, query, RPC, route, or data contract changed. |
| Members/Auth/Routing | LOW | No membership, session, route, or initialization path changed. |
| Notifications | LOW | No repository, trigger, payload, or notification code changed. |
| Platforms | LOW | No platform-conditional or platform configuration code changed; visual parity remains owner-run. |

No RPC signature or parameter order changed. No Controller or FocusNode lifecycle,
async gap, `setState` path, or rebuild trigger was added or modified.

## Database Safety

Not applicable. Cycle 4 adds no SQL, migration, RPC, RLS policy, trigger, grant,
index, schema, model, or repository change. Migration-apply and
`has_function_privilege` checks are not required.

## Analyzer Results

Command:

`flutter analyze lib/features/home/widgets/rehearsal_card.dart lib/features/home/widgets/confirmed_gig_card.dart lib/features/home/widgets/potential_gig_card.dart test/features/home/widgets/dashboard_no_setlist_badge_test.dart`

Result: **PASS** - `No issues found!` at every severity.

A no-write whole-file formatter check reported one existing wrap in
`PotentialChip` at `potential_gig_card.dart:688`. A focused formatter diff
confirmed that this is the sole discrepancy and that it is outside the Cycle 4
hunk; the tracked diff confirms the off-limits baseline line is unchanged. All
Cycle 4 additions are formatter-conformant, so this is not a Cycle 4 finding.

## Test Results

- Focused dashboard badge test: **PASS**, 11 passed / 0 failed.
- Dashboard badge plus `event_dropdown_test.dart`: **PASS**, 18 passed / 0
  failed.
- Full Flutter suite: **PASS**, 322 passed / 0 failed.

These QA runs independently reproduce the Engineer's reported counts.

## Diff Safety Review

- Reviewed every tracked `git diff` hunk against `HEAD` and read the complete
  untracked test file separately.
- `git diff --check`: clean.
- Added production and test lines contain no `TODO`, `FIXME`, `debugPrint(`,
  private-key marker, or credential-like token.
- No secret, API key, test scaffolding, accidental deletion, generated output,
  migration, dependency, or unrelated implementation formatting churn is
  present.
- The only production changes are the four Architect-approved render blocks.
- The only `PR_BODY.md` delta is Tony's pre-existing final-newline edit.
- The Cycle 3 report deletion is the Manager-requested setup for this fresh
  Cycle 4 report, not an implementation deletion.

## Change Budget Review

Cycle 4 implementation/test delta:

| File | Actual | Architect budget | Assessment |
| --- | ---: | ---: | --- |
| `rehearsal_card.dart` | +58 / -0 | +50 to +70 | Within budget |
| `confirmed_gig_card.dart` | +27 / -0 | +25 to +35 | Within budget |
| `potential_gig_card.dart` | +31 / -0 | +25 to +35 | Within budget |
| `dashboard_no_setlist_badge_test.dart` | +312 / -0 | +200 to +320 | Within budget |
| **Total** | **+428 / -0** | **at most +460** | **Within budget** |

There is exactly one planned new file, no new public class/method, and no new
dependency. The zero-deletion bug-fix shape is explicitly justified in the
Engineer report: the root cause was four missing render branches, so no existing
logic needed removal. The Engineer also provides the required one-line
justification for adding to the already over-target widget files.

## Code Efficiency Review

- Independent search found no pre-existing production no-setlist badge/helper.
  The only four production label matches are the four required render sites.
- The plan explicitly requires inlining at these four sites and forbids a Cycle
  4 shared extraction; no extra provider, notifier, wrapper, utility, or public
  surface was introduced.
- The new `_buildRehearsal` and `_buildGig` symbols are private test fixture
  builders required by the plan. The only other test `_buildGig` match is a
  model-test fixture with unrelated address/state inputs and is not a reusable
  equivalent.
- There is no unused field/parameter, future-facing flag, single-call wrapper,
  redundant data fetch, hand-rolled collection operation, or catch-and-rethrow
  block in the change.

## Manual Verification Punch List

QA cannot exercise a running app. Tony should run these steps on at least one
native platform (macOS or iOS) plus Web.

1. **Confirmed rehearsal card, no setlist.** Open Home. Ensure the
   "Upcoming Rehearsals" slot is a confirmed rehearsal with no setlist
   selected (create one via Add -> Rehearsal with the setlist selector left on
   "None", save, reload Home).
   **Expected:** The confirmed rehearsal card renders an outlined pill below
   the Location row with the literal text `No Setlist Selected` in muted white
   (~75% alpha) with a 1.5px white 40%-alpha border, sized identically to the
   existing rose selected pill, left-aligned.
2. **Confirmed rehearsal card, setlist selected.** Open the same rehearsal,
   edit via View Rehearsal -> Edit Rehearsal, pick any setlist, save. Reload
   Home.
   **Expected:** The card renders the existing rose-outlined selected pill with
   the setlist name (Cycle 1-3 behavior). The muted `No Setlist Selected` pill
   is not shown.
3. **Potential rehearsal card, no setlist.** Ensure a `POTENTIAL REHEARSAL`
   card is visible on Home without a setlist selected (create a rehearsal with
   `isPotential: true`, leave the setlist selector on "None", save, reload
   Home).
   **Expected:** The potential rehearsal card renders the same muted pill
   between the Location text and the YES/NO button row, horizontally centered
   within the card. Text, color, border, height, and radius match step 1's pill
   exactly.
4. **Potential rehearsal card, setlist selected.** Edit the same potential
   rehearsal via View Rehearsal -> Edit Rehearsal, pick any setlist, save.
   Reload Home.
   **Expected:** The potential rehearsal card no longer shows the muted
   `No Setlist Selected` pill. The YES/NO button row remains anchored at the
   bottom of the card; card height may shrink slightly.
5. **Confirmed gig card, no setlist.** Open Home. Ensure a confirmed gig is
   visible in the "Upcoming Gigs" horizontal row without a setlist selected
   (create one via Add -> Gig, leave the Show Details setlist selector on
   "None", save).
   **Expected:** The confirmed gig card renders an outlined
   `No Setlist Selected` pill below the Time row, using the same muted styling
   as step 1, left-aligned.
6. **Confirmed gig card, setlist selected.** Edit the gig via View Gig -> Edit
   Gig, pick any setlist, save. Reload Home.
   **Expected:** The confirmed gig card no longer shows the muted
   `No Setlist Selected` pill. No new selected-setlist pill is added; Cycle 4
   intentionally leaves the with-setlist confirmed-gig layout unchanged.
7. **Potential gig card, no setlist.** Ensure a `POTENTIAL GIG` card is visible
   on Home without a setlist selected (create a gig with `isPotential: true`,
   leave the setlist selector on "None", save, reload Home).
   **Expected:** The potential gig card renders the same muted pill between the
   venue+city row and the YES/NO button row, horizontally centered within the
   card. Text, color, border, height, and radius match step 3's pill exactly.
8. **Potential gig card, setlist selected.** Edit the same potential gig via
   View Gig -> Edit Gig, pick any setlist, save. Reload Home.
   **Expected:** The potential gig card no longer shows the muted
   `No Setlist Selected` pill. The YES/NO button row remains anchored at the
   bottom; card height may shrink slightly.
9. **Loading race - confirmed rehearsal card.** With a rehearsal that has a
   setlist selected, force a fresh cold start (kill and relaunch the app). Land
   on Home.
   **Expected:** While `setlistsProvider` is briefly loading, the rehearsal
   card renders neither the rose pill nor the muted `No Setlist Selected` pill.
   Once the provider populates, the rose pill appears. No transient empty-state
   flash occurs.
10. **Loading race - potential rehearsal card.** With a potential rehearsal
    that has a setlist selected, force a fresh cold start. Land on Home.
    **Expected:** While `setlistsProvider` is briefly loading, the potential
    rehearsal card renders no muted `No Setlist Selected` pill because the ID
    is non-null. No transient flash occurs.
11. **Platform parity.** Repeat steps 1, 3, 5, and 7 on Web
    (`bandroadie.com`) or a second native platform.
    **Expected:** Every variant has the same visual result across platforms;
    the muted pill renders consistently on all four surfaces.

## Issues Found

### Critical

None.

### Warnings

None.

Prior-cycle comparison: Cycle 3 was APPROVED with no findings. Cycle 1's
historical **[code-quality]** budget warning did not recur in Cycles 2-3 and does
not recur here; every Cycle 4 implementation/test delta is within its explicit
budget. No prior issue category is repeated.

### Suggestions

None.
