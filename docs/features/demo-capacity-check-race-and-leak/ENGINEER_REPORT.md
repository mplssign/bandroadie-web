# Engineer Report

## Feature Slug
`bug/demo-capacity-check-race-and-leak`

## Feature Title
Demo session cap (30 concurrent) has no atomic enforcement, and abandoned sessions occupy slots for up to ~20 minutes

## Cycle Number
2

## Cycle 2 Reconciliation (2026-09-12)
QA Cycle 1 returned **REQUIRES CHANGES** on a **single** Critical `[database-safety]` item and
found **no implementation defect** (Dart analyzer clean, predicate test 3/3, SQL byte-diff
confirmed correct, scope/off-limits/diff-safety/budget all PASS). The blocker was purely
that the original Verification Plan made the isolated-DB migration apply-check (Tier 1 #4) and
grant assertions (Tier 1 #5) a **mandatory QA gate**, while no agent-runnable isolated Supabase
environment exists here (`docker`/`colima`/`podman` all absent → no local Supabase stack; the
only Supabase CLI link is to a **remote** project, which is off-limits).

The Architect has now **amended the Verification Plan only** (see its "Cycle 2 amendment"
block): the QA gate is explicitly the **static + headless** scope (analyzer, predicate test,
static SQL review/byte-diff, scope review), and the clean-apply, grant, concurrency, reclaim,
idempotency, and live-app A/B/C checks are reclassified as an **owner-run pre-apply Manual
Verification Punch List** for Tony. **Implementation scope is UNCHANGED.**

This cycle therefore makes **zero source/migration/test changes** — the working tree is
byte-for-byte identical to Cycle 1 (`git diff --numstat`: `auth_gate.dart` +9,
`demo_session_service.dart` +22, `AI_DECISIONS.md` +81; the migration and test remain the same
untracked files). Only this report is updated: Cycle Number → 2, verification boundary revised
to match the amended plan, focused analyzer/test/static checks re-run to re-confirm the static +
headless QA gate, and Ready For QA re-affirmed on that scope.

## Goal
Close two independent defects in the anonymous demo-session path:
1. **Race** — `provision_demo_session()`'s count-then-insert admission window is not
   serialized, so concurrent first-time visitors can provision more than 30 live sessions.
2. **Abandoned-slot leak** — a closed/killed app releases its slot only via TTL + cron
   (up to ~20 min), because teardown runs only on the explicit "Exit Demo" tap.

Fix per the Architect plan: a transaction-scoped advisory lock for atomic admission, a
best-effort `detached` client teardown for anonymous sessions, and faster reclaim via a
fixed **8-minute** TTL paired with a **2-minute** cron sweep.

## Architect Tasks Completed
1. ✅ New layered migration re-declares `provision_demo_session()` verbatim + one
   `PERFORM pg_advisory_xact_lock(8675309001)` placed immediately after the idempotency
   early-return and before the ceiling `SELECT count(*)`; REVOKE-from-PUBLIC/anon +
   GRANT-to-authenticated re-issued.
2. ✅ Same migration: `expires_at` default → `now() + interval '8 minutes'`;
   `heartbeat_demo_session()` re-declared with `interval '8 minutes'` renewal + re-issued
   REVOKE/GRANT; both `8 minutes` values carry the fixed-8-min-TTL comment.
3. ✅ Same migration: cron reschedule `*/5` → `*/2` via guarded unschedule-then-schedule
   with the existing loud post-assertion.
4. ✅ `DemoSessionService.releaseSlotOnDetach()` (static, ref-free, fire-and-forget invoke of
   `exit-demo-session`, all errors swallowed) and pure predicate
   `shouldReleaseDemoOnLifecycle(state, {required isAnonymous})` returning `true` only for
   `detached && isAnonymous`.
5. ✅ `auth_gate.dart` `didChangeAppLifecycleState`: added the doubly-gated
   (`detached` + `isAnonymous`) unawaited `releaseSlotOnDetach()` call before
   `_previousLifecycleState = state;`; the existing `resumed` branch is untouched.
6. ✅ Appended `[DECISION-005]` to `AI_DECISIONS.md` recording the advisory-lock choice,
   rejected alternatives, and Tony's decided 8-minute TTL / 2-minute cron rationale.
7. ✅ Added `test/features/auth/demo_lifecycle_predicate_test.dart` per the Verification Plan.

## Files Created
- `supabase/migrations/20260912130000_demo_session_capacity_hardening.sql` — timestamp
  strictly greater than `20260912122827`; the layered migration (advisory lock + 8-min TTL +
  8-min heartbeat renewal + `*/2` cron).
- `test/features/auth/demo_lifecycle_predicate_test.dart` — unit tests for
  `shouldReleaseDemoOnLifecycle`.

## Files Modified
- `lib/features/auth/demo_session_service.dart` — added `releaseSlotOnDetach()` and
  `shouldReleaseDemoOnLifecycle(...)`; added `import 'package:flutter/widgets.dart' show
  AppLifecycleState;`. No change to `provisionAndEnter` / `exit` / `heartbeat`.
- `lib/features/auth/auth_gate.dart` — added the `detached`-gated best-effort teardown branch
  in `didChangeAppLifecycleState`. No change to init order, splash, or the resumed-refresh path.
- `docs/reference/general/AI_DECISIONS.md` — one appended DECISION-005 entry (documentation only).

## Analyzer Results
`flutter analyze lib/features/auth/demo_session_service.dart lib/features/auth/auth_gate.dart
test/features/auth/demo_lifecycle_predicate_test.dart` → **No issues found!** (clean at every
severity; re-run this cycle in ~2.6s). `dart fix --dry-run` (whole-package read-only preview) →
**Nothing to fix!**

## Test Results
`flutter test test/features/auth/demo_lifecycle_predicate_test.dart` → **All 3 tests passed**
(re-run this cycle):
- `(detached, isAnonymous: true)` → true.
- `(detached, isAnonymous: false)` → false.
- every non-detached state (`resumed`, `inactive`, `hidden`, `paused`) with
  `isAnonymous: true` → false.

## Static SQL Review (Tier 1, item 3)
Confirmed in `20260912130000_demo_session_capacity_hardening.sql`:
- (a) `PERFORM pg_advisory_xact_lock(8675309001)` present (line 105), after the idempotency
  `IF FOUND ... RETURN ... END IF` and before `SELECT count(*) INTO v_live_count`.
- (b) `REVOKE ALL ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated` present for
  both `provision_demo_session()` and `heartbeat_demo_session()`.
- (c) `expires_at` default and heartbeat renewal both read `interval '8 minutes'` (two
  occurrences, lines 472 & 487).
- (d) cron reschedule to `'*/2 * * * *'` present with guarded unschedule and the loud
  post-assertion (`... is not in cron.job`).
- (e) both re-declared functions retain `SECURITY DEFINER` + `SET search_path = public`.

## Code Efficiency / Bloat Check
- **Reuse search performed:** `grep -rniE "releaseSlot|onDetach|shouldRelease|AppLifecycleState.detached" lib/`
  (excluding the two touched files) → none found — no existing helper for detached demo
  release, so the two new methods are genuinely new surface, not duplicates.
- **No AI-shaped bloat introduced:** no `_buildX()`/single-use `_Foo` widget, no new
  provider/notifier/controller/repository (plan explicitly requires none), no
  Future/StreamBuilder, no hand-rolled first-match/dedupe loop, no unused model field/param/
  `copyWith` entry, no barrel file, no future-use flags/enum cases, no restating comments, no
  `TODO`/`FIXME`/`debugPrint` added.
- **`try/catch` justification:** `releaseSlotOnDetach()`'s catch intentionally swallows all
  errors — it is fire-and-forget best-effort during app termination, and the DB cron sweep is
  the guaranteed backstop; it does not log-and-rethrow.
- **Zero-deleted-lines bug fix (guardrail note):** this fix is intentionally additive. Both
  defects are *missing* behavior, not defective existing behavior: defect 1 is a missing
  serialization point (a lock added between an otherwise-correct count and insert), and defect
  2 is a missing lifecycle handler plus faster reclaim. The migration re-declares
  `provision_demo_session()`/`heartbeat_demo_session()` verbatim via `CREATE OR REPLACE`
  (plpgsql has no in-place line insert), which git shows as a new file (all additions) but
  functionally replaces the prior bodies. No wrong existing code was left in place beneath a
  patch.
- **File-size targets:**
  - `demo_session_service.dart` = 95 lines, `demo_lifecycle_predicate_test.dart` = 52 lines —
    both well under target.
  - `auth_gate.dart` = 751 lines, over the 500-line Dart target. **Justification:** pre-existing
    size; this cycle added only a 9-line doubly-gated branch to a plan-listed file. Splitting
    the file is out of scope (the plan lists it as *modify*, adds no structural change, and
    forbids refactoring beyond the task).
  - Migration = 522 lines. **Justification:** the meaningful change is ~6 lines (advisory-lock
    line + comment, `expires_at` ALTER, heartbeat interval, cron reschedule); the remaining
    ~510 lines are a *mandatory verbatim* re-declaration of the current `provision_demo_session()`
    body (plpgsql has no in-place line insert), per the plan's Change Budget. Migration files
    are not Dart source and are not governed by the Dart line target.

## Verification (manual steps performed)
- Static: `flutter analyze` (scoped) clean this cycle; `dart fix --dry-run` nothing to fix;
  `dart format` unchanged (files already formatted; no source touched this cycle).
- Dart test: predicate test (3/3 passing this cycle) — the core headless proof of the
  `detached`-gating logic.
- Static SQL review of the migration re-run this cycle (all five invariants confirmed via
  targeted grep: advisory lock at line 105; `interval '8 minutes'` in both the `expires_at`
  default and heartbeat renewal; cron `'*/2 * * * *'`; `SECURITY DEFINER` +
  `SET search_path = public`; `REVOKE ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO
  authenticated` for both re-declared functions).
- Diff scope: `git diff --numstat` + `git status --short` confirm changes are byte-for-byte
  identical to Cycle 1 and confined to the plan-listed files (2 created, 3 modified) plus the
  expected untracked `docs/features/demo-capacity-check-race-and-leak/`.

## Deviations From Plan
None. **Cycle 2 makes no source/migration/test change** — the amended plan changed only the
Verification Plan's QA-gate/owner-run boundary, not the implementation scope, so reconciling the
existing (already-correct) implementation against it required no code edits. The Cycle 1
implementation details still hold: timestamp `20260912130000` (strictly greater than
`20260912122827`, same day); and the narrow `import 'package:flutter/widgets.dart' show
AppLifecycleState;` added to the service (because `package:flutter/foundation.dart` does not
export `AppLifecycleState`) — an in-file implementation detail, not a design deviation.

## Blockers Encountered
None blocking delivery, and **no unmet QA obligation** this cycle. Per the amended Verification
Plan, the DB and live-app checks below are **owner-run pre-apply checks for Tony**, not a QA
gate — the QA gate is the static + headless scope only. Confirmed again this cycle: no
agent-runnable isolated Supabase environment exists (`docker`/`colima`/`podman` all **NOT
FOUND** → no local Supabase stack can start; the only Supabase CLI link is to a **remote**
project). The following must be run by Tony on an environment he controls (local Docker Supabase
stack or a staging/branch project he owns) **before the migration is applied to prod**, and must
**never** be run against production or the remotely linked project:
- **Owner-run #1 — clean migration apply.** `supabase db reset` on a fresh local stack; then
  `SELECT 1 FROM cron.job WHERE jobname = 'cleanup_demo_sessions';` (expect exactly one row).
- **Owner-run #2 — grant assertions.**
  `has_function_privilege('anon', 'public.provision_demo_session()'::regprocedure, 'EXECUTE')` = `false`;
  `has_function_privilege('authenticated', ...)` = `true`; same for `heartbeat_demo_session()`.
- **Owner-run #3 — concurrency admission.** Seed 29 live rows + 10 (then 40) parallel
  spoofed-anon `provision_demo_session()` calls → live count settles at exactly **30** (never
  31+); the excess raise `demo_capacity_exceeded`.
- **Owner-run #4 — reclaim.** Fresh provision `expires_at ≈ now()+8min`; `heartbeat_demo_session()`
  renews to `now()+8min`; `cleanup_expired_demo_sessions()` deletes an already-expired row.
- **Owner-run #5 — idempotency.** Double-provision under the same spoofed anon uid → identical
  `clone_band_ids`; band count for that session stays at **2** (no second clone pair).
- **Owner-run A/B/C — live app.** (A) macOS `Cmd-Q` without Exit Demo → row gone ~10s.
  (B) iOS/Android force-swipe-kill → row gone by ~10 min (TTL 8 + cron ≤2). (C) background
  <8 min, return → demo still alive (no false teardown).

I did **not** run any application build/deploy/publish command, did **not** apply any migration,
and did **not** touch production or the remotely linked Supabase project. No source/migration/
test file was changed this cycle. `pipeline.lock` was left untouched (Manager holds it for this
run).

## Ready For QA
**Yes** — on the amended QA gate scope (static + headless), which is re-confirmed this cycle:
- `flutter analyze` on the three diff files → clean at every severity.
- `flutter test` predicate test → 3/3 passing.
- Static SQL review / byte-diff invariants confirmed (advisory lock at line 105 — after the
  idempotency early-return, before `SELECT count(*)`; `interval '8 minutes'` in both the
  `expires_at` default and heartbeat renewal; cron `'*/2 * * * *'`; `SECURITY DEFINER` +
  `SET search_path = public` and `REVOKE ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO
  authenticated` re-issued for both re-declared functions).
- Diff confined to the plan-listed files (3 modified: `auth_gate.dart`, `demo_session_service.dart`,
  `AI_DECISIONS.md`; 2 created: the migration and the predicate test).

The clean-apply, grant, concurrency, reclaim, idempotency, and live-app A/B/C checks are handed
to Tony as the **owner-run pre-apply Manual Verification Punch List** above (per the amended
plan) — structurally outside the agent-runnable surface, never to be run against production or
the remotely linked project.
