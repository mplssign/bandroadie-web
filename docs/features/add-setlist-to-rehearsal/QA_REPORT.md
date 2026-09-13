# QA REPORT

## Feature Slug

`feature/add-setlist-to-rehearsal`

## Feature Title

Add a setlist to a rehearsal

## Cycle Number

1

## Final Verdict

APPROVED

## Validation Summary

The implementation matches the Architect plan: the existing setlist selector is mounted in the rehearsal branch between Location and Notes, and the requested widget coverage observes both selection and clearing through the existing repository save path. The changed-file analyzer passed, the focused test file passed 7/7, and the full suite passed 311/311.

Overall regression risk is **LOW**. No running app, simulator, emulator, or browser was launched; the runtime checks are correctly classified by the Architect as owner-run and are reproduced below.

## Architect Scope Review

- The plan, Engineer report, and branch all use `feature/add-setlist-to-rehearsal`.
- The only tracked changes are `lib/features/events/widgets/event_editor_drawer.dart` and `test/features/events/widgets/event_dropdown_test.dart`, exactly as authorized.
- The production diff is limited to the planned five-line `_SectionCard` insertion in the rehearsal layout.
- The gig and block-out branches, `_buildShowPrepSection`, providers, repositories, models, migrations, routing, initialization, platform configuration, and all files marked off-limits are unchanged.
- No code file, public API, dependency, migration, RPC, or architectural abstraction was added.

## Completeness Check

- The rehearsal layout renders a `Setlist` section between Location and Notes.
- The section reuses `EventFormFields.buildSetlistSelector` unchanged.
- The test pumps an edit-mode rehearsal with exactly one non-catalog setlist.
- The test confirms the `Setlist` text renders.
- Selecting `Road Set` reaches `EventFormData.setlistId` as `setlist-1` through `EventsRepository.updateRehearsal`.
- Selecting `None` and saving again reaches `EventFormData.setlistId` as `null`.
- Existing test groups were not moved or modified.

All Architect tasks are complete.

## Behavior Verification

**Method:** code-path analysis plus widget-test execution; not runtime device testing.

The root cause was the missing selector mount in the rehearsal branch. The production hunk fixes that root cause directly. The existing selector callback updates `_selectedSetlistId` and `_selectedSetlistName`; `_buildFormData()` emits those values; and the unchanged repository writes `formData.setlistId` on rehearsal create, update, and recurring-series paths.

The focused test exercised the public edit/save path twice and independently confirmed the selected ID and cleared `null` value captured by the repository test double.

## Regression Check

Overall risk: **LOW**.

| System | Risk | Evidence |
| --- | --- | --- |
| Rehearsals | LOW | Planned UI insertion; render/select/clear save path passed. Existing create/update/recurring persistence remains unchanged. |
| Gigs | LOW | Gig branch and Show Details helper have no diff; full suite passed. Owner-run step 7 covers runtime presentation. |
| Block-outs | LOW | Conditional branch has no diff; full suite passed. |
| Setlists | LOW | Existing provider and selector are reused unchanged; focused test uses the real selector behavior. |
| Members/Auth/Routing | LOW | No provider contract, session, permission, or route changes. |
| Notifications | LOW | No trigger or notification code changed. |
| Platforms | LOW | Shared Flutter widget only; no platform-conditional or configuration change. Native/Web parity remains owner-run. |

No RPC signature or parameter order changed. Initialization order is unchanged. No Controller or FocusNode lifecycle was added or altered, no async production callback was introduced, and no new rebuild source was added beyond mounting the existing band-scoped selector in the intended rehearsal layout.

## Database Safety

Not applicable. The diff contains no SQL, migration, RPC, RLS, grant, schema, or repository change. Migration apply and `has_function_privilege` checks are therefore not required by the plan.

## Analyzer Results

`flutter analyze lib/features/events/widgets/event_editor_drawer.dart test/features/events/widgets/event_dropdown_test.dart`

Result: **PASS** — `No issues found!` at every severity.

## Test Results

- Focused test file, `test/features/events/widgets/event_dropdown_test.dart`: **PASS**, 7 passed / 0 failed.
- Full Flutter suite: **PASS**, 311 passed / 0 failed.

These runs independently reproduce the Engineer's reported counts.

## Diff Safety Review

- `git diff --check`: clean.
- Required diff scan found no added `TODO`, `FIXME`, or `debugPrint(`.
- No secret or real API credential is present; `https://test.supabase.co` and `test-anon-key` are explicit test placeholders.
- No accidental deletion, generated artifact, golden file, integration test, test scaffold outside the authorized file, or unrelated formatting churn is present.
- Post-validation status showed no additional files changed by analysis or tests.

## Change Budget Review

| File | Architect Budget | Actual | Assessment |
| --- | ---: | ---: | --- |
| `event_editor_drawer.dart` | +5 to +8 | +5 / -0 | Within budget |
| `event_dropdown_test.dart` | +40 to +80 | +149 / -0 | 1.86x the upper estimate |
| Total Dart diff | At most +90 | +154 / -0 | 1.71x the total cap |

The total exceeds the plan cap by 1.71x, which requires a `code-quality` Warning under the QA rubric. It does not cross the 2x Critical threshold. The deviation is documented in the Engineer report and is isolated to private test harness code needed to prevent Supabase access and capture the existing public save path.

The zero-deletion bug fix is justified: the root cause was a missing UI section, so no production line needed replacement or removal. The Engineer also documented why the pre-existing 3,585-line production file remains above its size target under the Architect's no-refactor constraint.

## Code Efficiency Review

Independent searches found no reusable equivalent for the new test symbols in `lib/`. Similar members, contacts, and venues stubs exist only as private classes in other test files and cannot be imported. Every new private stub in this diff is used by the drawer harness; there is no new production helper, provider, notifier, wrapper, dead parameter, unread field, or future-facing configuration.

The enlarged test harness is locally necessary and does not create Critical-level bloat, but its arithmetic budget overage remains recorded as a Warning.

## Manual Verification Punch List

QA cannot exercise a running app; these steps are for Tony at PR-test / apply time. Run each on at least one native platform (macOS or iOS) plus Web to confirm platform parity.

1. Open Home → Add → Rehearsal.
   **Expected:** A "Setlist" section is visible between the Location section
   and the Notes section, showing at least a "None" pill and any existing
   band setlists as pills.
2. Fill in required rehearsal fields (location, date, time). Tap a setlist
   pill (any non-catalog setlist). Save.
   **Expected:** Save succeeds. The rehearsal card on Home shows the selected
   setlist name in the setlist pill.
3. Reopen the same rehearsal via View Rehearsal → Edit.
   **Expected:** The "Setlist" section is present and the previously chosen
   pill is highlighted as selected.
4. Tap the "None" pill. Save.
   **Expected:** Save succeeds. Reopening the rehearsal shows "None"
   selected and the setlist pill disappears from the rehearsal card.
5. In a band that has no setlists yet, open Add → Rehearsal.
   **Expected:** The "Setlist" section shows a "None" pill plus a
   `+ Create Setlist` shortcut (identical to the gig editor's behaviour).
6. Repeat step 2 on Web (bandroadie.com).
   **Expected:** Same visual layout, same save behaviour, same reload
   behaviour — confirms platform parity.
7. Confirm gigs are unchanged: open Add → Gig, verify the "Show Details"
   section still renders the setlist selector plus the contacts subsection.

## Issues Found

### Critical

None.

### Warnings

1. **[code-quality] Change-budget overage:** The test diff is +149 lines versus the +80 upper estimate (1.86x), and the total Dart diff is +154 versus the +90 cap (1.71x). The excess is documented, test-only, private, and justified by the full drawer's isolation and capture requirements; it does not block approval under the Critical-level bloat threshold.

### Suggestions

None.