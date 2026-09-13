# QA_REPORT - Reorder Financials in Quick Actions

## Feature Slug

`quick-actions-financials-order`

Branch: `feature/quick-actions-financials-order`

## Feature Title

Reorder Financials in Quick Actions

## Cycle Number

1

## Final Verdict

APPROVED

## Validation Summary

The uncommitted implementation matches the Architect plan. The Financials block
now renders between Add Event and Create Setlist, the planned widget test locks
the all-visible order, static analysis is clean, and all 322 Flutter tests pass.
The plan uses the branch-form slug and the Engineer report uses the bare feature
slug; both resolve to the requested feature/branch pair.

## Architect Scope Review

- Modified only
  [lib/features/home/widgets/quick_actions_row.dart](../../../lib/features/home/widgets/quick_actions_row.dart)
  in production code.
- Created only the planned implementation test,
  [test/features/home/widgets/quick_actions_row_test.dart](../../../test/features/home/widgets/quick_actions_row_test.dart).
- The Architect plan, Engineer report, and this QA report are expected pipeline
  artifacts.
- All named off-limits consumers and feature directories are untouched.
- No dependency, API, provider, controller, repository, routing, or database
  change was introduced.

## Completeness Check

- The Financials button block is immediately after Add Event and before Create
  Setlist.
- Each existing conditional 12px spacer guard remains intact.
- The new test pumps the widget under `MaterialApp` and `Scaffold`, supplies all
  three callbacks and explicit visibility flags, extracts `OutlinedButton`
  labels in tree order, and asserts the exact planned list.
- No consumer call site was changed.

All Architect tasks are complete.

## Behavior Verification

Code-path analysis confirms the list construction order is now `+ Add Event`,
`Financials`, `+ Create Setlist`. The focused widget test exercised and passed
that behavior. Code-path analysis also confirms that hiding Financials leaves
`+ Add Event` followed by `+ Create Setlist` with the existing spacer logic.

No live app, simulator, emulator, device, or browser verification was performed;
the plan correctly classifies those checks as owner-run rather than QA gates.

## Regression Check

Overall regression risk: **LOW**.

- Gigs, rehearsals, setlists, members, auth/session, routing, and notifications:
  unaffected; no related code changed.
- Platform parity: low risk; all platforms execute the same platform-agnostic
  widget code.
- RPC signatures, parameter order, and initialization order: unchanged.
- Controller/FocusNode disposal, async `setState`, and rebuild frequency:
  unchanged or not applicable to this `StatelessWidget` reorder.
- RBAC visibility and navigation callbacks: unchanged; each label remains paired
  with its original callback and visibility flag.

## Database Safety

Not applicable. No SQL, migration, Supabase RPC, RLS, grant, or data-access file
was added or modified.

## Analyzer Results

`flutter analyze`: **PASS** - no issues found at any severity.

## Test Results

- `flutter test test/features/home/widgets/quick_actions_row_test.dart`:
  **PASS** - 1 passed, 0 failed.
- `flutter test`: **PASS** - 322 passed, 0 failed.

## Diff Safety Review

- `git diff --check`: clean.
- No `TODO`, `FIXME`, or `debugPrint(` artifact was found in the implementation
  or feature artifacts.
- No secret or API-key pattern, test scaffolding, accidental deletion, or
  unrelated formatting churn was found.
- No source file, migration, or config outside the approved scope changed.

## Change Budget Review

- Production file: 6 additions and 6 deletions, net 0 lines, exactly matching
  the plan's zero-net-line reorder budget.
- New implementation files: 1 planned 34-line widget test, matching the planned
  one-file budget.
- New public library classes/methods: 0, matching budget.
- New dependencies: 0, matching budget.

## Code Efficiency Review

No helper, extension, utility, private widget, provider, wrapper, field, or
configuration symbol was added. The test directly exercises the existing public
widget and contains one behavior assertion. No duplicate abstraction search was
required because the diff introduces no abstraction or helper-like symbol. No
code-efficiency or maintenance-burden finding was identified.

## Manual Verification Punch List

1. Launch the app on macOS: `./run.sh macos`. Sign in as an admin (or a member)
   of a band where you have permission to create events, create setlists, and
   view financials.
2. Navigate to the Home tab and scroll to the "Quick Actions" section.
   - Expected: three buttons appear left-to-right in this exact order:
     `+ Add Event`, `Financials`, `+ Create Setlist`.
3. Launch the app on iOS via `./run.sh ios` and repeat step 2.
   - Expected: identical order to step 2.
4. Launch the app on Android via `flutter run -d android` (emulator or connected
   device) and repeat step 2.
   - Expected: identical order to step 2.
5. Launch the app on Web via `flutter run -d chrome` and repeat step 2.
   - Expected: identical order to step 2.
6. On any platform, switch to a contributor account that lacks the
   "Can view financials" sub-permission but retains setlist and event
   permissions.
   - Expected: the Home tab's Quick Actions section shows exactly two buttons in
     order `+ Add Event`, `+ Create Setlist` (the `Financials` button is hidden;
     the remaining two collapse together with the standard 12px gap).

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.