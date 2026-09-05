# QA Report — Demo Exit/Re-Entry Stuck Spinner

**Feature Slug:** `bug/demo-exit-reentry-stuck-spinner`
**Feature Title:** Re-entering the demo after "Exit Demo" leaves a permanent loading overlay stuck on screen
**Cycle Number:** 1
**Branch:** `feature/interactive-demo-band-experience` (stacked onto in-progress interactive-demo work, per the plan — not a defect)

---

## Final Verdict

**APPROVED**

The one-line `.autoDispose` conversion of `_exitingDemoProvider` (plus a 3-line
explanatory comment) exactly matches the Architect plan's chosen mechanism,
genuinely resolves the documented root cause by code-path analysis, introduces no
regressions in code-path analysis, touches only the approved file, adds no DB
change, and is analyzer-clean on its own changed lines. Remaining verification is
the plan's Tier-2 on-device exit → re-entry cycle, which is Tony's manual step
(steps listed at the end).

> **Verification honesty note:** My validation was **static analysis + full
> code-path tracing of the diff**, plus `flutter analyze`. I did **not** run the
> app on macOS/iOS. The Tier-2 on-device repro is explicitly designed by the plan
> as a post-deploy manual check by Tony and is not a QA gate for the code review;
> it has **not** been performed and remains required before release.

---

## Validation Summary

- Root cause (non-autoDispose provider retaining `state = true` at root-container
  scope across `AppShell` unmount → remount) is correctly and directly addressed
  by aligning the provider's lifetime with its intended semantics via
  `NotifierProvider.autoDispose<...>`. Confirmed in code, not at runtime.
- Diff is confined to `lib/features/shell/app_shell.dart`. `demo_session_service.dart`
  and every `supabase/migrations/**` file are pre-existing untracked branch work,
  **not** modified by this fix.
- `_ExitingDemoNotifier` still `extends Notifier<bool>` with the same `build() => false`
  and `setExiting(bool)` — unchanged, and compiles cleanly with the autoDispose
  modifier (Riverpod 3.x shares the `Notifier<T>` base for both forms).
- `flutter analyze lib/features/shell/app_shell.dart`: **0 errors, 0 warnings**;
  6 pre-existing `info` lints, none on this fix's changed lines.

---

## Architect Scope Review

**PASS.** The plan authorizes exactly one modified file — `app_shell.dart` — with a
`.autoDispose` modifier insertion plus a single explanatory comment, and forbids
touching `onExitDemoTap`, the overlay render site, and the `_ExitingDemoNotifier`
class body.

- `git diff HEAD -- lib/features/shell/app_shell.dart` shows the provider is now
  `NotifierProvider.autoDispose<_ExitingDemoNotifier, bool>(_ExitingDemoNotifier.new)`
  with the required "why autoDispose" comment above it.
- The plan's pre-fix line references (provider L52-L61, overlay render site
  L240-L248, handler L306-L321) map cleanly to the current file with only the
  3-line comment's downward shift — corroborating that nothing beyond the modifier
  - comment was added, and the overlay render site / handler / notifier body are
    left as-is.
- Off-limits files: `demo_session_service.dart`, `auth_gate.dart`, `login_screen.dart`,
  `side_drawer.dart`, `active_band_controller.dart`, and all `supabase/migrations/**`
  appear in `git status` as pre-existing interactive-demo branch work (the plan
  explicitly lists them as already-touched-by-the-branch and off-limits to this
  fix). None carry a change attributable to this fix.
- **Not conflated** with `docs/features/bug/demo-session-provisioning-not-idempotent/`
  (the separate `demo_session_service.dart` idempotency plan) — that file was not
  touched here.

---

## Completeness Check

**PASS.** All four Engineer tasks from the plan are done:

1. `_exitingDemoProvider` located and converted to `.autoDispose`.
2. Single explanatory comment added stating why autoDispose is required.
3. `_ExitingDemoNotifier` continues to extend `Notifier<bool>` (`build`/`setExiting`
   unchanged).
4. `onExitDemoTap`, the overlay render site, and the notifier class body untouched.

No partial implementation; the plan's rejected alternatives (post-`await` `ref.read`
reset; `initState` reset; belt-and-suspenders) were correctly **not** added.

---

## Behavior Verification

**Method: code-path analysis (not runtime-exercised).** Traced all three flows the
plan specifies:

- **Successful exit → re-entry (the bug):** `AppShell` is the sole watcher of
  `_exitingDemoProvider`. `onExitDemoTap` → `setExiting(true)` (overlay shows while
  mounted) → `await DemoSessionService.exit(ref)` → `exit_demo_session` RPC +
  `signOut()`. `signOut()` triggers `AuthGate` to swap `AppShell` → `LoginScreen`,
  unmounting `AppShell`; the last watcher drops, autoDispose fires, and the `true`
  state is discarded. On re-entry (`signInAnonymously` → `AuthGate` remounts
  `AppShell`), `ref.watch(_exitingDemoProvider)` reconstructs the Notifier via
  `build() => false`, so the `ModalBarrier` + `CircularProgressIndicator` overlay
  does **not** render. Root cause resolved — not a symptom patch. ✅
- **Failed exit (error path):** `exit()` throws → `AppShell` stays mounted (no auth
  change) → Notifier still alive → existing `catch` sets `setExiting(false)`, guarded
  by `context.mounted`, and shows `showErrorSnackBar(... "Couldn't exit the demo —
try again.")`. autoDispose is inert here. Unchanged behavior. ✅
- **First-entry (no prior exit):** provider initializes fresh at `false` on first
  watch; overlay never shows. Unchanged. ✅
- **Normal (single) exit render site:** the overlay is gated by
  `if (ref.watch(_exitingDemoProvider)) ...[]`; while mounted the watch keeps the
  Notifier alive so the overlay remains visible for the duration of the exit until
  `signOut()` unmounts the shell. autoDispose does not fire early during a normal
  mounted exit. ✅

The plan's noted benign edge (autoDispose disposing the Notifier before the pending
`await` returns) is confirmed harmless by code-path: after unmount there is no
overlay to render, and the success path never re-reads the provider. The error-path
`catch` re-reading a possibly-disposed `_MenuDrawerLayer` ref is a **pre-existing,
out-of-scope** hazard the plan explicitly excludes; Riverpod re-instantiates the
Notifier if disposed (no crash).

---

## Regression Check — Risk: **LOW**

| System                        | Rating | Notes                                                                                                     |
| ----------------------------- | ------ | --------------------------------------------------------------------------------------------------------- |
| Auth / session                | LOW    | No auth/session code touched; only the demo-exit overlay's provider lifetime changed.                     |
| Supabase RPC signatures       | LOW    | No RPC added/changed; `DemoSessionService.exit` untouched.                                                |
| Init order                    | LOW    | `main.dart` init sequence not touched.                                                                    |
| Platform parity               | LOW    | Pure Dart provider modifier in `lib/`; no platform-conditional code — identical on iOS/Android/macOS/web. |
| Controller/FocusNode disposal | LOW    | `Notifier<bool>` holds no disposable resources; nothing to leak.                                          |
| `setState` after async gap    | LOW    | Error path uses `context.mounted` guard before showing the snackbar; no `setState` added.                 |
| Rebuild triggers/frequency    | LOW    | Same single `ref.watch` gate; no new watchers. Overlay stack unchanged.                                   |
| Drawer / tab navigation       | LOW    | `_MenuDrawerLayer`, `overlayStateProvider`, tab providers untouched (smoke-check recommended on device).  |

No regression detected in code-path analysis.

---

## Database Safety

**N/A — no DB change introduced by this fix.** Database Impact per plan is "None":
no migration, no RLS change, no new/changed RPC, no `SECURITY DEFINER`/grant
surface. The `.sql` files present under `supabase/migrations/**` are untracked
pre-existing interactive-demo branch work belonging to a separate plan and are not
part of this diff. Because this fix adds/changes **zero** migrations, the
migration-apply-on-a-Supabase-branch check does not apply and was intentionally not
run. No `has_function_privilege` verification is relevant.

---

## Analyzer Results

`flutter analyze lib/features/shell/app_shell.dart` → **0 errors, 0 warnings**, 6
`info` lints:

- `211:13` `prefer_const_constructors`, `216:24` / `217:27` / `218:34`
  `avoid_redundant_argument_values` — inside the `if (kIsWeb) NativeAppBanner`
  block. **Pre-existing interactive-demo branch work, unrelated to this fix.**
- `247:13` / `248:22` `prefer_const_constructors` — the exit-demo overlay render
  site (`Center` / `CircularProgressIndicator`). These are the **plan-protected**
  lints: the plan explicitly directs this render site (L240-L248) be left "as-is,"
  so touching them would exceed scope.

**None of the 6 lints fall on this fix's actually-changed lines** (the
`.autoDispose` provider declaration and its comment); the fix itself introduces
zero analyzer issues. Per the plan's role as validation authority — and consistent
with the Manager's brief pre-acknowledging "only pre-existing info lints, including
the two plan-protected ones at the overlay render site" — these pre-existing lints
in code this fix did not author and is forbidden to touch do **not** block. The
`.autoDispose` static form analyzed cleanly (no API-shape rejection), matching the
`FutureProvider.autoDispose` precedent in `notification_controller.dart`.

---

## Test Results

**No offline widget/unit test added — accepted as plan-sanctioned Tier-2-only
verification (NOT a silent skip).** The plan's Verification Plan classifies the
widget test as "recommended, not required" and states "We do not require adding a
widget test as a gate for this fix," documenting three concrete reasons the offline
test is infeasible within scope:

1. `_exitingDemoProvider` is file-private with no test seam; forcing it to `true`
   from a test would require a `@visibleForTesting` export, which the plan forbids
   ("Nothing else in this file changes").
2. The overlay only renders inside a fully built `AppShell`, which watches
   `activeBandProvider` / `currentUserPermissionsProvider` / `userProfileProvider` /
   `overlayStateProvider` / `currentTabProvider` and builds heavy tab content
   (timers/network) — the existing `auth_gate_anonymous_recovery_test.dart`
   deliberately avoids ever building `AppShell` for this exact reason.
3. The only in-app path to set the flag runs through `DemoSessionService.exit`
   (off-limits) and would need a full mocked Supabase RPC + auth + band harness that
   does not exist.

The Engineer performed and documented an honest feasibility attempt and recorded the
skip under Test Results and Deviations. `flutter test` was correctly not run for
this area (no existing coverage, no test added), consistent with the engineer-mode
rule. I independently agree an offline test is not feasible here without violating
the plan's explicit "no `@visibleForTesting` export / don't touch other symbols"
constraint. Verification therefore correctly defers to Tier-2 on-device.

---

## Diff Safety Review

**PASS.**

- Grep of the changed file for `TODO` / `FIXME` / `debugPrint(` / `print(`:
  **none** on the fix's diff. (Note: `demo_session_service.dart` contains pre-existing
  `debugPrint` calls in `provisionAndEnter`, but that file is off-limits branch work
  and not part of this fix's diff — not a finding here.)
- No secrets/API keys in the diff.
- No leftover test scaffolding, accidental deletions, or unrelated formatting churn
  attributable to the fix.

---

## Change Budget Review

**PASS (within budget).** Plan budget: `app_shell.dart` ≈ +1 line / −0, one-line
comment, 0 new files/public classes/dependencies/tests. Actual fix change: the
`.autoDispose` modifier plus a 3-line wrapped explanatory comment (≈ +4 lines,
0 deletions), 0 new files, 0 new public symbols, 0 new dependencies. The comment is
a single logical explanation wrapped at the repo's ~80-column width, not scope
inflation. Zero deleted lines is expected and correct here — the plan's chosen fix
is a _missing-disposal_ lifetime alignment (a modifier insertion), not the removal
of a defective line — and the Engineer explicitly justified this in the report, so
the usual "zero-deletions bug fix" Warning does not apply.

---

## Code Efficiency Review

**PASS.** No new helper/util/widget/provider/notifier introduced — the fix is a
modifier on an existing file-private provider. It reuses the codebase's established
`.autoDispose` static-form idiom (`FutureProvider.autoDispose<int>` in
`notification_controller.dart`) rather than inventing a new pattern. No
AI-shaped constructs (no speculative flags, no `FutureBuilder`/`StreamBuilder`, no
unread field/param, no barrel file, no single-call-site wrapper). The added comment
states only the non-obvious "why" (lifetime/semantics mismatch), not a restatement
of the line below it.

---

## Issues Found

**Critical:** none.

**Warnings:** none.

**Suggestions:**

- _(code-quality, non-blocking)_ The plan said "single-line explanatory comment";
  the Engineer wrote a 3-line wrapped comment. This is a formatting artifact of the
  ~80-col wrap of one logical statement, honors the plan's intent (explain the
  non-obvious why, don't restate the next line), and is not scope inflation. No
  action required.
- _(out-of-scope, non-blocking — informational)_ The pre-existing error-path
  `ref.read(_exitingDemoProvider.notifier).setExiting(false)` in the `catch` block
  reads a possibly-disposed `_MenuDrawerLayer` ref. The plan explicitly declares
  this out of scope with no reported symptom; autoDispose re-instantiates the
  Notifier if disposed, so there is no crash. Flagged only for traceability.

---

## On-Device Tier-2 Steps Still Required (Tony)

These have **not** been performed by QA and are required before release, on macOS
and one iOS device:

1. Launch the branch build (`./run.sh macos`, and `./run.sh ios` on a device/sim).
2. From login, tap **"Check out the demo band"** → confirm the demo loads with **no**
   stuck overlay (first-entry baseline).
3. Side drawer → **"Exit Demo"** → overlay appears briefly, then the login screen
   shows, **no** error snackbar.
4. Immediately tap **"Check out the demo band"** again.
5. **Assert:** demo band loads and is fully interactive — **no** `ModalBarrier`, **no**
   stuck `CircularProgressIndicator`; tabs, drawer, and input all work.
6. Repeat steps 3-5 a second time in the same app session (stability across cycles).
7. **Error path:** enable airplane mode, tap **"Exit Demo"** → overlay clears and the
   "Couldn't exit the demo — try again." snackbar shows; re-enable network.

Passing all seven on macOS and iOS satisfies the plan's verification.
