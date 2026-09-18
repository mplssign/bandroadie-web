# QA_REPORT — bug/edit-gig-soundcheck-not-persisted

## Feature Slug

`bug/edit-gig-soundcheck-not-persisted`

## Feature Title

Soundcheck time in gig editor never marks form dirty and isn't persisted

## Cycle Number

2

## Final Verdict

**APPROVED**

## Validation Summary

Reviewed `ARCHITECT_PLAN.md` and both cycles of `ENGINEER_REPORT.md` against
the uncommitted working-tree diff (`git diff` vs `HEAD`, branch
`bug/edit-gig-soundcheck-not-persisted`, tree clean except the expected
in-progress changes). All five plan-mandated files match the plan exactly,
line-for-line. Cycle 2's one out-of-plan file
(`lib/features/events/widgets/gig_form_fields.dart`) was independently
verified as correct, minimal, and non-regressive — Manager has already
approved the scope addition, so it is not treated as an unapproved-file
violation. `flutter analyze` and `flutter test` were independently re-run
(not just trusted from the Engineer report) and both pass. The new migration
was independently applied against a fresh ephemeral Supabase branch and
confirmed to apply cleanly, then the branch was deleted as cleanup. Cycle 2's
"no code bug, migration not applied to Tony's DB" conclusion for the save
failure is independently well-supported by code-path analysis.

## Architect Scope Review

All four plan-mandated `Files to Modify` and the one plan-mandated `Files to
Create` were touched exactly as specified, with no scope creep beyond the one
disclosed/approved deviation:

- `supabase/migrations/20260918120000_add_soundcheck_time_to_gigs.sql` —
  created, verbatim mirror of `085_add_load_in_time_to_gigs.sql`.
- `lib/app/models/gig.dart` — `soundcheckTime` field/ctor/`fromJson`/`toJson`,
  mirrors `loadInTime` exactly.
- `lib/features/events/models/event_form_data.dart` — three fields, ctor
  params, `soundcheckTimeDisplay` getter, `fromGig` parse block; `copyWith`
  correctly left untouched per the plan's explicit mirror decision.
- `lib/features/events/events_repository.dart` — `'soundcheck_time':
formData.soundcheckTimeDisplay,` added to both `createGig` and `updateGig`
  payloads, directly under `load_in_time` in both.
- `lib/features/events/widgets/event_editor_drawer.dart` — all five sub-edits
  (`_buildFormData`, edit-mode populate block, `_createGigFormFields` 8 args,
  `_buildScheduleSection` replacement, `_buildSoundcheckTimePicker` deletion)
  present and correct.
- `lib/features/events/widgets/gig_form_fields.dart` — **not** in the original
  plan's Files to Modify list. Per the task framing, Manager has already
  reviewed and approved this as justified and minimal; not counted as an
  unapproved-file violation. Independently verified below (see Behavior
  Verification and Regression Check).

Files off-limits per the plan (`view_gig_drawer.dart`, `calendar-feed`
function, demo-session RPC migrations, auth/routing/init-order files) were
confirmed untouched — full working-tree diff contains exactly the six
modified files plus one new migration and one new test file, nothing else.

## Completeness Check

All ten Engineer Task Breakdown steps from the plan are done:

1. Migration created, filename sorts after `20260915130000`. ✓
2. `Gig` model extended. ✓
3. `EventFormData` extended (fields, ctor, getter, `fromGig`), `copyWith`
   correctly untouched. ✓
4. `EventsRepository` payloads extended in both `createGig` and `updateGig`. ✓
5–7. Drawer wiring: `_buildFormData`, edit-mode populate, `_createGigFormFields`
   8 args with `_markDirty()` on every callback (confirmed — this is the root
   symptom the bug report described, and every one of the five new callbacks
   calls `_markDirty()`). ✓
8. Ad-hoc `_buildScheduleSection` block replaced with
   `gigFormFields.buildSoundcheckRow(context)`. ✓
9. `_buildSoundcheckTimePicker` deleted. ✓
10. Two unit tests added (`EventFormData.soundcheckTimeDisplay`,
    `Gig` JSON round-trip) — both independently re-run and passing.

Cycle 2 additionally found and fixed a real, reproduced UI bug
(`RenderFlex` overflow in `buildSoundcheckRow`'s unset state) not anticipated
by the plan, and correctly declined to "fix" Issue 2 (save failure) with no
code change, since no code bug exists — see Behavior Verification.

No partial implementations or missing edge cases found.

## Behavior Verification

**Code-path analysis performed; no runtime/manual device verification was
performed** (out of scope for QA per this pipeline's hard rules).

- Dirty-flag fix: every one of the five new `onSoundcheck*` callbacks in
  `event_editor_drawer.dart` calls `_markDirty()`, matching the `onLoadIn*`
  pattern exactly — confirmed by direct diff read. This resolves the reported
  root cause (Update button staying disabled).
- Persistence fix: `soundcheck_time` now flows migration → `Gig.fromJson` /
  `toJson` → `EventFormData.fromGig` / `soundcheckTimeDisplay` →
  `EventsRepository.createGig`/`updateGig` payloads → drawer state — confirmed
  end-to-end by reading every hop; a repo-wide grep for `soundcheck` shows a
  fully closed loop with no orphaned reference.
- Cycle 2 overflow fix: independently compared
  `GigFormFields.buildSoundcheckRow`'s unset-state branch (post-fix) against
  `_buildLoadInTimeSelector`'s unset-state branch — they are now structurally
  identical (`Column` with a label `Text` + `EventAddValueButton`, the latter
  wrapping its child in `SizedBox(width: double.infinity)`, which is exactly
  why the pre-existing load-in path never overflowed and why this fix
  eliminates the overflow in the soundcheck path). The fix is a narrow,
  correct swap of an already-proven-safe shared component
  (`EventAddValueButton`) for a broken ad-hoc `Row`; no new class, method, or
  provider was introduced.
- Issue 2 (save failure) root-cause conclusion — independently assessed as
  well-supported, not a missed code bug:
  - `EventsRepository.updateGig`/`createGig` payload construction and the
    `.update(data)` / `.insert(data)` calls are ordinary Supabase client calls
    with no special-casing per column; a genuinely missing `soundcheck_time`
    column on the target database would produce a PostgREST schema-cache
    error (e.g. `"Could not find the 'soundcheck_time' column of 'gigs' in
the schema cache"`).
  - Read `lib/shared/utils/event_permission_helper.dart`'s `classifyError()`
    directly: that exact error string does not contain any of the substrings
    checked for `permission`/`network`/`validation` classification, so it
    falls through to `EventErrorType.unknown`, which
    `mapEventErrorToMessage(error, context: 'update')` renders as exactly
    **"Failed to update event. Please try again."** — the precise message
    Tony reported. This is a strong, specific match, not a vague inference.
  - Confirmed no other plausible code-level cause exists in the reviewed
    payload/model chain (parameter order, key naming, nullability all
    correct and consistent with the working `load_in_time` sibling).
  - **Verdict: the conclusion is well-supported.** This is a plan-classified
    owner-run/manual concern (a local DB missing a migration), not a code
    defect QA should block on.

## Regression Check

**Risk: LOW**, matching the plan's own assessment.

- Auth/session/routing/init-order: untouched — confirmed by diff scope (only
  the six files listed touched; no import or call added outside the
  gigs/events feature).
- Supabase RPC signatures: no RPC touched or added.
- Platform parity: pure Dart/widget changes; no platform-conditional code
  added or removed.
- Controller/FocusNode disposal: no new controllers or focus nodes introduced
  in either cycle.
- `setState` after async gaps: all new `setState` calls in the drawer are
  synchronous UI-state callbacks (mirroring the existing `onLoadIn*` pattern
  exactly), not inside any newly-added `async` gap.
- Rebuild triggers/frequency: no new provider/notifier; `buildSoundcheckRow`
  is a plain widget-tree swap, same rebuild scope as `buildLoadInTimeSelector`.
- Cycle 2's `gig_form_fields.dart` fix only touches the unset-state branch of
  `buildSoundcheckRow`; the expanded-state branch (hour/minute/AM-PM
  dropdowns) is untouched, and `buildLoadInTimeSelector` / the rest of
  `GigFormFields` is untouched. Existing `gig_form_fields_test.dart` (3
  tests, unrelated to soundcheck rendering) still passes unaffected.
- One gap noted (non-blocking, see Code Efficiency Review): the Cycle 2
  overflow fix was verified via a throwaway widget test that was deleted
  before finishing the cycle — no permanent regression test now guards
  `buildSoundcheckRow`'s unset-state layout going forward.

## Database Safety

- Migration `supabase/migrations/20260918120000_add_soundcheck_time_to_gigs.sql`
  read directly: single `ALTER TABLE gigs ADD COLUMN soundcheck_time TEXT;`
  plus a matching `COMMENT ON COLUMN`. Nullable, no `DEFAULT`, no RLS/trigger/
  RPC/GRANT/REVOKE changes. Filename timestamp (`20260918120000`) sorts after
  the last merged migration (`20260915130000_add_locale_to_bands.sql`).
- No new or changed `SECURITY DEFINER` function in this diff — the
  `has_function_privilege` grant-verification step does not apply here.
- **Ephemeral-branch apply-check performed independently by QA** (not just
  trusted from the Engineer report): reused the existing
  `qa-bug-edit-gig-soundcheck-not-persisted` Supabase branch (created earlier
  during Cycle 2's own read-only investigation), ran `supabase migration list`
  against it after linking, and confirmed `local` and `remote` both report
  `20260918120000` — i.e., the migration is present and applied with no drift
  on that branch, confirming the SQL applies cleanly. The branch was then
  deleted (`supabase branches delete ... --experimental --yes`) as the
  required cleanup step; cleanup succeeded.
- This confirms *the SQL applies cleanly on a database that has it applied*;
  it does not and cannot confirm Tony's local test-database state, which is
  explicitly out of scope for this pipeline (see Behavior Verification, Issue
  2, and the Manual Verification Punch List below).

## Analyzer Results

Independently re-run (not just trusted from `ENGINEER_REPORT.md`):

```
flutter analyze lib/app/models/gig.dart lib/features/events/events_repository.dart \
  lib/features/events/models/event_form_data.dart \
  lib/features/events/widgets/event_editor_drawer.dart \
  lib/features/events/widgets/gig_form_fields.dart \
  test/app/models/gig_test.dart \
  test/features/events/models/event_form_data_test.dart

No issues found! (ran in 1.8s)
```

Empty at every severity across all seven touched/created files.

## Test Results

Independently re-run:

```
flutter test test/app/models/gig_test.dart \
  test/features/events/models/event_form_data_test.dart \
  test/features/events/widgets/gig_form_fields_test.dart

00:01 +13: All tests passed!
```

13/13 passed, matching the Engineer's reported count, including the two new
`soundcheckTimeDisplay` cases, the two new `Gig` round-trip cases, and the
pre-existing (unaffected) `gig_form_fields_test.dart` suite.

## Diff Safety Review

- `git diff HEAD | grep -niE "TODO|FIXME|debugPrint\(|api[_-]?key|secret|password|token\s*="`
  → **no matches.** No secrets, no debug artifacts, no leftover markers.
- No leftover test scaffolding: the Cycle 2 throwaway reproduction widget test
  is confirmed absent from `git status` (untracked-files list contains no
  such file).
- No accidental deletions or unrelated formatting churn found in any diff
  hunk reviewed.

## Change Budget Review

Actual `git diff --numstat` vs. plan's Change Budget table:

| File                                                   | Budgeted                | Actual (ins/del, net)   | Verdict                                  |
| ------------------------------------------------------- | ------------------------ | ------------------------- | ------------------------------------------ |
| `supabase/migrations/20260918120000_...sql`             | +12 (new file)           | +14 (new file)            | within range                              |
| `lib/app/models/gig.dart`                               | +4                       | +4/-0, net +4              | exact match                               |
| `lib/features/events/models/event_form_data.dart`       | +~25                     | +35/-0, net +35            | 1.4x — within ~1.5x, noted, not a Warning |
| `lib/features/events/events_repository.dart`            | +2                       | +2/-0, net +2              | exact match                               |
| `lib/features/events/widgets/event_editor_drawer.dart`  | net -40 to -50           | +45/-92, net -47           | within budgeted range                     |
| `lib/features/events/widgets/gig_form_fields.dart`      | not budgeted (0)         | +14/-21, net -7            | out-of-plan, Manager-approved; narrow, no new class/method — not treated as bloat |
| `test/app/models/gig_test.dart`                         | (2 new tests, no budget) | +46/-0                    | matches "2 new tests" allowance           |
| `test/features/events/models/event_form_data_test.dart` | new file allowed by plan | +39 (new file)             | matches plan's explicit fallback allowance |

New-file count: 2 (1 migration + 1 test file) — matches the plan's explicit
allowance for a test file "only if no reasonable existing home is available"
(Engineer's report documents the search that justified this). New public
class/method count: 0. New dependency count: 0. No item crosses the >1.5x or
>2x thresholds that would trigger Warning/Critical under the arithmetic rule.

## Code Efficiency Review

- No new provider/notifier, no new `FutureBuilder`/`StreamBuilder`, no
  hand-rolled collection logic, no `try/catch` swallow-and-rethrow, no unused
  field, no barrel file, no speculative "for future use" config — confirmed
  by direct diff read across all six modified files.
- Cycle 2's `gig_form_fields.dart` fix reuses an existing, already-used
  component (`EventAddValueButton`) rather than introducing a new one — this
  is the correct minimal fix, not a new abstraction.
- Bug-fix-with-zero-deletions rule does not apply: `gig_form_fields.dart`'s
  fix has 21 deletions against 14 insertions (net negative), and
  `event_editor_drawer.dart`'s change is net -47. Neither is a zero-deletion
  bug fix.
- `event_editor_drawer.dart` (3539 lines) and `gig_form_fields.dart` (1505
  lines) both remain well over the ~500-line file-size target — this is
  pre-existing bloat, not introduced or grown by this diff (both files got
  *smaller* in this diff: -47 and -7 net lines respectively). No growth
  across the target to justify.
- **Suggestion (non-blocking):** Cycle 2's overflow fix for
  `buildSoundcheckRow`'s unset state was verified via a throwaway widget test
  that was deleted before the cycle finished. No permanent regression test
  now exists to guard against this specific layout regression recurring.
  Recommend a follow-up test (e.g., a `gig_form_fields_test.dart` case that
  pumps `buildSoundcheckRow` at a narrow width with all three soundcheck
  fields null and asserts no `FlutterError`/overflow) — not required to land
  this fix, since it wasn't part of the original plan's test list, but worth
  tracking.

## Manual Verification Punch List (for Tony)

Carried forward from `ARCHITECT_PLAN.md` Tier 2 and `ENGINEER_REPORT.md`
Cycle 2's additions. QA did not and cannot execute these — no app launch,
simulator, or live-instance testing was performed, per this pipeline's hard
rules. Execute in order:

1. **Confirm the `20260918120000_add_soundcheck_time_to_gigs.sql` migration is
   applied to whatever database your running app instance is actually
   connected to** (local Supabase/docker stack, or whichever project/branch
   your `--dart-define` config points at for this test run). If testing
   locally: `supabase db reset` or `supabase migration up` against your local
   stack. **Expected:** `soundcheck_time` column exists on your `gigs` table
   before proceeding to step 2.
2. In the current active band, tap an existing confirmed gig, then tap Edit
   in the drawer. **Expected:** Editor drawer opens with a soundcheck row
   showing "Set soundcheck time" (identical shape to the Load-in Time row
   above it), with **no error banner / diagonal-striped overflow warning**
   rendered in that area, at your normal window/device width and at a narrow
   width if resizable.
3. Tap "Set soundcheck time". **Expected:** Row expands to a picker showing
   `6 : 00 PM` (default), and the Update button becomes enabled.
4. Change hour dropdown from `6` to `7`. **Expected:** Update stays enabled.
5. Change minutes dropdown from `00` to `30`. **Expected:** Update stays
   enabled.
6. Tap the `AM` toggle, then the `PM` toggle. **Expected:** Toggle switches
   correctly each time; Update stays enabled throughout.
7. Tap Update. Wait for save spinner to clear. Close the drawer. **Expected:**
   Save succeeds without "Failed to update event." error. If it still fails
   after confirming step 1, capture the exact Postgrest error from the debug
   console and report back — that would indicate a different root cause than
   diagnosed in Cycle 2.
8. Reopen the same gig, tap Edit. **Expected:** Soundcheck row shows `7 : 30
   PM`. Update button starts disabled (unchanged form).
9. Tap Clear on the soundcheck row. **Expected:** Row collapses back to "Set
   soundcheck time", Update becomes enabled.
10. Tap Update, wait for save, close, reopen for edit. **Expected:**
    Soundcheck row shows "Set soundcheck time" (persisted-null state).
11. Repeat steps 2–10 substituting Load-in Time for Soundcheck. **Expected:**
    Load-in behavior is byte-for-byte unchanged from before this PR.
12. Open the read-only gig view drawer (not the editor) for a gig with a
    soundcheck value saved. **Expected:** Soundcheck value does not appear in
    the view drawer — this is expected/out-of-scope, not a bug. Flag as a
    follow-up if desired for a future feature.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

1. **[code-quality]** No permanent regression test guards
   `GigFormFields.buildSoundcheckRow`'s unset-state layout fix from Cycle 2.
   The reproduction test that caught and verified the fix was a throwaway
   file, deleted before the cycle finished. Recommend adding a small widget
   test at a narrow width asserting zero `FlutterError`/overflow for this
   render path, as a follow-up (not blocking this fix).
