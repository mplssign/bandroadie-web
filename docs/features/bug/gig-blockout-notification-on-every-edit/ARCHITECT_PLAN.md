# ARCHITECT_PLAN — bug/gig-blockout-notification-on-every-edit

## Feature Slug

`bug/gig-blockout-notification-on-every-edit`

## Feature Title

Block-out conflict notifications re-sent on every gig edit

## Problem Summary

Every time a user edits a confirmed gig (or a confirmed rehearsal), the members
of their *other* bands receive a fresh **"Member Unavailable"** push, even when
the edit did not change the date. Non-date edits (venue name, times, notes,
gig pay, etc.) trigger the same notification storm as the initial creation.
Expected behavior per the Feature Input: the block-out conflict push should
fire only when the edit genuinely introduces a new conflict (i.e., the gig's
scheduling actually changed).

## Root Cause

Confidence: **HIGH** (verified end-to-end in code + migrations).

`EventsRepository.updateGig()` in
[lib/features/events/events_repository.dart](lib/features/events/events_repository.dart#L849-L881)
unconditionally runs an auto-block *resync* on every update — no matter what
changed:

```dart
// updateGig, ~L849–L881
await _autoConflictBlockingService.clearAutoBlocksForSource(sourceGigId: gigId);
if (!formData.isPotentialGig) {
  // …
  await _autoConflictBlockingService.autoBlockConflictingDates(
    userId: userId,
    eventBandId: bandId,
    eventDates: allDates,
    // …
    sourceGigId: gigId,
  );
}
```

That two-step is a **DELETE + re-INSERT** of the actor's auto-generated rows in
[public.block_dates](supabase/migrations/20260804120000_add_block_dates_source_traceability.sql)
for every other band they belong to. Each of those INSERTs fires the
`blockout_created_notification` trigger
([supabase/migrations/20260901170853_fix_notification_trigger_gaps.sql](supabase/migrations/20260901170853_fix_notification_trigger_gaps.sql#L204-L209)),
which calls `notify_blockout_created()` →
[notify_band_members()](supabase/migrations/20260220120000_secure_push_notification_trigger.sql#L182-L219),
which inserts a `notifications` row for every member of that other band except
the actor, which fires `trigger_send_push_notification` → the actual FCM push.

Net effect on a non-date edit:

1. `clearAutoBlocksForSource` deletes N rows (no notification — DELETE doesn't
   fire the trigger).
2. `autoBlockConflictingDates` re-inserts the same N rows.
3. Trigger re-fires, N pushes to every other band's roster (minus the actor).

The exact same defect exists in
[updateRehearsal()](lib/features/events/events_repository.dart#L430-L462) (standard
non-recurring update path) and, more narrowly, at the tail of
[_updateAndGenerateRecurringSeries()](lib/features/events/events_repository.dart#L575-L615).

The `_showBlockOutConflictDialog` in the drawer
([lib/features/events/widgets/event_editor_drawer.dart:1607](lib/features/events/widgets/event_editor_drawer.dart#L1607))
is a purely local "Availability Notice" dialog shown only to the editor. It is
**not** the push described in the bug report and is left out of scope.

The DB triggers themselves (`gig_created_notification`,
`blockout_created_notification`) are correctly bound `AFTER INSERT` only —
they are innocent bystanders. The bug is entirely in the client-side resync
churning `block_dates` rows on every save.

## Existing System Analysis

The auto-conflict-blocking system (One Calendar) is client-driven:

- [AutoConflictBlockingService](lib/features/calendar/auto_conflict_blocking_service.dart)
  fetches the actor's One Calendar prefs, resolves which other bands should
  receive auto-blocks, and calls `BlockOutRepository.createBlockOut()` per
  (date × other-band). `createBlockOut()` inserts directly into `block_dates`,
  relying on `UNIQUE (user_id, band_id, date)` to skip actual duplicates.
- `clearAutoBlocksForSource()` deletes by `source_gig_id` / `source_rehearsal_id`
  — the traceability columns added in
  [20260804120000_add_block_dates_source_traceability.sql](supabase/migrations/20260804120000_add_block_dates_source_traceability.sql).
- The resync pattern (`clear → re-insert`) works correctly when the underlying
  event date set changes (old blocks must be removed, new ones inserted). It's
  wrong only when nothing scheduling-related changed — in that case the
  DELETE+INSERT produces identical rows, but the intermediate DELETE evicts the
  row long enough that the re-INSERT looks brand-new to the trigger.

The fix therefore has to gate the resync on "did the schedule-relevant subset
of the update actually change?" — a pure compare of `(main date, is_potential,
additional_dates set)` for gigs and `(main date, is_potential)` for rehearsals
(rehearsals' current auto-block only covers the main date, not
`rehearsal_dates`).

## Proposed Solution

Introduce a small pure comparator and gate the resync on it. Same principle
applied to `updateGig`, the standard-update path of `updateRehearsal`, and the
tail resync of `_updateAndGenerateRecurringSeries`.

Per-call-site behavior after the fix:

1. **`updateGig`** — fetch a pre-update snapshot of the gig (with `gig_dates`)
   before applying the update. Compute `didGigSchedulingChange(pre, formData)`.
   Wrap the existing `clearAutoBlocksForSource` + `autoBlockConflictingDates`
   block in `if (schedulingChanged) { … }`. Non-scheduling edits skip the
   resync entirely.

2. **`updateRehearsal` (standard path)** — same pattern. Fetch pre-update
   `rehearsals` row, compute `didRehearsalSchedulingChange(pre, formData)`,
   gate the tail resync block. `_updateAndGenerateRecurringSeries` and the
   `isStoppingRecurring` child-deletion branch are separate call sites and are
   handled independently:
   - `_updateAndGenerateRecurringSeries` (becoming-recurring): schedule
     genuinely changes (0 → N dates); its tail resync stays unconditional
     (still fires notifications, but that's legitimate — new dates are new
     conflicts).
   - Stopping-recurring: children are deleted with their block_dates cleaned
     up in `_deleteChildRehearsals`; the parent then falls through to the
     standard update path, where the same gate applies. If neither date nor
     `is_potential` changed, no parent notification fires (correct — the parent
     block_date remained valid throughout).

3. **Comparator** — two top-level pure functions in the same
   `events_repository.dart` file (no new file), annotated
   `@visibleForTesting`:

   ```dart
   @visibleForTesting
   bool didGigSchedulingChange(Gig preGig, EventFormData formData);

   @visibleForTesting
   bool didRehearsalSchedulingChange(Rehearsal preRehearsal, EventFormData formData);
   ```

   `didGigSchedulingChange` returns true iff any of these differ between
   `preGig` and `formData`:
   - Main date (compared as y/m/d only — the DB column is `DATE`).
   - `is_potential` boolean.
   - Set of additional dates (normalized to y/m/d).

   `didRehearsalSchedulingChange` returns true iff main date or `is_potential`
   differs (rehearsal auto-block only covers the main date today — deliberately
   *not* expanding scope to `rehearsal_dates` in this fix; that's a separate
   latent gap).

Design notes:

- The gate is **client-side** because the auto-block system already is (fetches
  user prefs, other bands, dispatches `createBlockOut` per pair). Moving the
  whole resync into an RPC is a bigger surgery that this bug does not require.
  If a future refactor consolidates the auto-block system into a
  `SECURITY DEFINER` RPC, that RPC can carry the same idempotence guarantee.
- The comparator is deliberately pure and side-effect-free so it's directly
  unit-testable without touching Supabase.
- Skipping the resync when nothing scheduling-related changed intentionally
  respects a manual delete by the other band's admin — if that admin cleared
  the actor's auto-block on `block_dates`, a non-scheduling edit will not
  resurrect it. That matches how the system already behaves for a user who
  joins a new band after the gig was created (their new band is not
  retroactively auto-blocked without an explicit re-save).

## Database Impact

**Not applicable.** No new migration, no schema change, no RLS change, no new
`SECURITY DEFINER` function, no trigger change. The existing
`blockout_created_notification` trigger continues to fire on genuine new
`block_dates` INSERTs — that behavior is correct and desired. This fix reduces
the number of spurious INSERTs upstream of the trigger.

## Flutter Architecture Changes

None. No new Riverpod providers, controllers, repositories, models, or
dependencies. The changes are:

- Two new private-ish pure helpers in `events_repository.dart`.
- One extra `select().single()` call inside `updateGig` and `updateRehearsal`
  each (pre-update snapshot).
- Two `if (schedulingChanged) { … }` wraps around already-existing resync
  blocks.

## Files to Create

1. `test/features/events/events_repository_scheduling_test.dart` — new focused
   unit-test file for the two pure comparators (~80–110 lines). No existing
   test file covers these; `test/features/events/models/event_form_data_test.dart`
   is a model-level file and is the wrong scope. Two `group()`s
   (`didGigSchedulingChange`, `didRehearsalSchedulingChange`), each with the
   cases listed under **Verification Plan** below.

## Files to Modify

1. `lib/features/events/events_repository.dart` —
   - Add top-level `@visibleForTesting bool didGigSchedulingChange(Gig, EventFormData)`
     and `@visibleForTesting bool didRehearsalSchedulingChange(Rehearsal, EventFormData)`
     (either just above the `EventsRepository` class or at the bottom of the
     file). Import `package:flutter/foundation.dart` if not already imported for
     `@visibleForTesting`.
   - In `updateGig` (~L785–L900): add a pre-update snapshot fetch using the
     existing `_gigSelectClause`, then wrap the existing `clearAutoBlocksForSource
     + autoBlockConflictingDates` block (~L849–L881) in `if
     (didGigSchedulingChange(preGig, formData)) { … }`. Leave the rest of the
     method untouched (the `.update()`, `_syncGigDates`, `_syncGigContacts`,
     `invalidateCache`, and final re-fetch all remain unconditional).
   - In `updateRehearsal` (~L361–L465): add a pre-update snapshot fetch of the
     row (only need `date` and `is_potential` — one lightweight
     `select('date, is_potential')`). Wrap the tail `try { clearAutoBlocks… +
     autoBlockConflicting… }` block (~L430–L462) in `if
     (didRehearsalSchedulingChange(preRehearsal, formData)) { … }`. Snapshot
     is taken *before* the `.update()` runs so it reflects the actual
     pre-edit state.
   - Do **not** touch `_updateAndGenerateRecurringSeries` — its resync is
     genuinely required (transitioning from non-recurring to recurring adds
     new dates).

2. `test/features/events/events_repository_scheduling_test.dart` — see Files
   to Create.

## Files Off-Limits

- **`lib/features/events/widgets/event_editor_drawer.dart`** — the local
  `_showBlockOutConflictDialog` is a per-editor "Availability Notice", not the
  band-wide push described in the bug. Its trigger cadence is a separate UX
  concern.
- **All Supabase migrations, RPCs, triggers, and Edge Functions** — the DB
  layer is behaving correctly (INSERT-only triggers, correct actor exclusion).
  Modifying any of these would be treating a symptom rather than the root
  cause.
- **`AutoConflictBlockingService`** — its `autoBlockConflictingDates` /
  `clearAutoBlocksForSource` API is correct; only the *conditions under which
  they're called* are wrong.
- **`BlockOutRepository.createBlockOut`** — inserting a genuinely new row and
  firing the notification is the desired behavior. The unique constraint
  already skips true duplicates; the bug isn't there.
- **Auth, routing, init-order, deep-link, and Firebase config** — untouched.
- **`_updateAndGenerateRecurringSeries`** — its tail resync is legitimate on
  every call (only called when the rehearsal is *becoming* recurring, which
  is always a schedule change).
- **`createGig` / `createRehearsal`** — creation-time notifications are the
  expected behavior and are explicitly in-scope of the bug's *expected*
  behavior.

## Change Budget

Engineer implementation should land within these bounds; QA compares actual
diff against these numbers.

| File                                                                                 | Expected net line delta |
| ------------------------------------------------------------------------------------ | ----------------------- |
| `lib/features/events/events_repository.dart`                                         | +55 to +75              |
| `test/features/events/events_repository_scheduling_test.dart`                        | +80 to +110 (new file)  |

- Expected new files: **1** (test file).
- Expected new public classes: **0**.
- Expected new public methods: **0** (two `@visibleForTesting` top-level
  functions are the only new symbols — deliberately not on the class).
- Expected new dependencies: **0**.

## System Impact Map

| System         | Status                                                                                                       |
| -------------- | ------------------------------------------------------------------------------------------------------------ |
| Gigs           | **Affected** — `updateGig` behavior changes on non-scheduling edits (fewer block_dates INSERTs, fewer pushes) |
| Rehearsals     | **Affected** — same behavior change in `updateRehearsal` standard-update path                                |
| Setlists       | Unaffected                                                                                                   |
| Members        | Unaffected                                                                                                   |
| Auth           | Unaffected                                                                                                   |
| Routing        | Unaffected                                                                                                   |
| Notifications  | **Affected downstream** — `blockout_created` push volume drops for non-scheduling edits; behavior unchanged for creates and for genuine scheduling changes |
| Platforms      | All (iOS, Android, macOS, Web) — client-side gate, no platform-conditional code touched                      |
| Init order     | Unaffected                                                                                                   |
| Supabase (DB)  | Unaffected (no migration, no trigger change, no RPC change)                                                  |
| Calendar feed  | Unaffected                                                                                                   |
| Financials     | Unaffected                                                                                                   |

## Regression Risk

**LOW.**

- Change is confined to two methods in one file, plus one new test file.
- No auth, routing, session, init-order, RLS, RPC, or trigger touched.
- The gated code path (resync) still runs unchanged whenever it *should* run
  (main date change, `is_potential` flip, additional-dates change for gigs).
- Worst-case if the comparator is wrong in the "changed → false negative"
  direction: a legitimate new conflict is missed until the next scheduling
  edit; the block_date stays stale for that user but manual block-outs work
  fine. No data corruption, no auth issue, no RLS bypass.
- Worst-case in the "unchanged → false positive" direction: the resync fires
  unnecessarily, which is exactly today's behavior — no regression.

## Engineer Task Breakdown

Implement in this order, one atomic commit per task if possible:

1. **Add the two pure comparators** as top-level `@visibleForTesting`
   functions at the top of `lib/features/events/events_repository.dart`
   (immediately after the imports, before `class NoBandSelectedError`). Both
   return `bool`. Normalize dates to `DateTime(y, m, d)` before compare. For
   gig additional dates, compare as `Set<DateTime>` on the normalized values.

2. **Gate `updateGig`** — right after the `if (bandId.isEmpty) throw …` guard
   and before building the `data` map, fetch the pre-update snapshot:

   ```dart
   final preUpdateResponse = await supabase
       .from('gigs')
       .select(_gigSelectClause)
       .eq('id', gigId)
       .eq('band_id', bandId)
       .single();
   final preGig = Gig.fromJson(preUpdateResponse);
   ```

   Then wrap the existing `try { await _autoConflictBlockingService.clearAutoBlocksForSource…
   … } catch (e) { debugPrint(…); }` block in
   `if (didGigSchedulingChange(preGig, formData)) { … }`. Leave the surrounding
   `.update()`, `_syncGigDates`, `_syncGigContacts`, `invalidateCache`, and
   final `select(_gigSelectClause)` calls untouched.

3. **Gate `updateRehearsal`** — same pattern in the standard-update path.
   Fetch a minimal pre-update snapshot (`select('id, band_id, date,
is_potential')`) before the update runs, hydrate a `Rehearsal` from it (or
   construct a light temp struct — either works, but `Rehearsal.fromJson`
   keeps the comparator signature clean), then wrap the tail resync
   `try { … } catch (e) { … }` block (~L430–L462) in
   `if (didRehearsalSchedulingChange(preRehearsal, formData)) { … }`. Do this
   *only* on the standard-update path; leave the `isBecomingRecurring` and
   `isStoppingRecurring` branches untouched (they either delegate to
   `_updateAndGenerateRecurringSeries` or fall through to the gated block
   naturally).

4. **Add the unit tests** in
   `test/features/events/events_repository_scheduling_test.dart` — one
   `group('didGigSchedulingChange')` with the cases in **Verification Plan**
   Tier 1 below, one `group('didRehearsalSchedulingChange')` similarly. No
   Supabase, no widget test, no golden — pure `test()` calls.

5. **Static analysis + tests** — Engineer runs `flutter analyze` and
   `flutter test test/features/events/events_repository_scheduling_test.dart`
   locally before opening PR. Both must pass.

## Verification Plan

### Tier 1 — Pre-deploy (QA gate)

Executable in the QA environment without a running app.

1. **`flutter analyze`** — must pass with zero new warnings introduced by
   this change. (Baseline is clean per `edit-gig-soundcheck-not-persisted`
   merge.)
2. **`flutter test test/features/events/events_repository_scheduling_test.dart`**
   — must pass. Required test cases:

   For `didGigSchedulingChange`:
   - Identical main date, identical `is_potential`, both additional-date sets
     empty → returns `false`.
   - Main date changes by one day → returns `true`.
   - `is_potential` flips true → false → returns `true`.
   - `is_potential` flips false → true → returns `true`.
   - Identical scheduling but time-of-day component differs on the `DateTime`
     inputs (e.g., one at 00:00, other at 12:00 on the same y/m/d) → returns
     `false` (proves normalization works).
   - Additional-dates set: `{Feb 10, Feb 12}` vs. `{Feb 10, Feb 12}` (same
     order) → `false`.
   - Additional-dates set: `{Feb 10, Feb 12}` vs. `{Feb 12, Feb 10}` (reordered
     but same set) → `false`.
   - Additional-dates set: `{Feb 10}` vs. `{Feb 10, Feb 12}` → `true`.
   - Additional-dates set: `{Feb 10, Feb 12}` vs. `{Feb 10, Feb 15}` → `true`.

   For `didRehearsalSchedulingChange`:
   - Identical main date, identical `is_potential` → `false`.
   - Main date differs → `true`.
   - `is_potential` flips → `true`.
   - Same y/m/d but different time-of-day component → `false` (normalization).

3. **Full `flutter test` run** — the change must not regress any existing test.
   Existing `test/features/events/widgets/event_dropdown_test.dart` uses a
   `_CapturingEventsRepository extends EventsRepository` spy; verify it still
   compiles and passes (the `updateGig`/`updateRehearsal` public signatures are
   unchanged, so this should be a no-op regression risk).

4. **Change-budget check** — QA compares actual diff line counts against the
   **Change Budget** table above. Flag Warning if net delta on
   `events_repository.dart` exceeds +75; flag Critical if it exceeds +120.

### Tier 2 — Post-deploy (owner-run manual punch list for Tony)

Cannot be automated in the QA pipeline (requires a running app + push
delivery). Hand this verbatim to Tony as a numbered punch list.

**Setup (once):**

- Two test accounts: **A** (editor) and **B** (member of a *different* band
  than the one A is editing in; both in A's One Calendar auto-block scope).
- A has One Calendar auto-blocking enabled and includes the target band.
- A has an existing confirmed gig in Band X on date D. Auto-block already
  exists on Band Y for user A on date D. B's device is signed in as a member
  of Band Y with push enabled.

**Punch list:**

1. Silence B's device notification center. Reset it clean.
2. From A's device, edit the gig — change *only* the venue name. Save.
3. **Expected:** B receives **no** new "Member Unavailable" push.
   **Fail:** B receives a new push.
4. From A's device, edit the gig again — change *only* the start time (still
   on date D). Save.
5. **Expected:** B receives no new push.
6. From A's device, edit the gig again — change the date from D to a new
   conflicting date D+7 (where B has no personal block-out). Save.
7. **Expected:** B receives one new push for D+7 ("A is unavailable on
   {D+7}"), and any auto-block on D is removed from B's band's block-out
   list.
8. Repeat steps 2–7 for a confirmed rehearsal in Band X (same B in Band Y).
9. Sanity check: create a *brand-new* confirmed gig in Band X on a fresh
   conflicting date. Expected: B receives one push (create-time notification —
   unchanged by this fix).

## QA Regression Areas

Focus static-analysis and headless-test attention on:

- `EventsRepository.updateGig`, `EventsRepository.updateRehearsal`, and their
  callers — most notably `event_editor_drawer.dart` and any Riverpod overrides
  in `event_dropdown_test.dart`.
- Any other spot that constructs an `EventsRepository` for testing (spy
  subclasses must still compile).
- The two new `@visibleForTesting` symbols — grep for accidental leaks into
  production code paths.

## Rollout Strategy

Standard single-PR merge to `main`. No feature flag, no phased rollout, no
migration. The behavior change is:

- **Before:** every gig/rehearsal edit fires push notifications for the actor's
  auto-blocks on every other band they belong to.
- **After:** the same push fires only when the gig/rehearsal's schedule
  actually changes (main date, `is_potential`, or additional-dates set for
  gigs). Creates are unaffected. Manual block-outs are unaffected.

No user-facing UI messaging change. No changelog entry beyond the standard bug
fix note.

## Out of Scope

- Fixing / re-cadencing the local `_showBlockOutConflictDialog` in the drawer
  — separate UX concern, not part of the reported push behavior.
- Expanding rehearsal auto-blocks to include `rehearsal_dates` (multi-date
  potentials). Current code auto-blocks only the main rehearsal date; that's
  an independent latent gap.
- Moving the auto-block resync into a `SECURITY DEFINER` RPC. Would be a
  larger architectural change and is not required to fix this bug.
- Adding a `gig_updated` / `rehearsal_updated` notification type (already
  defined as a category value in
  [notification_categories.sql](supabase/migrations/20260128205900_notification_categories.sql)
  but never fired). Out of scope; only reducing spurious `blockout_created`
  volume matters here.
- Auditing / adjusting the `notify_band_members` actor-exclusion logic — it is
  correct.
- Any change to Firebase, FCM, Edge Functions, or the push-delivery pipeline.
