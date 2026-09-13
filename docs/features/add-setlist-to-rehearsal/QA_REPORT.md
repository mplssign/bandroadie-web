# QA REPORT

## Feature Slug

`feature/add-setlist-to-rehearsal`

## Feature Title

Add a setlist to a rehearsal

## Cycle Number

3

## Final Verdict

APPROVED

## Validation Summary

Cycle 3 independently confirms that Tony's finding is expected required-field
behavior when Location is empty, not a reproducible implementation defect at
the current PR head. A setlist is optional and intentionally does not satisfy
the create-mode Location requirement. Entering `Test Studio` through the real
Location autocomplete enables Add Rehearsal; selecting or clearing a setlist
then leaves it enabled and submits the expected Location and `setlistId`.

QA performed code-path analysis and widget-test execution, not manual device or
browser testing. Changed-file analysis is clean, the focused test passes 7/7,
and the full suite passes 311/311. Overall regression risk is **LOW**.

The Manager-held `pipeline.lock` was neither acquired nor modified.

## Architect Scope Review

- The branch, Architect plan, and Engineer report all use
  `feature/add-setlist-to-rehearsal`; the Engineer report is Cycle 3 and states
  `Ready For QA: Yes`.
- The working tree contains only the expected Cycle 3 test/report changes and
  the Manager's removal of the committed Cycle 2 QA report before this fresh
  report was created.
- Cycle 3 modifies the plan-approved
  `test/features/events/widgets/event_dropdown_test.dart` and the mandatory
  reports. No production, migration, configuration, dependency, or generated
  file is changed in this cycle.
- The Cycle 2 production implementation remains unchanged: the rehearsal
  `Details` section contains the existing setlist selector above Notes. The gig
  and block-out branches remain untouched.
- No provider, controller, repository contract, model, public API, test hook,
  route, initialization order, platform configuration, RPC, or RLS policy was
  added or changed.

## Completeness Check

- The test now pumps a create-mode rehearsal drawer with the real Location
  `FAutocomplete`, the existing setlist selector, and a fake repository that
  captures `createRehearsal` form data.
- It verifies Add Rehearsal starts disabled while Location is empty.
- It verifies selecting `Road Set`, then `None`, while Location is empty keeps
  Add Rehearsal disabled.
- It enters `Test Studio` and verifies Add Rehearsal becomes enabled.
- It selects `Road Set`, verifies the button stays enabled, saves, and observes
  `location == 'Test Studio'` and `setlistId == 'setlist-1'`.
- It selects `None`, verifies the button stays enabled, saves again, and
  observes `setlistId == null`.
- Existing layout assertions still verify `Details` is rendered and the
  setlist pill appears above `Notes (optional)`.

All Cycle 3 tasks are complete. No production change was required because the
reported state is the intended validation state when Location is blank.

## Behavior Verification

**Method:** code-path analysis plus widget-test execution; not runtime device or
browser testing.

The controlling production path is internally consistent:

- `RehearsalFormFields` forwards the managed Location autocomplete's text via
  `onLocationTextChanged`.
- `EventEditorDrawer` stores that value in `_rehearsalLocationText` inside
  `setState`, causing the footer to rebuild.
- Create-mode `_canSave` requires trimmed rehearsal Location to be non-empty.
  It does not require a setlist.
- Setlist selection updates only `_selectedSetlistId` and
  `_selectedSetlistName`; it neither fills nor clears Location.
- `_buildFormData()` emits the same trimmed Location and selected setlist state,
  and the create path passes it to `createRehearsal`.

Therefore, selecting a setlist with blank Location must leave Add Rehearsal
disabled. The focused test exercised the actual controls and could not
reproduce a disabled button after entering a valid Location. Tony's report is
expected required-field behavior on the facts provided, not a PR-head defect.
The running-app confirmation remains owner-run below.

## Regression Check

Overall risk: **LOW**.

| System | Risk | Evidence |
| --- | --- | --- |
| Rehearsals | LOW | Create-mode Location gate, setlist select/clear state, and submitted form data pass the focused test. |
| Gigs | LOW | No production or gig-test path changed; the full suite passes. |
| Block-outs | LOW | No production or block-out path changed; the full suite passes. |
| Setlists | LOW | Existing provider and selector are reused unchanged. |
| Members/Auth/Routing | LOW | No permission, session, provider contract, route, or initialization change. |
| Notifications | LOW | No repository, trigger, or notification code changed. |
| Platforms | LOW | No platform-specific code changed; native/Web runtime parity remains owner-run. |

No RPC signature or parameter order changed. No Controller or FocusNode
lifecycle changed, no production async gap was added, and the only relevant
rebuild is the existing `setState` invoked by Location/setlist callbacks.

## Database Safety

Not applicable. Cycle 3 contains no SQL, migration, RPC, RLS, grant, schema, or
repository change. Migration apply and `has_function_privilege` checks are not
required.

## Analyzer Results

Command:

`flutter analyze test/features/events/widgets/event_dropdown_test.dart`

Result: **PASS** - `No issues found!` at every severity.

Formatting check:

`dart format --output=none --set-exit-if-changed test/features/events/widgets/event_dropdown_test.dart`

Result: **PASS** - 1 file checked, 0 changed.

## Test Results

- Focused `event_dropdown_test.dart`: **PASS**, 7 passed / 0 failed.
- Full Flutter suite: **PASS**, 311 passed / 0 failed.

These QA runs independently reproduce the Engineer's reported counts.

## Diff Safety Review

- `git diff --check`: clean.
- Automated added-line scans found no `TODO`, `FIXME`, `debugPrint(`,
  private-key marker, service-role marker, or credential-like token in the
  implementation/test diff.
- No implementation deletion, production change, generated artifact, golden
  file, integration test, migration, dependency, or unrelated formatting churn
  is present.
- The removed Cycle 2 QA report was an expected Manager action for the duplicate
  guard; its prior verdict and findings were reviewed from the deletion diff
  before this Cycle 3 report was created.

## Change Budget Review

Cycle 3 implementation/test delta against `HEAD`:

| File | Actual | Assessment |
| --- | ---: | --- |
| `event_dropdown_test.dart` | +44 / -16, net +28 | 60 changed lines; within the plan's 40-80 test-line budget |
| Production files | +0 / -0 | Justified: the reported behavior is the existing required-Location gate |

There are no new files, public classes/methods, dependencies, or production
lines. The Cycle 1 historical **[code-quality]** warning concerned a 1.71x
cumulative test-harness budget overage. Cycle 2 did not worsen it, and Cycle 3's
replacement test delta is independently within budget, so the warning does not
repeat.

## Code Efficiency Review

Cycle 3 adds no production symbol or abstraction. The fake repository's
`createRehearsal` override reuses the existing capture pattern. The local
`addButton()` finder is called repeatedly and keeps callback-state assertions
consistent; no equivalent production helper was found or would be appropriate
for a widget test. No unused state, future-facing flag, wrapper widget,
provider, notifier, or dependency was added.

## Manual Verification Punch List

QA cannot exercise a running app. Tony should run these steps on at least one
native platform (macOS or iOS) and Web.

1. Open Home -> Add -> Rehearsal and leave Location empty.
   **Expected:** The `Details` card shows the setlist selector above Notes, and
   Add Rehearsal is disabled because Location is required.
2. While Location is still empty, select a non-catalog setlist, then select
   `None`.
   **Expected:** Both pills respond visually, but Add Rehearsal remains disabled
   because selecting a setlist does not satisfy the Location requirement.
3. Enter a non-whitespace Location such as `Test Studio`.
   **Expected:** Add Rehearsal becomes enabled without requiring a setlist.
4. With `Test Studio` still entered, select a non-catalog setlist, then select
   `None`, then select the setlist again.
   **Expected:** Add Rehearsal stays enabled through every selection change;
   setlist selection never clears Location.
5. Save with `Test Studio` and the non-catalog setlist selected.
   **Expected:** Save succeeds and the Home rehearsal card shows the selected
   setlist name.
6. Reopen that rehearsal through View Rehearsal -> Edit.
   **Expected:** Location is `Test Studio`, the saved setlist pill is selected,
   and the selector remains above Notes in `Details`.
7. Select `None` and save again.
   **Expected:** Save succeeds; reopening shows `None` selected and the Home
   rehearsal card no longer shows a setlist pill.
8. In a band with no setlists, open Add -> Rehearsal and enter a Location.
   **Expected:** `Details` shows `None` and `+ Create Setlist`; Add Rehearsal is
   enabled once Location is non-empty.
9. Create or edit a recurring rehearsal with a valid Location and setlist.
   **Expected:** Save succeeds and each generated rehearsal instance shows the
   selected setlist; clearing with `None` removes the association.
10. Repeat steps 1-7 on Web.
    **Expected:** Location gating, selector behavior, save/reload, and clearing
    match the native platform. If the button remains disabled after step 3,
    record the exact Location value and platform as a new runtime discrepancy.
11. Open Add -> Gig.
    **Expected:** `Show Details` still contains the setlist selector and
    contacts, and the gig Notes card remains separate and unchanged.

## Issues Found

### Critical

None.

### Warnings

None. Cycle 1's historical **[code-quality]** warning was not repeated in
Cycles 2 or 3.

### Suggestions

None.