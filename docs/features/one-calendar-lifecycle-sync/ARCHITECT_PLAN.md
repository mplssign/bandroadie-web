# ARCHITECT PLAN — One Calendar Lifecycle Sync

## Feature Slug

`bug/one-calendar-lifecycle-sync`

---

## Problem Summary

**What:** One Calendar auto-conflict-blocking only synchronizes correctly at the moment
a gig or rehearsal is first created. Three related gaps exist after that moment, and
Tony has bundled them into this single ticket rather than filing three:

1. **Tentative events wrongly auto-block.** `createGig()` and `createRehearsal()` call
   the auto-blocking service unconditionally — including for `is_potential = true`
   (tentative/"maybe") gigs and rehearsals. Tony's decision (confirmed): only
   **confirmed** events (`is_potential = false`) should create cross-band block-outs.
   Today, every tentative gig or rehearsal pollutes the user's other bands' calendars.

2. **Edits never resync.** `updateGig()` and `updateRehearsal()` never call the
   auto-blocking service at all. Consequences:
   - Rescheduling a confirmed event leaves the **old** block-out (wrong date) in other
     bands and never creates a **new** one for the new date.
   - Confirming a previously-tentative event (`is_potential: true → false`) never
     retroactively creates the cross-band block-out, because only the create path
     triggers blocking.
   - Un-confirming a previously-auto-blocked event (`is_potential: false → true`) leaves
     the stale block-out in place in other bands.

3. **Deletes never clean up.** `deleteGig()`, `deleteRehearsal()`, and
   `deleteRehearsalSeries()` never remove the block-outs they caused in other bands.
   Deleting/cancelling an event leaves permanent orphaned block-outs on every other band
   the user belongs to.

**Why this wasn't fixed already:** The `one-calendar-recurring-auto-block`
ARCHITECT_PLAN (2026-07-2x) explicitly identified gap #3 and scoped it out, recommending
exactly the fix implemented here:

> "Tracking which block-outs were auto-created by a specific recurring series requires
> either: a `source_event_id` column on `block_dates`... Consider future enhancement:
> add `source_event_type` and `source_event_id` columns to `block_dates` for cascade
> cleanup." — `docs/features/one-calendar-recurring-auto-block/ARCHITECT_PLAN.md`,
> "Out of Scope" §1.

This ticket implements that traceability change and uses it to close all three gaps.

---

## Root Cause

**Primary failure:** `block_dates` rows created by auto-blocking carry **no reference
back to the gig or rehearsal that caused them**. There is no way to find "which
block-out rows belong to event X" in order to update or remove them when X changes.
Compounding this, the auto-blocking service is wired into the **create** path only —
`updateGig`, `updateRehearsal`, `deleteGig`, `deleteRehearsal`, and
`deleteRehearsalSeries` never call it. There is also no `is_potential` gate anywhere in
the auto-blocking call chain.

**Evidence (confirmed by direct code read, this session):**

- `lib/features/calendar/auto_conflict_blocking_service.dart` — neither
  `autoBlockConflictingDate()` (dead code, zero callers) nor `autoBlockConflictingDates()`
  (the live method) accepts or checks `is_potential`.
- `lib/features/events/events_repository.dart` line 111 sets `'is_potential':
formData.isPotentialGig` on insert, but the auto-block trigger at lines 149–177 fires
  unconditionally regardless of that value (same pattern for gigs, lines 600 / 633–664).
- `updateRehearsal()` (line 343), `_updateAndGenerateRecurringSeries()` (line 437), and
  `updateGig()` (line 678) contain **zero** references to
  `_autoConflictBlockingService` anywhere in their bodies.
- `deleteRehearsal()` (line 919), `deleteRehearsalSeries()` (line 945), and `deleteGig()`
  (line 1087) each issue a plain `DELETE` against `rehearsals`/`gigs` with no companion
  cleanup of `block_dates`.
- Live production schema (`nekwjxvgbveheooyorjo`, verified via direct query this
  session): `block_dates` columns are `id, user_id, band_id, date, reason, created_at,
updated_at` — no source columns exist.
- Confirmed via `sql/diagnostics/` and `sql/fixes/` in the repo: Tony and a prior
  Engineer already had to hand-run one-off backfill/investigation scripts
  (`investigate_gig_backfill_gap.sql`, `backfill_tony_historical_blocks.sql`,
  `investigate_partial_block_anomaly.sql`) to patch missing propagation after the fact —
  direct evidence this class of bug has already caused real data drift in production.
- `lib/features/calendar/widgets/add_block_out_drawer.dart` is currently live, not dead:
  `BlockOutDrawer.show(...)` is called from
  `lib/features/calendar/calendar_screen.dart` (day-tap quick action, line 234) and
  `lib/features/calendar/calendar_tab_content.dart` (day-tap quick action, line 214).
  The prior dead-code citation from `one-calendar-manual-blackout` is historical/stale,
  not a current-code fact.

**Root Cause Confidence:** `HIGH` — confirmed by direct code observation and live
production schema/RLS inspection (not inferred).

---

## Reference Docs Consulted

- `docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md` — original feature design, `block_dates` unique constraint rationale
- `docs/features/one-calendar-auto-block-not-propagating/ARCHITECT_PLAN.md` — prior defaults bug, confirmed `is_potential` not checked anywhere at that time either
- `docs/features/one-calendar-recurring-auto-block/ARCHITECT_PLAN.md` — introduced `autoBlockConflictingDates()` (plural), and is the doc that explicitly deferred the traceability schema change to a future ticket (this ticket)
- `docs/features/one-calendar-manual-blackout/ARCHITECT_PLAN.md` — confirms manual block-outs must stay independent of any event-driven cleanup logic; documents the existing "delete old span → create new span" edit pattern this plan reuses
- `docs/agents/GUARDRAILS.md`, `docs/agents/ARCHITECT.md` — code change discipline, RLS safety rules, minimal-diff principle
- `docs/reference/architecture/database_schema.md` — `gigs`, `rehearsals`, `block_dates` column summaries
- `sql/diagnostics/investigate_gig_backfill_gap.sql`, `sql/diagnostics/investigate_partial_block_anomaly.sql`, `sql/fixes/backfill_tony_historical_blocks*.sql` — prior manual evidence of propagation drift (historical, already resolved by hand; informs but does not change this plan's scope)

**Code inspected in full:**

- `lib/features/events/events_repository.dart` (1110 lines — read in full)
- `lib/features/calendar/auto_conflict_blocking_service.dart` (235 lines — read in full)
- `lib/features/calendar/block_out_repository.dart` (311 lines — read in full)
- `lib/app/models/block_out.dart` (99 lines — read in full)

**Live database inspected (read-only, production project `nekwjxvgbveheooyorjo`):**

- `information_schema.columns` for `block_dates`
- `pg_policies` for `block_dates`, `gigs`, `rehearsals`

---

## Existing System Analysis

### Create path (works, minus the `is_potential` gate)

- `createRehearsal()`: generates all occurrence dates, inserts one `rehearsals` row per
  date (first becomes the series parent), then calls
  `_autoConflictBlockingService.autoBlockConflictingDates(eventDates: dates, ...)`
  **once**, unconditionally — no `is_potential` check.
- `createGig()`: inserts one `gigs` row (+ `gig_dates` rows for additional dates on
  multi-date potential gigs), then calls `autoBlockConflictingDates(eventDates: [main
date, ...additional dates], ...)` **once**, unconditionally — no `is_potential` check.
- `AutoConflictBlockingService.autoBlockConflictingDates()`: reads
  `user_calendar_preferences` once, resolves target bands once via
  `getBandIdsToApplyBlockOut()`, then nested-loops `eventDates × otherBandIds` calling
  `BlockOutRepository.createBlockOut()` per (date, band) pair. Each insert is wrapped in
  its own try-catch (duplicate-date unique-constraint violations are swallowed and
  logged — this is intentional, pre-existing, correct behavior that must not change).

### Update path (broken — no sync at all)

- `updateRehearsal()`: three branches (`isBecomingRecurring` →
  `_updateAndGenerateRecurringSeries()`; `isStoppingRecurring` → delete children then
  fall through; standard update). **None** of the three branches call the auto-blocking
  service. A confirmed rehearsal's date can be changed, or a tentative rehearsal can be
  confirmed, with zero effect on other bands' calendars.
- `updateGig()`: updates the `gigs` row, calls `_syncGigDates()` (adds/removes
  `gig_dates` rows for potential-gig additional dates), invalidates cache, returns. No
  auto-blocking call anywhere in the method.

### Delete path (broken — no cleanup at all)

- `deleteRehearsal()`: single `DELETE FROM rehearsals WHERE id = ... AND band_id = ...`.
- `deleteRehearsalSeries()`: two strategies (parent-child link, or legacy pattern
  matching) but both end in plain `DELETE FROM rehearsals` calls with no `block_dates`
  awareness.
- `deleteGig()`: single `DELETE FROM gigs WHERE id = ... AND band_id = ...`.

### `block_dates` schema and RLS (confirmed live, production)

Columns: `id, user_id, band_id, date, reason, created_at, updated_at` — no FK to any
event table.

RLS policies (verified via `pg_policies`, production):

- `block_dates_insert_own` (INSERT): `is_band_member(band_id) AND user_id = auth.uid()`
- `block_dates_select_members` (SELECT): `is_band_member(band_id)`
- `block_dates_update_own_or_admin` (UPDATE): `(user_id = auth.uid() AND
is_band_member(band_id)) OR is_band_admin(band_id)`
- `block_dates_delete_own_or_admin` (DELETE): `(user_id = auth.uid() AND
is_band_member(band_id)) OR is_band_admin(band_id))`

Cross-band writes by the propagating user already work today (this is how the feature
propagates at all) because the propagating user is, by definition, a member of every
target band returned by `getBandIdsToApplyBlockOut()`, and `user_id = auth.uid()` holds
for every row it creates. Deleting those same rows (by the same user, same bands) is
governed by an equally permissive policy. **No RLS policy change is required** for this
fix — new nullable columns do not interact with `is_band_member`/`user_id` predicates.

### Manual block-outs must stay untouched

Block-outs created via `event_editor_drawer.dart._saveBlockOut()` (the manual blockout
propagation flow fixed in `bug/one-calendar-manual-blackout`) are **not** tied to any
gig or rehearsal. Under this plan they will always have `source_gig_id = NULL` and
`source_rehearsal_id = NULL`. Any cleanup/resync logic added here must only ever target
rows where one of those columns is non-null — manual block-outs are structurally immune
by construction, not by an added `if` check.

`lib/features/calendar/widgets/add_block_out_drawer.dart` is also part of the current
manual block-out create path (via `BlockOutDrawer.show(...)` from
`calendar_screen.dart` line 234 and `calendar_tab_content.dart` line 214). This does
**not** change scope for this ticket: that drawer's writes also call
`BlockOutRepository.createBlockOut()` without `sourceGigId`/`sourceRehearsalId`, so its
rows remain `NULL, NULL` and are structurally unreachable by the new
event-source-based resync/cleanup logic, exactly like
`event_editor_drawer.dart._saveBlockOut()`.

---

## Proposed Solution

### 1. Schema: add source traceability to `block_dates`

Add two nullable, mutually-exclusive foreign key columns. `NULL, NULL` = manually
created (untouched, forever). Non-null in exactly one column = auto-created by that gig
or rehearsal.

```sql
ALTER TABLE public.block_dates
  ADD COLUMN source_gig_id UUID REFERENCES public.gigs(id) ON DELETE CASCADE,
  ADD COLUMN source_rehearsal_id UUID REFERENCES public.rehearsals(id) ON DELETE CASCADE;

ALTER TABLE public.block_dates
  ADD CONSTRAINT block_dates_single_source CHECK (
    NOT (source_gig_id IS NOT NULL AND source_rehearsal_id IS NOT NULL)
  );

CREATE INDEX idx_block_dates_source_gig_id
  ON public.block_dates (source_gig_id)
  WHERE source_gig_id IS NOT NULL;

CREATE INDEX idx_block_dates_source_rehearsal_id
  ON public.block_dates (source_rehearsal_id)
  WHERE source_rehearsal_id IS NOT NULL;
```

Existing rows are untouched (both columns default `NULL`). **No retroactive tagging of
pre-existing auto-created rows is attempted** — heuristic matching (reason text + date)
was already rejected as fragile in the `one-calendar-recurring-auto-block` plan, and
that reasoning still holds. This is an explicit Out of Scope item below.

**Per-occurrence granularity for recurring rehearsals is required, not optional.**
Each occurrence of a recurring rehearsal is its own row in `rehearsals` (with its own
`id`); the UI has a real, reachable "delete only this occurrence" action distinct from
"delete entire series" (`event_editor_drawer.dart` lines ~2020–2037). If all
block-outs from one `createRehearsal()` call were tagged with the series **parent's**
id, deleting a single occurrence would silently fail to clean up that occurrence's
cross-band block-out. Therefore: **every block-out row created for a rehearsal
occurrence must carry that specific occurrence's `rehearsals.id`**, not the parent's.
Gigs do not have this problem — a gig's additional dates live in a child `gig_dates`
table under one `gigs.id`, so `source_gig_id` is always the single gig id regardless of
how many dates it covers.

### 2. Gate auto-blocking on `is_potential`

At both call sites in `events_repository.dart` (`createRehearsal` line ~149,
`createGig` line ~633), wrap the existing auto-block trigger in
`if (!formData.isPotentialGig) { ... }`. Tentative events create rehearsal/gig rows as
today (unchanged) but no longer touch `block_dates` at all.

### 3. Resync on update (delete-then-recreate, reusing the existing pattern)

`one-calendar-manual-blackout`'s "Edit mode" analysis already established the accepted
pattern for this codebase: _delete the old span, create the new one_. Apply the same
pattern here, keyed by source id instead of by date span:

For every `updateGig()` / `updateRehearsal()` call, after the primary row update
succeeds:

1. Delete all `block_dates` rows whose `source_gig_id` (or `source_rehearsal_id`)
   matches this event — unconditionally, regardless of old/new `is_potential` value.
   This is cheap (indexed, typically 0–N rows) and idempotent.
2. If the event is now confirmed (`!formData.isPotentialGig`) **and** One Calendar /
   auto-block preferences are enabled (checked inside the existing service method, not
   duplicated here), recreate block-outs for the event's **current** date(s), tagged
   with the current source id(s).

This single delete-then-recreate step correctly and uniformly handles all four
transition cases without needing to compare old vs. new state in
`events_repository.dart`: confirmed→confirmed-with-new-date (stale removed, correct one
created), potential→confirmed (nothing to remove, new one created), confirmed→potential
(stale removed, nothing recreated), potential→potential (no-op both ways).

### 4. Deletes: FK cascade is the cleanup mechanism — must be verified, not assumed

`ON DELETE CASCADE` on both new FK columns means deleting a `gigs` or `rehearsals` row
automatically deletes every `block_dates` row that references it, with **zero
application code changes** required in `deleteGig()`, `deleteRehearsal()`, or
`deleteRehearsalSeries()` — cascade fires per-row regardless of which of the two delete
strategies in `deleteRehearsalSeries()` is used, since it operates on whatever specific
row id is actually deleted.

**This must not be assumed to work under RLS without verification.** Postgres's
interaction between row-level security and FK-triggered cascade deletes is a genuine
edge case, and this plan does not have a live test of it. **Task 1 in the Engineer
breakdown below is a mandatory Tier 2 test that proves the cascade fires under the
`authenticated` role before any Dart code is written.** If it does not fire as expected,
the Engineer must stop and escalate rather than silently proceeding — see the
contingency note in Task 1.

---

## Database Impact

| Component                    | Impact                                                                                                |
| ---------------------------- | ----------------------------------------------------------------------------------------------------- |
| `block_dates` table schema   | **Affected** — 2 new nullable columns, 1 CHECK constraint, 2 partial indexes                          |
| `gigs` / `rehearsals` schema | Unaffected (only referenced by the new FKs)                                                           |
| RLS policies                 | **Unaffected** — verified live; existing policies do not reference the new columns and do not need to |
| RPC functions                | Unaffected — no RPCs touch `block_dates`                                                              |
| Triggers                     | Unaffected — no existing triggers on `block_dates`; cascade is a native FK action, not a trigger      |
| Existing data                | Unaffected — new columns default `NULL` on all existing rows; no backfill/UPDATE performed            |

**Migration required:** Yes — one new migration file,
`supabase/migrations/<timestamp>_add_block_dates_source_traceability.sql`, timestamp
must sort after the current latest (`20260803153000_...`).

---

## Flutter Architecture Changes

| Component                                                                                   | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BlockOutRepository` (`lib/features/calendar/block_out_repository.dart`)                    | `createBlockOut()` gains 2 new optional params (`sourceGigId`, `sourceRehearsalId`), included in the insert payload when non-null. New method `deleteBlockOutsForSource({sourceGigId, sourceRehearsalId})` — deletes matching rows regardless of band, then clears the full cache (rows may span multiple bands' cache entries; blunt but correct — this repository already has no per-row cache invalidation finer than per-band).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `AutoConflictBlockingService` (`lib/features/calendar/auto_conflict_blocking_service.dart`) | `autoBlockConflictingDates()` gains 2 new optional params: `sourceGigId` (applies to every date — the gig case) and `sourceRehearsalIdsByDate` (a `List<String>?` parallel to `eventDates`, same length/order — the rehearsal case). New thin passthrough method `clearAutoBlocksForSource({sourceGigId, sourceRehearsalId}) => _blockOutRepository.deleteBlockOutsForSource(...)`. Existing singular `autoBlockConflictingDate()` (already dead code, zero callers) is left untouched — not in scope, do not remove it opportunistically.                                                                                                                                                                                                                                                                                                                                                                                                               |
| `EventsRepository` (`lib/features/events/events_repository.dart`)                           | `createRehearsal`: gate auto-block call on `!formData.isPotentialGig`; build a same-order `List<String>` of each inserted occurrence's id during the existing creation loop, pass as `sourceRehearsalIdsByDate`. `createGig`: gate on `!formData.isPotentialGig`; pass `sourceGigId: gigId`. `updateRehearsal` (standard branch): after update + `_syncRehearsalDates`, call `clearAutoBlocksForSource(sourceRehearsalId: rehearsalId)`, then if confirmed, re-trigger blocking for `[formData.date]` / `[rehearsalId]`. `_updateAndGenerateRecurringSeries`: same resync, extended to cover the parent id + every newly created child id. `updateGig`: after update + `_syncGigDates`, call `clearAutoBlocksForSource(sourceGigId: gigId)`, then if confirmed, re-trigger blocking for the current main + additional dates. `deleteGig`/`deleteRehearsal`/`deleteRehearsalSeries`: **no changes** — cleanup is via FK cascade (see Task 1 contingency). |

State management: no new providers, notifiers, or controllers. No Riverpod changes. No
widget/UI changes — this is entirely repository/service-layer.

---

## Files to Create

**None.** (The migration file is a database artifact tracked under Database Impact
above, not a Dart source file.)

---

## Files to Modify

| File                                                                | What changes                                                                                                                                                                                                                                                      |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<new>_add_block_dates_source_traceability.sql` | New migration: 2 columns, 1 CHECK constraint, 2 partial indexes on `block_dates`                                                                                                                                                                                  |
| `lib/features/calendar/block_out_repository.dart`                   | `createBlockOut()` — add 2 optional params, thread into insert payload. Add `deleteBlockOutsForSource()` method.                                                                                                                                                  |
| `lib/features/calendar/auto_conflict_blocking_service.dart`         | `autoBlockConflictingDates()` — add 2 optional params, thread into each `createBlockOut()` call. Add `clearAutoBlocksForSource()` passthrough method.                                                                                                             |
| `lib/features/events/events_repository.dart`                        | `createRehearsal` — gate + pass `sourceRehearsalIdsByDate`. `createGig` — gate + pass `sourceGigId`. `updateRehearsal` — add resync block. `_updateAndGenerateRecurringSeries` — add resync block covering parent + new children. `updateGig` — add resync block. |

---

## Files Off-Limits

| File                                                                       | Reason                                                                                                                                                                                                                                                                                                       |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/app/models/block_out.dart`                                            | UI never needs to read `source_gig_id`/`source_rehearsal_id` — no model change required. Do not add unused fields.                                                                                                                                                                                           |
| `lib/features/events/widgets/event_editor_drawer.dart`                     | Manual block-out propagation path (fixed under `bug/one-calendar-manual-blackout`) is correct and must stay independent of event-sourced cleanup logic. Do not touch.                                                                                                                                        |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`                  | Live code path (called from `lib/features/calendar/calendar_screen.dart` line 234 and `lib/features/calendar/calendar_tab_content.dart` line 214). Still off-limits for this ticket because it remains manual block-out flow with `NULL` source ids, structurally outside event-source resync/cleanup scope. |
| `lib/features/calendar/one_calendar_preferences_repository.dart`           | Preference read/resolution logic is correct and unrelated to this bug.                                                                                                                                                                                                                                       |
| `lib/main.dart`                                                            | Init order must not change (guardrail).                                                                                                                                                                                                                                                                      |
| Any other `supabase/migrations/*.sql`                                      | Only the one new migration file listed above is in scope.                                                                                                                                                                                                                                                    |
| `AutoConflictBlockingService.autoBlockConflictingDate()` (singular method) | Already dead code before this change. Do not remove or refactor it as part of this fix — out of scope, opportunistic cleanup is forbidden by guardrails.                                                                                                                                                     |

---

## System Impact Map

| System                                 | Impact                                                                                  |
| -------------------------------------- | --------------------------------------------------------------------------------------- |
| Gigs                                   | **Affected** — create/update/delete lifecycle now correctly syncs cross-band block-outs |
| Rehearsals                             | **Affected** — same, plus per-occurrence traceability for recurring series              |
| Setlists / Catalog                     | Unaffected                                                                              |
| Members / RBAC                         | Unaffected — no RLS policy changes                                                      |
| Auth / Session                         | Unaffected                                                                              |
| Routing                                | Unaffected                                                                              |
| Notifications                          | Unaffected — no notification triggers touch `block_dates`                               |
| Calendar / Block Dates                 | **Affected** — schema change, and the write/delete lifecycle for auto-created rows      |
| Platform (iOS / Android / Web / macOS) | Unaffected — pure Dart repository/service layer, identical across platforms             |

---

## Regression Risk

**Overall Risk:** `MEDIUM`

**Rationale:**

- Touches create, update, **and** delete lifecycle for both gigs and rehearsals — more
  surface area than any single prior One Calendar fix.
- Includes a schema change (additive, nullable, backward-compatible — low risk in
  isolation) combined with a genuinely uncertain runtime behavior (FK cascade under RLS)
  that must be verified before the fix can be considered complete.
- All new/changed blocking calls remain wrapped in the existing non-blocking try-catch
  pattern — a failure in auto-block resync cannot fail the primary gig/rehearsal
  save/delete, consistent with every prior One Calendar fix in this codebase.
- The `is_potential` gate is a pure behavior narrowing (fewer block-outs created, not
  more) — cannot introduce new cross-band write bugs, can only reduce noise.
- Manual block-outs are structurally unreachable by any of this logic (they never have a
  `source_gig_id`/`source_rehearsal_id` to match against).

**Specific regression scenarios:**

| Scenario                                                                                          | Risk                       | Mitigation                                                                                                                                     |
| ------------------------------------------------------------------------------------------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| FK cascade doesn't fire under RLS, orphaned rows persist after delete                             | MEDIUM                     | Task 1 mandatory Tier 2 test before any Dart code is written; documented contingency (explicit app-level cleanup) if it fails                  |
| Resync-on-update deletes a manual block-out by mistake                                            | LOW                        | Delete is always scoped by `source_gig_id`/`source_rehearsal_id` equality — manual rows have both `NULL` and can never match                   |
| Editing one occurrence in a recurring series accidentally resyncs the whole series                | LOW                        | Standard `updateRehearsal` branch only ever touches the single `rehearsalId` being edited; verified no series-wide query exists in that branch |
| Existing (pre-fix) orphaned block-outs remain forever                                             | Accepted, not a regression | Explicitly Out of Scope — no retroactive backfill attempted (see below)                                                                        |
| Tentative gigs/rehearsals created before this fix already have unwanted block-outs in other bands | Accepted, not a regression | Pre-existing state; not retroactively cleaned (Out of Scope)                                                                                   |

---

## Engineer Task Breakdown

Tasks must be completed in order. **Do not proceed past Task 1 until its verification
passes.**

### Task 1 — Migration + mandatory cascade verification (blocking gate)

1. Create `supabase/migrations/<timestamp>_add_block_dates_source_traceability.sql`
   with the DDL from "Proposed Solution §1" above.
2. Run `supabase db push` (or equivalent for the target environment).
3. Run Tier 1 and Tier 2 verification queries from the Verification Plan below,
   **including POST-DEPLOY TEST 3 (the cascade-fires-under-RLS test) — this is the
   critical gate.**
4. **Contingency:** If POST-DEPLOY TEST 3 fails (block_dates rows survive the
   parent delete), stop. Do not proceed to Task 2–7 as designed. Instead, add explicit
   `_blockOutRepository`-mediated cleanup calls inside `deleteGig()`,
   `deleteRehearsal()`, and `deleteRehearsalSeries()` (call
   `clearAutoBlocksForSource()` for the specific id(s) being deleted, before or after
   the primary delete, wrapped in non-blocking try-catch) and re-verify. Report this
   deviation explicitly in the ENGINEER_REPORT — do not silently patch and continue.

### Task 2 — `BlockOutRepository`: add source columns to create path + new delete method

**File:** `lib/features/calendar/block_out_repository.dart`

- Add `String? sourceGigId` and `String? sourceRehearsalId` params to `createBlockOut()`.
- Include `if (sourceGigId != null) 'source_gig_id': sourceGigId` and the rehearsal
  equivalent in both the single-day and multi-day-range insert payloads.
- Add:
  ```dart
  Future<void> deleteBlockOutsForSource({
    String? sourceGigId,
    String? sourceRehearsalId,
  }) async {
    assert(
      (sourceGigId == null) != (sourceRehearsalId == null),
      'Exactly one of sourceGigId or sourceRehearsalId must be provided',
    );
    if (sourceGigId != null) {
      await supabase.from('block_dates').delete().eq('source_gig_id', sourceGigId);
    } else {
      await supabase
          .from('block_dates')
          .delete()
          .eq('source_rehearsal_id', sourceRehearsalId!);
    }
    clearAllCache();
  }
  ```

### Task 3 — `AutoConflictBlockingService`: thread source ids, add clear method

**File:** `lib/features/calendar/auto_conflict_blocking_service.dart`

- `autoBlockConflictingDates()`: add `String? sourceGigId` and
  `List<String>? sourceRehearsalIdsByDate` params. Convert the outer
  `for (final eventDate in eventDates)` loop to an indexed loop (`for (var i = 0; i <
eventDates.length; i++)`) so the matching `sourceRehearsalIdsByDate?[i]` can be read.
  Pass `sourceGigId: sourceGigId, sourceRehearsalId: sourceRehearsalIdsByDate?[i]` into
  each `createBlockOut()` call. If `sourceRehearsalIdsByDate` is provided, assert its
  length equals `eventDates.length`.
- Add:
  ```dart
  Future<void> clearAutoBlocksForSource({
    String? sourceGigId,
    String? sourceRehearsalId,
  }) {
    return _blockOutRepository.deleteBlockOutsForSource(
      sourceGigId: sourceGigId,
      sourceRehearsalId: sourceRehearsalId,
    );
  }
  ```
- Do not modify the singular `autoBlockConflictingDate()` method — leave it as dead code.

### Task 4 — `EventsRepository.createRehearsal`: gate + tag

**File:** `lib/features/events/events_repository.dart`, `createRehearsal()` (~line 78)

- Inside the creation loop, collect `final createdRehearsalIds = <String>[];` — append
  each inserted row's id (parallel to `dates`, same order) as the loop already parses
  `response` into `Rehearsal.fromJson(response)` for the first iteration; for **every**
  iteration capture `response['id'] as String` into the list.
- Wrap the existing auto-block trigger block (`if (firstRehearsal != null) { ... }`) in
  an additional `&& !formData.isPotentialGig` condition (i.e.
  `if (firstRehearsal != null && !formData.isPotentialGig) { ... }`).
- Pass `sourceRehearsalIdsByDate: createdRehearsalIds` into the
  `autoBlockConflictingDates()` call.

### Task 5 — `EventsRepository.createGig`: gate + tag

**File:** `lib/features/events/events_repository.dart`, `createGig()` (~line 569)

- Wrap the existing auto-block trigger `try { ... }` block condition with
  `if (!formData.isPotentialGig) { ... }`.
- Pass `sourceGigId: gigId` into the `autoBlockConflictingDates()` call.

### Task 6 — `EventsRepository.updateRehearsal` + `_updateAndGenerateRecurringSeries`: resync

**File:** `lib/features/events/events_repository.dart`

- In the standard-update branch of `updateRehearsal()` (~line 382–416), after
  `await _syncRehearsalDates(rehearsalId, formData);` and before `invalidateCache`,
  add a non-blocking try-catch block: call
  `_autoConflictBlockingService.clearAutoBlocksForSource(sourceRehearsalId: rehearsalId)`,
  then if `!formData.isPotentialGig`, fetch band name (same pattern as `createRehearsal`)
  and call `autoBlockConflictingDates(eventDates: [formData.date],
sourceRehearsalIdsByDate: [rehearsalId], ...)`.
- In `_updateAndGenerateRecurringSeries()` (~line 437–513), after the parent update and
  all child inserts complete, apply the same resync pattern but covering **all** dates
  in the series: collect `[rehearsalId, ...newChildIds]` parallel to `dates`, call
  `clearAutoBlocksForSource(sourceRehearsalId: rehearsalId)` (clears only the parent's
  prior tag — children are brand new, nothing to clear for them), then if confirmed,
  call `autoBlockConflictingDates(eventDates: dates, sourceRehearsalIdsByDate: [...])`.
- Both call sites must be wrapped in try-catch that does not rethrow (matches the
  existing pattern in `createRehearsal`).

### Task 7 — `EventsRepository.updateGig`: resync

**File:** `lib/features/events/events_repository.dart`, `updateGig()` (~line 678–734)

- After `await _syncGigDates(gigId, formData);` and before the final gig fetch, add a
  non-blocking try-catch block: call
  `_autoConflictBlockingService.clearAutoBlocksForSource(sourceGigId: gigId)`, then if
  `!formData.isPotentialGig`, fetch band name, rebuild `allDates` (main date +
  `formData.additionalDates`, same construction as `createGig`), and call
  `autoBlockConflictingDates(eventDates: allDates, sourceGigId: gigId, ...)`.

### Task 8 — `flutter analyze`

Run `flutter analyze` and confirm 0 errors before reporting complete.

---

## Verification Plan

### Tier 1 — Pre-Deployment (before `supabase db push`)

```sql
-- PRE-DEPLOY TEST 1: Confirm block_dates has no source columns yet (baseline)
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'block_dates'
  AND column_name IN ('source_gig_id', 'source_rehearsal_id');
-- Expected: 0 rows (columns do not exist yet)

-- PRE-DEPLOY TEST 2: Confirm gigs and rehearsals PKs are UUID (FK target compatibility)
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name IN ('gigs', 'rehearsals') AND column_name = 'id';
-- Expected: both rows show data_type = 'uuid'

-- PRE-DEPLOY TEST 3: Confirm no existing objects named block_dates_single_source
SELECT conname FROM pg_constraint WHERE conname = 'block_dates_single_source';
-- Expected: 0 rows (safe to create)
```

### Tier 2 — Post-Deployment (after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1: Confirm columns, constraint, and indexes exist
SELECT column_name, is_nullable, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'block_dates'
  AND column_name IN ('source_gig_id', 'source_rehearsal_id');
-- Expected: 2 rows, both is_nullable = 'YES', data_type = 'uuid'

SELECT conname, contype FROM pg_constraint WHERE conname = 'block_dates_single_source';
-- Expected: 1 row, contype = 'c' (check)

SELECT indexname FROM pg_indexes
WHERE tablename = 'block_dates'
  AND indexname IN ('idx_block_dates_source_gig_id', 'idx_block_dates_source_rehearsal_id');
-- Expected: 2 rows

-- POST-DEPLOY TEST 2: CHECK constraint rejects dual-source rows (uses a throwaway gig/rehearsal
-- via a real test band the operator controls, or gen_random_uuid() FK-less test — since both
-- columns have real FK constraints, this test requires actual existing gig/rehearsal ids.
-- Run only if a disposable test gig + rehearsal id are available; otherwise skip and rely on
-- the CHECK constraint's presence (TEST 1) as sufficient proof of intent.
-- Example (adjust ids):
-- INSERT INTO block_dates (user_id, band_id, date, reason, source_gig_id, source_rehearsal_id)
-- VALUES (auth.uid(), '<band-id>', '2099-01-01', 'test', '<gig-id>', '<rehearsal-id>');
-- Expected: ERROR — violates check constraint "block_dates_single_source"

-- POST-DEPLOY TEST 3 (CRITICAL GATE): Confirm FK ON DELETE CASCADE fires under RLS
-- Must be run as an authenticated test user via the app or PostgREST with a real JWT —
-- NOT as the postgres/service_role user, which would bypass RLS and give a false pass.
--
-- Steps (manual, via app or direct authenticated PostgREST call):
--   1. As test user in Band A (member of Band A + Band B), create a confirmed rehearsal
--      in Band A for a disposable future date.
--   2. Confirm a block_dates row was created in Band B with source_rehearsal_id set:
SELECT id, band_id, date, source_rehearsal_id
FROM block_dates
WHERE source_rehearsal_id = '<test-rehearsal-id>';
-- Expected: 1 row (Band B)
--   3. As the same authenticated test user, delete the rehearsal in Band A via the app
--      (or `DELETE FROM rehearsals WHERE id = '<test-rehearsal-id>'` over an authenticated
--      PostgREST session — not service_role).
--   4. Re-run the SELECT above.
-- Expected: 0 rows (cascade fired). If 1 row remains, RLS blocked the cascade —
-- invoke the Task 1 contingency (explicit app-level cleanup) before proceeding further.

-- POST-DEPLOY TEST 4: Confirm manual block-outs are structurally unaffected
SELECT COUNT(*) FROM block_dates WHERE source_gig_id IS NULL AND source_rehearsal_id IS NULL;
-- Expected: equals the pre-migration total row count of block_dates (no existing rows altered)
```

### Tier 2 (continued) — Application-level checks (no device required)

```
-- POST-DEPLOY TEST 5: flutter analyze
-- Run: flutter analyze
-- Expected: 0 errors

-- POST-DEPLOY TEST 6: Code review — is_potential gate present at both create call sites
-- Check: events_repository.dart createRehearsal() auto-block trigger wrapped in
--        `if (firstRehearsal != null && !formData.isPotentialGig)`
-- Check: events_repository.dart createGig() auto-block trigger wrapped in
--        `if (!formData.isPotentialGig)`
-- Expected: both present

-- POST-DEPLOY TEST 7: Code review — resync present in both update methods
-- Check: updateRehearsal() standard branch calls clearAutoBlocksForSource then
--        conditionally autoBlockConflictingDates
-- Check: updateGig() calls clearAutoBlocksForSource then conditionally
--        autoBlockConflictingDates
-- Expected: both present, both wrapped in non-blocking try-catch

-- POST-DEPLOY TEST 8: SQL — confirm resync via direct RPC/PostgREST simulation
-- (no device needed — can be run via Supabase SQL editor as service_role for setup,
-- but the actual UPDATE must be simulated via authenticated session per POST-DEPLOY TEST 3
-- pattern, OR verified by code review per TEST 7 if an authenticated test session isn't
-- available in this environment.)
```

**Note on device access:** every test above is either a SQL query runnable from the
Supabase SQL editor / MCP, a `flutter analyze` invocation, or a code-review check against
the diff. POST-DEPLOY TEST 3 requires an _authenticated test user_ (which can be a
PostgREST call with a test JWT or the web build in a browser) but explicitly does not
require a physical iOS/Android device.

---

## QA Regression Areas

**Primary (new behavior):**

1. **Potential events do not auto-block** — create a tentative gig and a tentative
   rehearsal in Band A; confirm no block-out appears in Band B for either.
2. **Confirming a tentative event retroactively blocks** — create a tentative rehearsal,
   edit it to confirmed; confirm a block-out now appears in Band B.
3. **Un-confirming removes the block-out** — confirm a rehearsal (block-out created),
   edit it back to tentative; confirm the Band B block-out is removed.
4. **Rescheduling moves the block-out** — confirm a gig for date X (block-out created on
   X in Band B), edit its date to Y; confirm Band B shows the block-out on Y, not X.
5. **Deleting a confirmed gig removes its block-out** — confirm a gig, verify Band B
   block-out exists, delete the gig, verify Band B block-out is gone.
6. **Deleting one occurrence of a recurring rehearsal removes only that occurrence's
   block-out** — create a weekly recurring rehearsal (4 occurrences, confirmed), verify
   4 block-outs in Band B, delete only the 2nd occurrence via "delete this rehearsal
   only," verify exactly 3 block-outs remain in Band B (the 2nd occurrence's is gone,
   the other 3 are untouched).
7. **Deleting an entire recurring series removes all its block-outs** — same setup,
   delete via "delete entire series," verify 0 remaining block-outs in Band B tied to
   that series.

**Regression (existing behavior must not break):**

1. Confirmed one-off gig/rehearsal creation still auto-blocks correctly (no `is_potential`
   regression for the already-working confirmed case).
2. Manual block-out creation/propagation (`bug/one-calendar-manual-blackout` fix)
   unaffected — manual block-outs still propagate and are never touched by the new
   resync/cleanup logic.
3. Multi-date potential gig auto-blocking (`bug/one-calendar-recurring-auto-block` fix)
   still blocks all dates when the gig is confirmed.
4. One Calendar OFF / Selected-bands-only modes still gate propagation correctly
   (unchanged — gating logic inside `autoBlockConflictingDates` is not modified).
5. Duplicate-date unique-constraint handling (manual block-out already exists on a date
   the auto-blocker also wants) still fails gracefully per-row, as before.
6. Deleting a gig/rehearsal that never had auto-blocking enabled (no source-tagged
   `block_dates` rows exist) completes with no errors — cascade/cleanup on zero matching
   rows must be a no-op, not an exception.

**Known limitations (accepted, not regressions):**

1. Pre-existing orphaned/incorrectly-tagged block-outs created before this fix are not
   retroactively cleaned up or tagged.
2. Editing a recurring series' **pattern** (e.g., changing which days of the week it
   recurs on for an already-existing series) is a pre-existing, separate gap not
   addressed by `_updateAndGenerateRecurringSeries` today and is out of scope here.

---

## Rollout / Migration Strategy

1. Apply the migration (`supabase db push`) to staging first if available; run the full
   Tier 2 verification suite there, including the critical cascade test (POST-DEPLOY
   TEST 3).
2. Only after staging verification passes, apply to production.
3. Deploy the Dart code changes (standard `flutter build` / `deploy_web.sh` /
   app-store submission per platform — no special sequencing relative to the migration,
   since the new columns are purely additive and the old code path does not reference
   them).
4. No user communication required — this is a bug fix restoring intended behavior, not
   a new user-facing feature.
5. **Rollback:** if the cascade test fails in production and the contingency
   (application-level cleanup) cannot be implemented same-day, the migration can be left
   in place (additive, harmless if unused) while only the Dart changes are reverted —
   this avoids a second migration/rollback cycle. If the schema itself must be rolled
   back:
   ```sql
   ALTER TABLE public.block_dates DROP CONSTRAINT IF EXISTS block_dates_single_source;
   DROP INDEX IF EXISTS idx_block_dates_source_gig_id;
   DROP INDEX IF EXISTS idx_block_dates_source_rehearsal_id;
   ALTER TABLE public.block_dates DROP COLUMN IF EXISTS source_gig_id;
   ALTER TABLE public.block_dates DROP COLUMN IF EXISTS source_rehearsal_id;
   ```

---

## Out of Scope

1. **Retroactive tagging/backfill of pre-existing auto-created `block_dates` rows.**
   Already-existing rows stay `NULL, NULL` (indistinguishable from manual) forever.
   Heuristic matching was already rejected as fragile in the prior
   `one-calendar-recurring-auto-block` plan; that reasoning is unchanged.
2. **Retroactive cleanup of already-orphaned block-outs from events deleted before this
   fix shipped.** Same rationale as #1 — no reliable way to attribute them after the
   fact. If Tony wants this, it is a separate one-off manual SQL exercise (precedent:
   `sql/fixes/backfill_tony_historical_blocks.sql`), not a code change.
3. **Recurring series pattern edits** (changing days-of-week/frequency on an existing
   series after creation) — `_updateAndGenerateRecurringSeries` only handles the
   non-recurring→recurring transition today; pattern changes on an already-recurring
   series are a separate, pre-existing gap.
4. **Performance optimization of the resync delete-then-recreate pattern** — an update
   always issues a DELETE then re-INSERTs, even when nothing relevant changed (e.g.
   editing only the location field on a confirmed rehearsal still clears and recreates
   its block-outs). This mirrors the accepted pattern from
   `one-calendar-manual-blackout` and is not optimized further here; event edits are
   infrequent, and the operation is wrapped non-blocking.
5. **The dead `autoBlockConflictingDate()` (singular) method** — not removed, not
   refactored. Confirmed pre-existing dead code, unrelated cleanup, forbidden by
   guardrails' "no opportunistic refactors" rule.
6. **Duplicate manual block-out implementations** —
   `lib/features/calendar/widgets/add_block_out_drawer.dart` and
   `event_editor_drawer.dart._saveBlockOut()` are now two independent implementations
   of manual block-out create/delete + One Calendar propagation. This architectural
   duplication is real but is a separate future cleanup ticket, not part of this
   lifecycle-sync fix.

---

**END OF ARCHITECT_PLAN.md**
