# QA REPORT

## Feature Slug

`feature/add-setlist-to-rehearsal`

## Feature Title

Add a setlist to a rehearsal

## Cycle Number

2

## Final Verdict

APPROVED

## Validation Summary

The Cycle 2 revision matches Tony's requested rehearsal UX: the separate
Setlist and Notes cards are replaced by one `Details` card, the existing
setlist selector is first, and the existing Notes field is below it. The
select/save and None/clear behavior from Cycle 1 remains intact.

Independent QA validation passed: changed-file analysis is clean, formatting
requires no changes, `dart fix --dry-run` finds nothing, the focused test file
passes 7/7, and the full suite passes 311/311.

Overall regression risk is **LOW**. QA performed code-path analysis and widget
test execution only. No running app, simulator, emulator, or browser was
launched; the runtime checks are correctly owner-run and listed below.

## Architect Scope Review

- The branch, Architect plan, and Engineer report all use
  `feature/add-setlist-to-rehearsal`; the Engineer report is Cycle 2 and says
  `Ready For QA: Yes`.
- Tony's Cycle 2 request supersedes the Cycle 1 plan's separate `Setlist` and
  `Notes` card presentation. The implementation differs from that presentation
  detail only: it uses one `Details` card with selector above Notes.
- Implementation changes remain confined to
  `lib/features/events/widgets/event_editor_drawer.dart` and
  `test/features/events/widgets/event_dropdown_test.dart`.
- The gig and block-out branches, `_buildShowPrepSection`, selector
  implementation, providers, repositories, models, migrations, routing,
  initialization, and platform configuration are unchanged.
- No implementation file, public API, dependency, migration, RPC, provider, or
  architectural abstraction was added.

## Completeness Check

- The rehearsal branch renders one `_SectionCard` titled `Details` after
  Location.
- Its child `Column` renders `buildSetlistSelector(context, ref)` first,
  `Spacing.space16` second, and `_buildNotesSection(...)` last.
- The focused test asserts the unique `Details` title and confirms the
  `Road Set` pill is vertically above `Notes (optional)`.
- The test still selects `Road Set`, taps Update, and observes
  `EventFormData.setlistId == 'setlist-1'` through the existing repository
  capture path.
- The same test still selects `None`, taps Update, and observes a non-null
  submission with `EventFormData.setlistId == null`.
- Existing test groups and private test stubs are unchanged in Cycle 2.

All Cycle 2 tasks are complete.

## Behavior Verification

**Method:** code-path analysis plus widget-test execution; not runtime device
testing.

The root-cause fix remains mounted in the rehearsal branch. Cycle 2 changes
only its presentation container: the real selector continues to update
`_selectedSetlistId` / `_selectedSetlistName`, `_buildFormData()` continues to
emit those values, and the unchanged repository path persists or clears the
association.

The focused test exercises the public edit/save path twice and confirms both
the selected ID and cleared null value. Its coordinate assertion independently
confirms the requested selector-before-Notes vertical order.

## Regression Check

Overall risk: **LOW**.

| System | Risk | Evidence |
| --- | --- | --- |
| Rehearsals | LOW | Revised Details layout and select/clear save behavior passed the focused test. Existing create/update/recurring persistence is unchanged. |
| Gigs | LOW | Gig branch and Show Details helper have no Cycle 2 diff; full suite passed. Runtime presentation remains owner-run. |
| Block-outs | LOW | Conditional branch has no diff; full suite passed. |
| Setlists | LOW | Existing provider and selector are reused unchanged. |
| Members/Auth/Routing | LOW | No provider contract, session, permission, route, or initialization change. |
| Notifications | LOW | No trigger or notification code changed. |
| Platforms | LOW | Shared Flutter widget only; no platform-conditional or configuration change. Native/Web parity remains owner-run. |

No RPC signature or parameter order changed. No Controller or FocusNode
lifecycle changed, no async production callback was introduced, and no new
rebuild source was added.

## Database Safety

Not applicable. The diff contains no SQL, migration, RPC, RLS, grant, schema,
or repository change. Migration apply and `has_function_privilege` checks are
not required.

## Analyzer Results

Command:

`flutter analyze lib/features/events/widgets/event_editor_drawer.dart test/features/events/widgets/event_dropdown_test.dart`

Result: **PASS** - `No issues found!` at every severity.

Additional static checks:

- `dart format --output=none --set-exit-if-changed ...`: **PASS**, 2 files
  checked, 0 changed.
- `dart fix --dry-run`: **PASS**, `Nothing to fix!`.

## Test Results

- Focused `event_dropdown_test.dart`: **PASS**, 7 passed / 0 failed.
- Full Flutter suite: **PASS**, 311 passed / 0 failed.

These QA runs independently reproduce the Engineer's reported counts.

## Diff Safety Review

- `git diff --check`: clean.
- The added implementation/test lines contain no `TODO`, `FIXME`,
  `debugPrint(`, credential-like token, or secret.
- No accidental implementation deletion, generated artifact, golden file,
  integration test, or unrelated formatting churn is present.
- The only non-implementation working-tree artifacts are the expected feature
  reports and PR body.

## Change Budget Review

Cycle 2 working-tree Dart delta against `HEAD`:

| File | Actual | Assessment |
| --- | ---: | --- |
| `event_editor_drawer.dart` | +9 / -6 | Small local replacement |
| `event_dropdown_test.dart` | +7 / -2 | Existing test assertion update |
| Total Dart diff | +16 / -8, net +8 | Within the plan's +90-line total budget |

Cycle 1's sole non-blocking `code-quality` warning was a 1.71x cumulative
budget overage caused by the private full-drawer test harness. Cycle 2 neither
repeats nor worsens it: no stub or harness line was added, and the current test
delta only renames the case and adds presentation assertions. The historical
warning remains documented in Cycle 1; there is no new Cycle 2 budget finding.

The production file remains above its size target for pre-existing reasons.
The Engineer report provides the required one-line justification, and the
requested local replacement does not expand the file's responsibilities.

## Code Efficiency Review

Cycle 2 adds no symbol, helper, extension, widget class, provider, notifier,
field, parameter, dependency, or public surface, so no equivalent-symbol search
is applicable. The local `Column` is the existing direct composition needed to
place selector, spacing, and Notes in order; extracting it would create a
single-call-site wrapper.

The revision also removes the obsolete sibling-card structure rather than
layering another section around it. No code-quality bloat finding is present.

## Manual Verification Punch List

QA cannot exercise a running app. Tony should run these steps on at least one
native platform (macOS or iOS) and Web.

1. Open Home -> Add -> Rehearsal.
   **Expected:** One `Details` card appears after Location. Inside it, the
   `Setlist` label and selectable `None` / band-setlist pills are visibly above
   the `Notes (optional)` field; there are no separate Setlist or Notes cards.
2. Complete the required rehearsal fields, select a non-catalog setlist pill,
   enter a note, and save.
   **Expected:** Save succeeds. The Home rehearsal card shows the selected
   setlist name.
3. Reopen that rehearsal through View Rehearsal -> Edit.
   **Expected:** The `Details` card keeps the selector above Notes, the saved
   setlist pill is selected, and the note is preserved.
4. Select `None` and save again.
   **Expected:** Save succeeds. Reopening shows `None` selected, the note is
   still preserved, and the Home rehearsal card no longer shows a setlist pill.
5. In a band with no setlists, open Add -> Rehearsal.
   **Expected:** The `Details` card shows `None` and `+ Create Setlist` above
   Notes, matching the gig selector behavior.
6. Create or edit a recurring rehearsal and choose a setlist.
   **Expected:** Save succeeds and each generated rehearsal instance shows the
   selected setlist; clearing with `None` removes the association as existing
   recurring-series behavior specifies.
7. Repeat steps 1-4 on Web.
   **Expected:** Layout, selection, save/reload, note preservation, and clearing
   behavior match the native platform.
8. Open Add -> Gig.
   **Expected:** `Show Details` still contains the setlist selector and contacts,
   and the gig Notes card remains separate and unchanged.

## Issues Found

### Critical

None.

### Warnings

None. Cycle 1's historical **[code-quality]** budget warning was not worsened
or repeated by the Cycle 2 delta.

### Suggestions

None.