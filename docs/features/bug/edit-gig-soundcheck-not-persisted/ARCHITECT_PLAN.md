# ARCHITECT_PLAN — bug/edit-gig-soundcheck-not-persisted

## Feature Slug

`bug/edit-gig-soundcheck-not-persisted`

## Feature Title

Soundcheck time in gig editor never marks form dirty and isn't persisted

## Problem Summary

In the gig editor, every soundcheck interaction (set / adjust hour / adjust
minutes / toggle AM/PM / clear) leaves the edit form's `_isDirty` flag false, so
Update stays disabled. Independently, even if the dirty flag were fixed the
value would still be lost on save: there is no `gigs.soundcheck_time` column, no
`soundcheckTime` field on the `Gig` model, no soundcheck fields on
`EventFormData`, and the create/update payloads in `EventsRepository` never
write a `soundcheck_time` key. A fully-wired `GigFormFields.buildSoundcheckRow`
already exists but is never called; the drawer instead renders an ad-hoc
duplicate soundcheck UI that only mutates local `_soundcheck*` state variables
labelled _"UI-only, not persisted."_

## Root Cause

Confidence: **HIGH** (every claim below verified in code).

The soundcheck feature was left half-scaffolded on both sides of the boundary at
the same time:

- **UI side.** `event_editor_drawer.dart` declares
  `_soundcheckHour / _soundcheckMinutes / _soundcheckIsPM` with an explicit
  `"UI-only, not persisted"` comment (drawer L134–L137), then renders an inline
  ad-hoc soundcheck block inside `_buildScheduleSection` (L3043–L3082) plus a
  private `_buildSoundcheckTimePicker` helper (L3173–L3225). Every one of the
  ~9 `setState(...)` calls across those two blocks omits `_markDirty()`, unlike
  the analogous load-in-time handlers immediately above them (`onLoadInTimeSet`,
  `onLoadInTimeCleared`, `onLoadInHourChanged`, `onLoadInMinutesChanged`,
  `onLoadInAmPmChanged` at L2555–L2593, each of which calls `_markDirty()`).
- **Data side.** `GigFormFields` already exposes the _correct_ soundcheck
  surface: three nullable state props (`soundcheckHour / Minutes / IsPM`), five
  optional callbacks (`onSoundcheck{TimeSet, TimeCleared, HourChanged,
MinutesChanged, AmPmChanged}`), and a public
  `buildSoundcheckRow(BuildContext)` widget that mirrors
  `buildLoadInTimeSelector` line-for-line. But the drawer's
  `_createGigFormFields()` call site (L2472–L2620) passes none of them, so
  `buildSoundcheckRow` is never invoked. The drawer's ad-hoc UI runs in its
  place.
- **Persistence side.** `EventFormData` has no soundcheck fields, so even if the
  drawer wired `_soundcheck*` into `_buildFormData()`, `EventsRepository`'s
  `createGig` (repository L698–L744) and `updateGig` (L787–L823) payloads have
  no `soundcheck_time` key, and `gigs` has no column to receive it.

Together, this means soundcheck is invisible to every layer below the UI, and
even at the UI layer it can't enable Update.

## Existing System Analysis

Load-in time is the mirror: it went through the same shape a year ago (migration
`085_add_load_in_time_to_gigs.sql`, `Gig.loadInTime`, `EventFormData.loadIn*`
fields + `loadInTimeDisplay` getter + `fromGig` parsing block, drawer
`_loadInHour/_loadInMinutes/_loadInIsPM` state + `_markDirty()` on every
handler, `EventsRepository` payloads with `'load_in_time':
formData.loadInTimeDisplay`, `GigFormFields.buildLoadInTimeSelector`). The
soundcheck path already has the widget-level scaffolding
(`GigFormFields.buildSoundcheckRow` + 3 props + 5 nullable callbacks) but no
model / repo / migration / drawer wiring. Every add in this plan is a literal
mirror of an existing load-in line at a known location.

## Proposed Solution

Bring soundcheck to feature parity with load-in end-to-end and delete the
half-scaffolded UI-only duplicate. Five layers, each a direct mirror:

1. **Migration.** Add `gigs.soundcheck_time` as a nullable `TEXT` column
   holding a `H:MM AM/PM` string, exactly mirroring
   `085_add_load_in_time_to_gigs.sql`. No RLS change (the existing gig RLS
   applies to the new column automatically), no trigger change, no RPC change.
2. **`Gig` model.** Add `soundcheckTime` as `final String?` next to
   `loadInTime`; thread it through the constructor, `fromJson`, and `toJson`.
3. **`EventFormData` model.** Add `soundcheckHour / soundcheckMinutes /
soundcheckIsPM` fields alongside their `loadIn*` counterparts, add a
   `soundcheckTimeDisplay` getter that mirrors `loadInTimeDisplay`, and extend
   `EventFormData.fromGig` to parse `gig.soundcheckTime` the same way
   `gig.loadInTime` is parsed. Deliberately do **not** touch `copyWith` for
   soundcheck — `loadIn*` fields are not in `copyWith` either, and the drawer
   goes through `_buildFormData()` not `copyWith` for these values; adding
   soundcheck to `copyWith` while leaving load-in out would break the mirror.
4. **`EventsRepository`.** Add `'soundcheck_time': formData.soundcheckTimeDisplay,`
   next to `'load_in_time': formData.loadInTimeDisplay,` in _both_ the
   `createGig` payload (~L704) and the `updateGig` payload (~L814).
5. **`event_editor_drawer.dart`.**
   - `_buildFormData()`: pass `soundcheckHour`, `soundcheckMinutes`,
     `soundcheckIsPM` into the `EventFormData(...)` constructor, mirroring the
     `loadInHour / loadInMinutes / loadInIsPM` block already there.
   - Edit-mode `initState` populate block (~L275–L282): populate
     `_soundcheckHour / _soundcheckMinutes / _soundcheckIsPM` from the incoming
     `EventFormData`, mirroring the exact load-in `if (data.loadInHour != null
&& ...)` block right above it.
   - `_createGigFormFields()` call site (~L2545–L2593): pass all 8 soundcheck
     args — 3 state pass-throughs (`soundcheckHour`, `soundcheckMinutes`,
     `soundcheckIsPM`) + 5 callbacks
     (`onSoundcheckTimeSet`, `onSoundcheckTimeCleared`, `onSoundcheckHourChanged`,
     `onSoundcheckMinutesChanged`, `onSoundcheckAmPmChanged`), each doing
     `setState(...)` + `_markDirty()` exactly like the `onLoadIn*` callbacks
     directly below them. `onSoundcheckTimeSet` seeds `6:00 PM` to match the
     existing `_soundcheckHour = 6; _soundcheckMinutes = 0; _soundcheckIsPM = false`
     initial values in the ad-hoc block being removed (kept intentionally as a
     harmless UX preference: users overwhelmingly want a PM soundcheck; changing
     to load-in's "subtract 2h from start" heuristic would be a behavior change
     out of scope for this bug fix).
   - `_buildScheduleSection` (~L3043–L3082): delete the entire inline
     ad-hoc soundcheck block (the `Text('Soundcheck')` label,
     `AnimatedSize`, `EventAddValueButton`, and inline Row-with-Clear-button),
     replace with a single call `gigFormFields!.buildSoundcheckRow(context)` —
     same call pattern as `buildLoadInTimeSelector(context)` directly above it.
     Keep a `const SizedBox(height: 16)` separator between the two selectors.
   - Delete the private `_buildSoundcheckTimePicker` method (L3173–L3225) —
     dead once the ad-hoc block is gone. `GigFormFields.buildSoundcheckRow`
     renders the equivalent picker internally.

Explicitly out of scope (called out per guardrail; see **Out of Scope** below).

## Database Impact

One new migration file:

- **Filename:** `supabase/migrations/20260918120000_add_soundcheck_time_to_gigs.sql`
  (Engineer may adjust the HHMMSS suffix to a valid timestamp between the last
  merged migration `20260915130000` and `date -u +%Y%m%d%H%M%S` at
  implementation time; the yyyymmdd prefix must be today or later.)
- **Contents:** Mirror `085_add_load_in_time_to_gigs.sql` — one `ALTER TABLE
gigs ADD COLUMN soundcheck_time TEXT;` plus a matching `COMMENT ON COLUMN`.
  Nullable, no default; existing rows correctly remain NULL.

**RLS:** No policy change. `gigs` already has row-level policies keyed on
band membership; those apply column-agnostically to the new column. **No new
`SECURITY DEFINER` function is introduced**, so the RLS-recursion / `PUBLIC`-grant
guardrails don't apply here — nothing to `has_function_privilege` against.

**Triggers / RPCs:** Not touched. Notification triggers on `gigs` fire on row
insert/update; adding a nullable column with default NULL does not change any
trigger condition. No RPC references `load_in_time` in a way that requires
mirroring for `soundcheck_time` (the three demo-session RPCs that thread
`load_in_time` through are explicitly out of scope; see below).

## Flutter Architecture Changes

No new Riverpod providers, controllers, repositories, or patterns. All changes
are additions to existing models / methods / state, or deletions of dead UI
code. No new dependencies.

## Files to Create

1. `supabase/migrations/20260918120000_add_soundcheck_time_to_gigs.sql`
   (~12 lines; direct mirror of `085_add_load_in_time_to_gigs.sql`).

## Files to Modify

1. `lib/app/models/gig.dart` — add `soundcheckTime` field alongside `loadInTime`
   in the class body (~L29), constructor (~L74), `fromJson` (~L100), and
   `toJson` (~L126).
2. `lib/features/events/models/event_form_data.dart` — add
   `soundcheckHour / soundcheckMinutes / soundcheckIsPM` fields (~L271–L273),
   const constructor params (~L333–L335), a `soundcheckTimeDisplay` getter
   (mirror `loadInTimeDisplay` at ~L381–L388), and parsing + population in the
   `EventFormData.fromGig` factory (mirror the load-in block at ~L567–L589).
   Deliberately **not** touching `copyWith` (mirror decision — see Proposed
   Solution §3).
3. `lib/features/events/events_repository.dart` — add
   `'soundcheck_time': formData.soundcheckTimeDisplay,` next to the existing
   `'load_in_time': ...` line in _both_ `createGig` (~L704) and `updateGig`
   (~L814) payloads.
4. `lib/features/events/widgets/event_editor_drawer.dart` — five sub-edits
   listed in Proposed Solution §5.

## Files Off-Limits

- `supabase/migrations/20260904120003_provision_demo_session_rpc.sql`,
  `supabase/migrations/20260912122827_demo_relative_date_offsets.sql`,
  `supabase/migrations/20260912130000_demo_session_capacity_hardening.sql` —
  demo-session RPCs that thread `load_in_time` through for demo gig seeding.
  Explicitly excluded per Feature Input step 6; demo gigs don't need soundcheck
  data. Modifying these would require changing three signed RPCs for zero
  functional benefit to the bug being fixed.
- `supabase/functions/calendar-feed/index.ts` — ICS calendar feed reads and
  emits `load_in_time`. Adding soundcheck emission is a separate calendar-feed
  feature, not part of "editor persists soundcheck." Out of scope.
- `lib/features/gigs/widgets/view_gig_drawer.dart` — read-only gig view drawer
  displays `loadInTime`. Adding a soundcheck display row is a separate
  view-drawer feature, not part of "editor persists soundcheck." Out of scope.
- All authentication, routing, init-order, and Supabase-config files — untouched.
- All Riverpod providers, controllers outside the drawer — untouched.

## Change Budget

Engineer implementation should land within these bounds; QA compares actual
diff to these numbers.

| File                                                                 | Expected net line delta                                                                                                                                              |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260918120000_add_soundcheck_time_to_gigs.sql` | +12 (new file)                                                                                                                                                       |
| `lib/app/models/gig.dart`                                            | +4                                                                                                                                                                   |
| `lib/features/events/models/event_form_data.dart`                    | +~25 (3 fields + 3 ctor params + ~10-line getter + ~9-line factory block)                                                                                            |
| `lib/features/events/events_repository.dart`                         | +2 (one line in `createGig`, one in `updateGig`)                                                                                                                     |
| `lib/features/events/widgets/event_editor_drawer.dart`               | net **-40 to -50** (adds ~50 lines wiring 8 args; deletes the ~40-line inline block in `_buildScheduleSection` and the ~55-line `_buildSoundcheckTimePicker` helper) |
| **Total across repo**                                                | **~ -0 to -10** (adds and deletes roughly cancel)                                                                                                                    |

- **Expected new files:** 1 (the migration).
- **Expected new public classes / methods:** 0.
- **Expected new dependencies:** 0.
- **Expected new tests:** 2 (both added into existing test files — no new test
  files; see Verification Plan).

## System Impact Map

- **Gigs — AFFECTED.** New nullable column, new model field, new form field,
  new editor wiring, new repo payload key.
- **Rehearsals — unaffected.** Soundcheck is gig-only (mirror of load-in,
  which is also gig-only).
- **Setlists — unaffected.**
- **Members — unaffected.**
- **Auth — unaffected.**
- **Routing — unaffected.**
- **Notifications — unaffected.** Notification triggers on `gigs` don't inspect
  `load_in_time`; adding a nullable-with-null-default sibling column doesn't
  change any trigger firing condition.
- **Platforms — unaffected.** Pure Dart + SQL. No platform-conditional code,
  no `--dart-define` change, no init-order change, no iOS/macOS/Android/web
  divergence introduced.
- **Init order — unaffected.** Untouched.

## Regression Risk

**LOW.** Auth / session / routing / init order / RLS / RPCs / triggers / demo
data / notifications / calendar feed / cross-platform code paths are all
untouched. Every added line either mirrors an existing load-in line (with the
name changed) or lives entirely inside the gig editor's local widget state.
The largest single risk — a schema change — is a nullable-with-null-default
column, which is null-safe against every existing read path.

## Engineer Task Breakdown

Atomic, ordered. Each step is small enough to review independently.

1. **Create migration.** `supabase/migrations/20260918120000_add_soundcheck_time_to_gigs.sql`.
   Mirror `085_add_load_in_time_to_gigs.sql` verbatim: file header comment,
   `ALTER TABLE gigs ADD COLUMN soundcheck_time TEXT;`, matching `COMMENT ON
COLUMN`. Adjust the HHMMSS suffix if needed so the filename sorts after
   `20260915130000_add_locale_to_bands.sql`.
2. **Extend `Gig` model.** Add `final String? soundcheckTime;` next to
   `loadInTime`. Add `this.soundcheckTime,` to the const constructor next to
   `this.loadInTime,`. In `fromJson`, add `soundcheckTime: json['soundcheck_time']
as String?,` next to the `loadInTime:` line. In `toJson`, add
   `'soundcheck_time': soundcheckTime,` next to the `'load_in_time':` line.
3. **Extend `EventFormData` model.**
   - Add `final int? soundcheckHour; final int? soundcheckMinutes; final bool?
soundcheckIsPM;` in the same neighborhood as `loadInHour/Minutes/IsPM`.
   - Add `this.soundcheckHour, this.soundcheckMinutes, this.soundcheckIsPM,`
     to the const constructor next to the `loadIn*` params.
   - Add a `String? get soundcheckTimeDisplay` getter mirroring
     `loadInTimeDisplay` line-for-line.
   - In `EventFormData.fromGig`, add a `soundcheckHour / Minutes / IsPM` parse
     block mirroring the existing `if (gig.loadInTime != null) { … }` block,
     and pass the three parsed values into the returned `EventFormData(...)`
     next to `loadInHour: loadInHour, loadInMinutes: loadInMinutes,
loadInIsPM: loadInIsPM,`.
   - Do **not** modify `copyWith`.
4. **Extend `EventsRepository` payloads.** In `createGig` (~L704), add
   `'soundcheck_time': formData.soundcheckTimeDisplay,` on the line immediately
   following the existing `'load_in_time':` entry. In `updateGig` (~L814),
   same edit in the same relative position.
5. **Wire soundcheck into `event_editor_drawer.dart` — `_buildFormData()`.**
   Add `soundcheckHour: _soundcheckHour, soundcheckMinutes: _soundcheckMinutes,
soundcheckIsPM: _soundcheckIsPM,` to the returned `EventFormData(...)` in
   the same block as the existing `loadInHour: _loadInHour, …` lines.
6. **Wire soundcheck into `event_editor_drawer.dart` — edit-mode `initState`
   population (~L275–L282).** Immediately after the load-in populate block, add
   an identically-shaped block for `_soundcheckHour / _soundcheckMinutes /
_soundcheckIsPM` reading `data.soundcheckHour / soundcheckMinutes /
soundcheckIsPM`.
7. **Wire soundcheck into `event_editor_drawer.dart` —
   `_createGigFormFields()` call site (~L2545–L2593).** After the existing
   `loadInHour / loadInMinutes / loadInIsPM` + `onLoadInTimeSet / onLoadInTimeCleared
/ onLoadInHourChanged / onLoadInMinutesChanged / onLoadInAmPmChanged` args,
   add the 8 soundcheck args:
   - `soundcheckHour: _soundcheckHour,`
   - `soundcheckMinutes: _soundcheckMinutes,`
   - `soundcheckIsPM: _soundcheckIsPM,`
   - `onSoundcheckTimeSet: () { setState(() { _soundcheckHour = 6;
_soundcheckMinutes = 0; _soundcheckIsPM = false; }); _markDirty(); },`
     (seeds 6:00 PM — matches the pre-existing initial values of the ad-hoc
     block being deleted).
   - `onSoundcheckTimeCleared: () { setState(() { _soundcheckHour = null;
_soundcheckMinutes = null; _soundcheckIsPM = null; }); _markDirty(); },`
   - `onSoundcheckHourChanged: (v) { setState(() => _soundcheckHour = v);
_markDirty(); },`
   - `onSoundcheckMinutesChanged: (v) { setState(() => _soundcheckMinutes = v);
_markDirty(); },`
   - `onSoundcheckAmPmChanged: (isPM) { setState(() => _soundcheckIsPM = isPM);
  _markDirty(); HapticFeedback.selectionClick(); },`
     Match `onLoadIn*` styling and `HapticFeedback.selectionClick()` placement
     exactly.
8. **Replace inline soundcheck block in `_buildScheduleSection` (~L3043–L3082).**
   Delete the `Text('Soundcheck', …)`, `SizedBox(height: 8)`, `AnimatedSize`,
   `EventAddValueButton`, and inline `Row` (with `_buildSoundcheckTimePicker`
   and Clear `TextButton`). Replace with a single line:
   `gigFormFields!.buildSoundcheckRow(context),` — placed after
   `gigFormFields!.buildLoadInTimeSelector(context)` and a `const SizedBox(height: 16),`
   separator, matching the existing separator style.
9. **Delete `_buildSoundcheckTimePicker` method (L3173–L3225).** Dead code once
   step 8 lands. `GigFormFields.buildSoundcheckRow` renders the equivalent picker
   internally. Also remove any now-unused import if applicable (verify with
   `flutter analyze` in step 10 QA — unlikely, as `EventDropdown`,
   `AmPmToggleButton`, `EventAddValueButton`, and `Spacing` are all used
   elsewhere in the file).
10. **Add unit test coverage.** Two small additions, no new test files:
    - In an existing `event_form_data`-adjacent test group (or the closest
      existing one — Engineer picks the smallest file that thematically owns it;
      if none exists, put it in `test/features/events/models/event_form_data_test.dart`
      and only create the file if no reasonable existing home is available):
      one test case that constructs an `EventFormData` with soundcheck fields
      set and asserts `soundcheckTimeDisplay` returns the expected
      `"H:MM AM/PM"` string; one case with any of the three fields null
      asserting the getter returns null.
    - In an existing `Gig` model / json test group: one case asserting
      `Gig.fromJson(...).toJson()` round-trip preserves `soundcheck_time`
      (both a non-null "7:00 PM" value and a null value).

## Verification Plan

### Tier 1 — Pre-Deploy (QA gate; mechanically executable without a running app)

QA runs these and blocks merge on any failure:

1. `flutter analyze` reports no new warnings or errors introduced by the diff.
2. `flutter test` passes, including the two new unit tests added in Engineer
   step 10.
3. **New unit test — `EventFormData.soundcheckTimeDisplay`.** Verifies
   `H:MM AM/PM` formatting when all three fields set (e.g., hour=7, minutes=30,
   isPM=true → `"7:30 PM"`), and null when any field is null. This test never
   invokes any DB code — pure model logic.
4. **New unit test — `Gig` JSON round-trip.** Given a JSON map with
   `soundcheck_time: "6:00 PM"`, `Gig.fromJson(...).toJson()` emits
   `soundcheck_time: "6:00 PM"`. Same test with `soundcheck_time: null`.
   Never invokes any DB code.
5. **Static SQL review of the new migration** (QA reads the file):
   - Filename sorts after `20260915130000_add_locale_to_bands.sql`.
   - Single `ALTER TABLE gigs ADD COLUMN soundcheck_time TEXT;` statement.
   - Column is nullable; no `DEFAULT` clause (null default preserves existing
     rows).
   - No RLS policy change, no trigger definition, no RPC change, no `GRANT` /
     `REVOKE`.
   - Matching `COMMENT ON COLUMN` present.
6. **Ephemeral-DB apply-check.** Apply the new migration against a fresh
   ephemeral Postgres (the standard QA harness for this repo); confirm
   `\d public.gigs` shows `soundcheck_time text` nullable, and re-running
   the migration on already-applied state errors expectedly (idempotency is
   provided by the migration harness, not the SQL — this matches
   `085_add_load_in_time_to_gigs.sql`'s pattern).
7. **Diff size check against Change Budget.** Actual net line delta per file
   within ±20% of the Change Budget table above; new-file count exactly 1;
   new-public-class / new-dependency counts exactly 0.

### Tier 2 — Owner-Run PR-Test Punch List (Tony runs; QA hands this list to Tony verbatim)

QA cannot launch the app in this pipeline, so these UI-behavior checks are not
QA gates — they are Tony's PR-test checklist. Each step is precise and each has
an explicit expected result. Every step is required.

1. In the current active band, tap an existing confirmed gig, then tap Edit in
   the drawer. **Expected:** Editor drawer opens with soundcheck row showing
   `+ Set Soundcheck Time (Optional)` (identical shape to the Load-in Time row
   above it).
2. Tap `+ Set Soundcheck Time (Optional)`. **Expected:** Row expands to a
   picker showing `6 : 00 PM` (default), and the Update button becomes
   enabled.
3. Change hour dropdown from `6` to `7`. **Expected:** Update stays enabled.
4. Change minutes dropdown from `00` to `30`. **Expected:** Update stays
   enabled.
5. Tap the `AM` toggle. **Expected:** Toggle switches to AM, Update stays
   enabled.
6. Tap the `PM` toggle. **Expected:** Toggle switches back to PM, Update
   stays enabled.
7. Tap Update. Wait for save spinner to clear. Close the drawer.
   **Expected:** Save succeeds without error; snackbar (if any) matches the
   normal confirmed-gig-save snackbar shown for load-in-only edits.
8. Reopen the same gig, tap Edit. **Expected:** Soundcheck row shows `7 : 30 PM`
   (the value set in steps 3–4 with PM toggled back in step 6). Update
   button starts disabled (unchanged form).
9. Tap Clear on the soundcheck row. **Expected:** Row collapses back to
   `+ Set Soundcheck Time (Optional)`, Update becomes enabled.
10. Tap Update, wait for save, close, reopen for edit. **Expected:** Soundcheck
    row shows `+ Set Soundcheck Time (Optional)` (persisted-null state).
11. Repeat steps 1–10 substituting Load-in Time for Soundcheck. **Expected:**
    Load-in behavior is byte-for-byte unchanged from before this PR.
12. Open the read-only gig view drawer (not the editor) for a gig with a
    soundcheck value saved. **Expected:** Soundcheck value does _not_ appear
    in the view drawer — this is expected behavior; the view drawer is
    explicitly out of scope for this fix. Flag as a follow-up if visible.
13. Export the calendar feed (ICS) for a band with a gig that has a soundcheck
    value saved. **Expected:** Soundcheck value does _not_ appear in the ICS
    description — this is expected behavior; the calendar feed is explicitly
    out of scope for this fix. Flag as a follow-up if visible.
14. Repeat step 1–10 on the second target platform (iOS if step 1 was Android,
    or vice versa). **Expected:** Identical behavior on both platforms.
15. **DB spot-check** (Tony via psql or Supabase Studio, post-migration
    apply): `select id, name, load_in_time, soundcheck_time from gigs where
id = '<the gig from step 7>';` — should show the soundcheck value written
    in step 7 and cleared in step 10.

## QA Regression Areas

Static-analysis and unit-test surface QA must verify unchanged:

- `flutter analyze` reports zero new warnings.
- Existing `gig_form_fields_test.dart` cases (particularly the one at
  L95–L100 that passes `loadInHour: null, onLoadInTimeSet: () {}` etc.)
  continue to pass — soundcheck params were already declared optional /
  nullable on `GigFormFields`, so this test already omits them and remains
  valid.
- No other test file references soundcheck (grep across `test/` returned
  zero matches at diagnosis time) — no test needs to be updated by QA.
- Migration apply-check does not affect any other table or policy.

## Rollout Strategy

Single PR. Standard branch → PR → CI → merge → Supabase migration apply.

- Migration applies before app deploy (standard order; the new column is
  nullable, so an old app deploy reading a row with the new column simply
  ignores it, and a new app deploy hitting a pre-migration DB attempting to
  write `soundcheck_time` would fail on the missing column — the standard
  migration-first order avoids this).
- No feature flag needed. The soundcheck row already exists in the UI; this
  PR simply makes it work correctly.
- No user data migration needed. All existing gigs receive NULL for
  `soundcheck_time`, which is the intended "not set" state.
- No rollback complication: dropping the column is safe if needed (nothing
  references it outside this PR's diff).

## Out of Scope

- **Read-only gig view drawer (`lib/features/gigs/widgets/view_gig_drawer.dart`).**
  Currently displays `loadInTime` at L593–L596 but nothing for soundcheck.
  Adding a soundcheck display row is a separate feature.
- **Calendar feed ICS export (`supabase/functions/calendar-feed/index.ts`).**
  Currently reads and emits `load_in_time` in the ICS description. Adding
  soundcheck emission is a separate feature.
- **Demo-session RPCs** (`20260904120003_provision_demo_session_rpc.sql`,
  `20260912122827_demo_relative_date_offsets.sql`,
  `20260912130000_demo_session_capacity_hardening.sql`). These thread
  `load_in_time` through for demo gig seeding; explicitly excluded per Feature
  Input step 6. Demo gigs will show empty soundcheck values, which is fine.
- **`EventFormData.copyWith` soundcheck support.** `copyWith` does not
  currently handle `loadInHour / loadInMinutes / loadInIsPM` either.
  Deliberately mirrored; a separate refactor could add both together later.
- **Load-in-time behavior.** Not changed by this PR. QA punch-list step 11
  exists to confirm no unintended regression.
- **Any RLS, auth, routing, init-order, or platform-conditional change.**
