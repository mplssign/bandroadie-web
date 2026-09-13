# ENGINEER_REPORT — demo-session-no-relaunch-resume

## Feature Slug

`feature/demo-session-no-relaunch-resume`

## Feature Title

Demo/anonymous sessions should not survive an app relaunch

## Cycle Number

1

## Goal

Ensure a restored **anonymous** demo session never auto-resumes into the Demo
Band on cold start. On native relaunch, purge a restored anonymous session with a
bounded **local** sign-out **before** `runApp()`, so every existing auth path
sees `currentSession == null` and routes to `LoginScreen`. Real-user
(non-anonymous) session persistence and the live in-run demo flow are preserved
exactly. No database/TTL/cron/edge-function change (all #289 surfaces off-limits).

## Architect Tasks Completed

1. **`DemoSessionService` predicate** — added the pure static
   `shouldPurgeRestoredAnonymousSession({hasSession, isAnonymous}) => hasSession
   && isAnonymous` next to `shouldReleaseDemoOnLifecycle`, with the doc comment
   stating restored-anonymous-only intent. No existing method touched.
2. **`main.dart` cold-start purge** — added
   `import 'features/auth/demo_session_service.dart';` and the guarded purge block
   immediately after the `Supabase.initialize()` try/catch (`FormatException`
   retry) and before the Firebase init block (init step 6.5). Reads
   `currentSession`, gates on the predicate, and performs a bounded (~2 s
   `.timeout`) local sign-out inside try/catch.
3. **Predicate unit test** — added a new
   `group('shouldPurgeRestoredAnonymousSession', ...)` with the full truth table
   in `test/features/auth/demo_lifecycle_predicate_test.dart`.
4. **Logged the init-order decision** — appended `DECISION-006` to
   `docs/reference/general/AI_DECISIONS.md` (Feature slug, Status Active,
   init-order step 6.5, local-sign-out-only choice, login-guaranteed failure
   behavior, one-line rollback).
5. **Updated RUNTIME_CONFIG** — inserted step `6.5 Purge restored anonymous demo
   session (local sign-out) ← native-only effect` between steps 6 and 7 in
   `docs/reference/general/RUNTIME_CONFIG.md`.

## Files Created

None.

## Files Modified

| File | Change |
| --- | --- |
| [lib/main.dart](../../../lib/main.dart) | Added the demo-session-service import + the guarded cold-start purge block (init step 6.5). Net +24 lines. |
| [lib/features/auth/demo_session_service.dart](../../../lib/features/auth/demo_session_service.dart) | Added the pure static `shouldPurgeRestoredAnonymousSession` predicate + doc comment. Net +12 lines. No existing method altered. |
| [test/features/auth/demo_lifecycle_predicate_test.dart](../../../test/features/auth/demo_lifecycle_predicate_test.dart) | Added the `shouldPurgeRestoredAnonymousSession` truth-table group. Net +43 lines. |
| [docs/reference/general/AI_DECISIONS.md](../../../docs/reference/general/AI_DECISIONS.md) | Appended `DECISION-006`. Net +87 lines. |
| [docs/reference/general/RUNTIME_CONFIG.md](../../../docs/reference/general/RUNTIME_CONFIG.md) | Inserted init step 6.5. Net +1 line. |

`git diff --stat main`: 5 files changed, 167 insertions(+), 0 deletions. `test/`
changes are limited to the one predicate test file (confirmed via `git diff
--stat main -- test/`).

## Analyzer Results

`flutter analyze lib/main.dart lib/features/auth/demo_session_service.dart
test/features/auth/demo_lifecycle_predicate_test.dart` → **No issues found!**
(clean at every severity). `dart fix --dry-run` → **Nothing to fix!** for the
plan-listed files. `dart format` applied to the three changed Dart files (no
formatting changes required).

## Test Results

- `flutter test test/features/auth/demo_lifecycle_predicate_test.dart
  test/features/auth/auth_gate_anonymous_recovery_test.dart` → **All 12 tests
  passed** (4 new `shouldPurgeRestoredAnonymousSession` cases + existing
  lifecycle-predicate cases + the unchanged anonymous-recovery reconcile backstop
  Tests A–E).
- `flutter test` (full suite) → **All 292 tests passed.** No new failures. The
  `login_screen_demo_button_test.dart` suite (noted as previously flaky in prior
  reports) **passed** in this run — there are no pre-existing failures to report,
  and this branch introduces zero changes under `test/` outside the predicate
  test.

## Code Efficiency / Bloat Check

- **Reuse search performed.** Searched `lib/` for an existing cold-start / restored-
  anonymous purge helper before adding the predicate. Closest existing seam is the
  sibling `DemoSessionService.shouldReleaseDemoOnLifecycle` (different semantics:
  lifecycle-`detached` slot *release*, not cold-start *purge*); the `isAnonymous`
  checks in `auth_gate.dart` (lines 106/151/205/250/315/649) and `app_shell.dart`
  (line 310) are inline runtime routing/exit checks, not a reusable pure predicate.
  **No existing helper for cold-start restored-anonymous purge** — the new
  predicate is justified and mirrors the established #289 testable-seam pattern.
- No `_buildX()`/private `_Foo` widgets, no new provider/notifier, no
  `Future`/`StreamBuilder`, no hand-rolled match/dedupe loops, no new model field
  or `copyWith` entry, no barrel file, no "for future use" flags/enums added.
- The `try/catch` in `main.dart` **swallows and continues** (does not log-and-
  rethrow) — intentional and required: startup must reach `runApp()` even if the
  bounded sign-out throws/times out (worst case = pre-fix behavior, backstopped by
  #289 TTL). This mirrors the existing `FormatException` "sign out and continue"
  pattern already at the same point in `main.dart`.
- Comments state *why* (offline/login guarantee, bounded startup), not *what*; no
  `TODO`/`FIXME` left. The single `debugPrint` in the catch matches the existing
  `main.dart` startup-error logging convention (`debugPrint` is permitted;
  `avoid_print` targets `print`).
- **Zero deleted lines** is expected here: this is a net-additive *feature* (a new
  cold-start guard inserted into an existing flow), not a bug fix layered on top of
  a defect — there is no pre-existing defective line to remove. The only in-place
  simplification is noted under Deviations below.
- **File sizes:** `lib/main.dart` = 348 lines (< 500 target);
  `lib/features/auth/demo_session_service.dart` = 107 lines (< 500 target). No
  target exceeded; no justification required.

## Verification (manual steps performed)

- Confirmed the purge block sits **between** the `Supabase.initialize()` block and
  the `// Initialize Firebase` block (init-order step 6.5), and that
  `isAuthenticated == session != null` in `auth_state_provider.dart` is **not**
  touched (grep confirmed no edit there).
- Confirmed the gotrue 2.27.2 `signOut` signature is
  `Future<void> signOut({SignOutScope scope = SignOutScope.local})` — the default
  scope is already `SignOutScope.local`, and its `_signOut` removes the in-memory
  session and awaits persisted-storage removal before the ignorable network
  `admin.signOut`, guaranteeing `currentSession == null` even offline.
- Confirmed all changes are confined to the 5 plan-listed files; the only untracked
  path outside them is `docs/features/demo-session-no-relaunch-resume/` (this
  report + the plan).
- Ran `dart fix --dry-run` (read-only, whole package) — no suggestions for the
  plan-listed files.

## Deviations From Plan

**One deviation, behavior-preserving.** The plan's literal code (Task 2 / Files-to-
Modify) specifies `signOut(scope: SignOutScope.local)`. This project explicitly
enables `avoid_redundant_argument_values` in `analysis_options.yaml` (listed under
its "AI-slop lints"), and gotrue 2.27.2's `signOut` default scope is already
`SignOutScope.local`, so the explicit argument is flagged as a redundant value
(info severity). Because the engineer gate requires scoped `flutter analyze` to
come back empty **at every severity**, I dropped the explicit argument and call
`signOut()` (which resolves to the identical `SignOutScope.local` default). This is
byte-for-byte the same **bounded local sign-out** the plan intends — the `.timeout`
bounding and the local-only scope are both preserved — and it satisfies the
project's own lint policy and the analyze-clean gate. A one-line comment documents
that this is gotrue's default local scope. No other deviation; the `SignOutScope`
import remains available via the existing unprefixed `supabase_flutter` import (now
unused-as-explicit-symbol but still exported by that import, so no unused-import
lint).

## Blockers Encountered

None.

## Ready For QA

**Yes.**
