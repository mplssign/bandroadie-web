# QA_REPORT — bug/gig-blockout-notification-on-every-edit

## Feature Slug

`bug/gig-blockout-notification-on-every-edit`

## Feature Title

Block-out conflict notifications re-sent on every gig edit

## Cycle Number

1

## Final Verdict

**APPROVED**

## Validation Summary

Branch `bug/gig-blockout-notification-on-every-edit` matches both the plan and
report slugs. Working tree is clean except for the expected uncommitted diff
(`lib/features/events/events_repository.dart`), the new test file, and the
untracked `docs/features/bug/gig-blockout-notification-on-every-edit/` folder
— nothing was committed, staged, or pushed during this review. No
`docs/features/bug/gig-blockout-notification-on-every-edit/QA_REPORT.md`
existed prior to this run. All changes reviewed via
`GIT_OPTIONAL_LOCKS=0 git diff HEAD`. Implementation matches the Architect
plan task-for-task; analyzer and full test suite are clean.

## Architect Scope Review

- Only `lib/features/events/events_repository.dart` was modified, matching
  the plan's "Files to Modify" list exactly.
- Only `test/features/events/events_repository_scheduling_test.dart` was
  created, matching "Files to Create" exactly.
- All "Files Off-Limits" confirmed untouched: `event_editor_drawer.dart`, all
  Supabase migrations/RPCs/triggers/Edge Functions (`git status` shows no
  `supabase/` changes), `AutoConflictBlockingService`,
  `BlockOutRepository.createBlockOut`, and
  `_updateAndGenerateRecurringSeries` (verified by reading the untouched
  method body — its tail resync remains unconditional, as intended).
- No auth, routing, init-order, or Firebase config touched.

## Completeness Check

All 5 Engineer task-breakdown items completed and verified in code:

1. **Comparators added** — `didGigSchedulingChange` and
   `didRehearsalSchedulingChange`, plus private `_normalizeDate`, placed
   immediately after imports, before `NoBandSelectedError`, both
   `@visibleForTesting` top-level functions per plan.
2. **`updateGig` gated** — pre-update snapshot fetched via `_gigSelectClause`
   (includes `gig_dates`, so `Gig.additionalDates` hydrates correctly) before
   the `data` map is built; the existing `clearAutoBlocksForSource` +
   `autoBlockConflictingDates` `try/catch` is wrapped in
   `if (didGigSchedulingChange(preGig, formData))`. `.update()`,
   `_syncGigDates`, `_syncGigContacts`, `invalidateCache`, and final re-fetch
   all left unconditional, as specified.
3. **`updateRehearsal` gated (standard path only)** — pre-update snapshot
   (`select('id, band_id, date, is_potential')`) is fetched after the
   `isBecomingRecurring`/`isStoppingRecurring` branches (so it only affects
   the standard path) and before `.update()`; the tail resync block is
   wrapped in `if (didRehearsalSchedulingChange(preRehearsal, formData))`.
   The `Rehearsal` snapshot uses placeholder empty strings for
   `startTime`/`endTime`/`location` (unused fields for this transient,
   comparator-only instance) — confirmed the `Rehearsal` constructor has no
   validation that would reject this.
4. **Tests added** — 9 `didGigSchedulingChange` cases + 4
   `didRehearsalSchedulingChange` cases, covering every Tier 1 case listed in
   the plan (identical/changed date, `is_potential` flip both directions,
   time-of-day normalization, additional-dates match/reorder/add/swap).
5. **Static analysis + tests run by Engineer** — reproduced independently,
   see Analyzer/Test Results below.

No partial implementations, no missing edge cases relative to the plan.

## Behavior Verification

**Code-path analysis only** — no runtime/device testing performed (out of
scope per QA mode rules; see Manual Verification Punch List below).

- Root cause (unconditional resync churning `block_dates` via
  delete+re-insert on every edit) is fixed at its source: the resync block in
  both `updateGig` and `updateRehearsal`'s standard path is now gated on a
  pure pre/post scheduling comparison, not a symptom-level suppression (e.g.
  no debounce, no notification-side filtering).
- Scope match confirmed: no new behavior added beyond the gate itself. Create
  paths (`createGig`/`createRehearsal`) are untouched, matching "creates are
  unaffected" from the plan.
- Type compatibility verified: `Gig.additionalDates` is `List<GigDate>` with
  `.date`; `EventFormData.additionalDates` is `List<AdditionalDateEntry>`
  with `.date` — both align with the comparator's `.map((x) => x.date)` usage.

## Regression Check

**LOW** (matches plan's own risk rating).

- `updateGig`/`updateRehearsal` public signatures unchanged — confirmed by
  the pre-existing `_CapturingEventsRepository extends EventsRepository` spy
  in `test/features/events/widgets/event_dropdown_test.dart` still compiling
  and passing without modification.
- No auth/session, RPC signature, init-order, or platform-conditional code
  touched.
- `_updateAndGenerateRecurringSeries` resync remains unconditional (correct —
  becoming-recurring is always a genuine schedule change).
- Full `test/features/events` suite (38 tests) and full project `flutter
  test` suite (371 tests) both pass with zero failures.

## Database Safety

**Not applicable.** No migrations, RPCs, triggers, or Edge Functions were
added, modified, or referenced in the diff (`git status` shows no `supabase/`
changes). No `SECURITY DEFINER` grant verification required.

## Analyzer Results

```
flutter analyze lib/features/events/events_repository.dart test/features/events/events_repository_scheduling_test.dart
Analyzing 2 items...
No issues found! (ran in 1.1s)
```

Full-project `flutter analyze` also run independently: 1 pre-existing `info`
lint (`use_decorated_box`) in
[lib/features/setlists/widgets/add_to_setlist/pause_screen.dart](lib/features/setlists/widgets/add_to_setlist/pause_screen.dart#L401) —
untouched by this diff, does not block per QA rules (pre-existing violation
in a file the diff doesn't touch).

## Test Results

```
flutter test test/features/events
00:05 +38: All tests passed!
```

```
flutter test
00:56 +371: All tests passed!
```

Both reproduced independently and match the Engineer Report's claimed results.

## Diff Safety Review

- No secrets, API keys, or credentials in the diff.
- No `TODO`/`FIXME` added. The only `debugPrint(` occurrences in the diff are
  the pre-existing `'[EventsRepository] Auto-block resync failed: $e'` lines,
  re-indented one level deeper by the new `if` wrap — not new debug
  artifacts.
- No leftover test scaffolding, no accidental deletions, no unrelated
  formatting churn — diff is confined exactly to the described gate logic.

## Change Budget Review

| File | Budget | Actual | Status |
|---|---|---|---|
| `lib/features/events/events_repository.dart` | +55 to +75 net | +121/-52 = net +69 | Within budget |
| `test/features/events/events_repository_scheduling_test.dart` (new) | +80 to +110 | 161 lines | 161/110 ≈ 1.46x — within the 1.5x tolerance band, noted per plan tolerance, not a Warning |

New files: 1 (matches expected: 1). New public classes: 0 (matches). New
public methods: 0 — the two new symbols are top-level `@visibleForTesting`
functions, not class methods, per plan (matches). New dependencies: 0
(matches — `package:flutter/foundation.dart` was already imported).

## Code Efficiency Review

- No new provider/notifier, no single-use `_buildX()` method, no new
  `FutureBuilder`/`StreamBuilder`, no hand-rolled dedupe beyond a straight
  `Set` comparison (simplest correct form for order-independent set equality).
- **Suggestion:** the file already has a private instance method
  `_isSameDay(DateTime a, DateTime b)` (used at
  [events_repository.dart:683](lib/features/events/events_repository.dart#L683))
  performing the same year/month/day normalization the new top-level
  `_normalizeDate` duplicates. They aren't directly interchangeable as-is
  (`_isSameDay` is bound to the `EventsRepository` instance; the new
  comparators are deliberately free functions per the plan), so this isn't a
  drop-in reuse miss, but the Engineer's stated pre-existing-helper search
  ("no existing helper compares Gig/Rehearsal snapshots against
  EventFormData") is accurate at the snapshot-comparison level while missing
  this lower-level day-normalization overlap. Cosmetic; does not affect
  correctness or maintainability meaningfully enough to block.
- Bug fix has non-zero deletions (-52 lines, from re-indenting the wrapped
  blocks) — not a zero-deletion fix, no Warning triggered under that rule.
- No file crossed a size-target threshold requiring justification.

## Manual Verification Punch List

The plan's Tier 2 punch list requires a running app with real push delivery
across two devices/accounts and is explicitly the owner-run check per the
plan's own classification — not attempted here. Hand verbatim to Tony:

**Setup (once):**

1. Prepare two test accounts: **A** (editor) and **B** (member of a
   different band than the one A is editing in; both bands are in A's One
   Calendar auto-block scope).
2. Confirm A has One Calendar auto-blocking enabled, including the band that
   contains B.
3. Confirm A has an existing confirmed gig in Band X on date D, and that an
   auto-block already exists on Band Y for user A on date D.
4. Confirm B's device is signed in as a member of Band Y with push
   notifications enabled.

**Steps:**

1. On B's device, clear the notification center completely.
2. On A's device, edit the Band X gig — change only the venue name. Save.
   **Expected:** B receives no new "Member Unavailable" push.
3. On A's device, edit the same gig again — change only the start time
   (date stays D). Save.
   **Expected:** B receives no new push.
4. On A's device, edit the same gig again — change the date from D to a new
   conflicting date D+7 (a date on which B has no personal block-out).
   Save.
   **Expected:** B receives exactly one new push referencing D+7 ("A is
   unavailable on {D+7}"), and the auto-block on date D is removed from Band
   Y's block-out list.
5. Repeat steps 1–4 for a confirmed rehearsal in Band X (same B in Band Y).
6. Create a brand-new confirmed gig in Band X on a fresh conflicting date.
   **Expected:** B receives exactly one push (create-time notification —
   unchanged by this fix).

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

1. **[code-quality]** `_normalizeDate` (new, top-level) duplicates the
   day-level normalization logic already present in the file's existing
   private instance method `_isSameDay`
   ([events_repository.dart:683](lib/features/events/events_repository.dart#L683)).
   Not a drop-in reuse fix given the different binding (instance vs.
   top-level free function required by the plan's `@visibleForTesting`
   design), but worth a mental note for a future pass that touches this file
   again. Non-blocking.
