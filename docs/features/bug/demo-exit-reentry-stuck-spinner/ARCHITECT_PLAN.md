# Architect Plan — Demo Exit/Re-Entry Stuck Spinner

**Feature Slug:** `bug/demo-exit-reentry-stuck-spinner`
**Feature Title:** Re-entering the demo after "Exit Demo" leaves a permanent loading overlay stuck on screen
**Type:** Bug
**Branch:** `feature/interactive-demo-band-experience` (stacked onto in-progress interactive-demo work — not a fresh branch)

---

## Problem Summary

After exiting the interactive demo band and immediately re-entering it via "Check out the demo band", the app renders a full-screen `ModalBarrier` + `CircularProgressIndicator` overlay that never clears. Band data (setlists, members, gig/rehearsal prompts) resolves correctly underneath — the overlay itself is the stuck element and it blocks all input, forcing an app restart. First-entry (no prior exit in the same app session) is unaffected.

---

## Root Cause — HIGH confidence (confirmed in code)

Located in [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart). Three code sites conspire:

1. **Provider declaration ([app_shell.dart#L52-L61](lib/features/shell/app_shell.dart#L52-L61))** — `_exitingDemoProvider` is a top-level, module-scoped, **non-autoDispose** `NotifierProvider<_ExitingDemoNotifier, bool>`. Its Notifier is therefore created once in the **root `ProviderContainer`** and lives for the entire app-process lifetime; nothing else in the codebase invalidates it.

2. **Overlay render site ([app_shell.dart#L240-L248](lib/features/shell/app_shell.dart#L240-L248))** — `AppShell.build` unconditionally does `if (ref.watch(_exitingDemoProvider)) { ModalBarrier + CircularProgressIndicator }`. The overlay's visibility is entirely a function of the provider's boolean state.

3. **Exit handler ([app_shell.dart#L306-L321](lib/features/shell/app_shell.dart#L306-L321))** — `onExitDemoTap` calls `setExiting(true)` before `await DemoSessionService.exit(ref)` and **only resets to `false` inside the `catch` block**. The success path has no reset.

Cross-referencing [lib/features/auth/demo_session_service.dart#L34-L42](lib/features/auth/demo_session_service.dart#L34-L42), `DemoSessionService.exit` completes by awaiting `client.auth.signOut()`. That triggers `AuthGate` to swap `AppShell` → `LoginScreen`, unmounting `AppShell`. But because `_exitingDemoProvider` is non-autoDispose and lives at root scope, unmounting `AppShell` does **not** dispose the Notifier — it silently retains `state = true`.

Lifecycle across the reported repro:

| Step | Event                                                                            | `_exitingDemoProvider` state        | `AppShell` mounted?                                                      |
| ---- | -------------------------------------------------------------------------------- | ----------------------------------- | ------------------------------------------------------------------------ |
| 1    | User taps Exit Demo                                                              | `false` → `true` (via `setExiting`) | yes (overlay shows)                                                      |
| 2    | `exit_demo_session` RPC awaits                                                   | `true`                              | yes                                                                      |
| 3    | `signOut()` completes → auth state changes                                       | `true` (retained at root scope)     | **unmounted** by AuthGate                                                |
| 4    | LoginScreen renders                                                              | `true` (still retained)             | no                                                                       |
| 5    | User taps "Check out the demo band" → `signInAnonymously` succeeds               | `true` (still retained)             | no                                                                       |
| 6    | AuthGate remounts `AppShell`                                                     | `true` (still retained)             | **re-mounted**                                                           |
| 7    | First `AppShell.build` after remount evaluates `ref.watch(_exitingDemoProvider)` | `true`                              | yes — **overlay renders immediately with no code path left to clear it** |

The Feature Input's diagnosis is exactly correct. The prior feature's `QA_REPORT.md` only asserted "Exit Demo wiring present and gated" — it never exercised an exit → re-entry cycle, so the missing success-path reset went unnoticed.

---

## Existing System Analysis

- `DemoSessionService.exit` is a pure client-side wrapper over one RPC + `signOut()`. It does not touch `_exitingDemoProvider`, nor should it — the overlay state is a UI concern owned by `AppShell`.
- `DemoSessionService.provisionAndEnter` already documents (and works around) the fact that a `WidgetRef` captured in a login/drawer callback becomes invalid once the parent widget unmounts across an auth-state change. This is the codebase's established pattern for demo flows and directly informs why an explicit post-`await` `ref.read` reset on the exit success path would be fragile.
- `_exitingDemoProvider` is file-private (`_` prefix) — it has no other watchers or mutators anywhere in the codebase. This means the overlay's behavior is fully captured by the three sites listed above; nothing external needs to be changed.
- `flutter_riverpod: ^3.0.3` (Riverpod 3.x) is in use. The codebase already uses the `.autoDispose` static-form modifier idiom — see [lib/features/notifications/notification_controller.dart#L46](lib/features/notifications/notification_controller.dart#L46) (`FutureProvider.autoDispose<int>((ref) async { ... })`).

---

## Proposed Solution

**Convert `_exitingDemoProvider` from `NotifierProvider<...>` to `NotifierProvider.autoDispose<...>`.**

With `autoDispose`:

- While `AppShell` is mounted, the `ref.watch(_exitingDemoProvider)` in `build` keeps the Notifier alive — the overlay behaves exactly as today during the intended exit flow.
- When `signOut()` causes `AuthGate` to unmount `AppShell`, the last watcher goes away and Riverpod disposes the Notifier, discarding its state.
- When `AppShell` remounts on re-entry, `ref.watch(_exitingDemoProvider)` reconstructs the Notifier via `build() => false`. The overlay does not render. Bug fixed.

That is the entire fix. It is one changed line in one file plus a single-line explanatory comment.

### Alternatives Considered and Rejected

1. **Explicit reset on the success path** (`try { ... ref.read(...).setExiting(false); } catch { ... }`, or a `try/finally` reset).
   Rejected: requires holding a valid `WidgetRef` across the `await` on `DemoSessionService.exit(ref)`. By the time that future completes, `AuthGate` has already swapped in `LoginScreen`, so the `_MenuDrawerLayer`'s ref (which is what the callback closes over) is disposed. This is the exact hazard `DemoSessionService.provisionAndEnter` already documents and works around by capturing notifiers synchronously; the codebase's established pattern is to _not_ do post-`await` `ref.read`. autoDispose achieves the same reset without adding a fragile ref-after-async access.

2. **Reset in `AppShell.initState` (or an inline `ref.listenManual`).**
   Rejected: mutating a provider inside `initState` / `build` is the "modify provider during build" hazard the guardrails explicitly call out. Workable only via `WidgetsBinding.instance.addPostFrameCallback`, which is measurably more code, mutates state unconditionally on every mount (including the healthy first-entry path), and doesn't fix the underlying design smell — the provider's lifetime doesn't match its intended semantics. autoDispose aligns lifetime and semantics directly.

3. **Belt-and-suspenders (autoDispose + explicit `try/finally` reset).**
   Rejected as scope creep. autoDispose is sufficient (verified below). Adding the reset re-introduces the ref-after-async hazard from Option 1 for zero incremental safety, contradicting the guardrail against speculative extra code.

### Why autoDispose Alone Is Sufficient (verification of reasoning)

- **Successful exit flow:** `AppShell` is the sole watcher of `_exitingDemoProvider`. When `signOut()` triggers unmount, watcher count drops to zero → autoDispose fires → state discarded. On re-entry remount, `build() → false`. No stuck overlay. ✅
- **Failed exit flow:** `client.rpc('exit_demo_session')` or `signOut()` throws. `AppShell` remains mounted (auth didn't change), so the provider is still alive; the existing `catch` block resets `state = false` normally and shows the error snackbar. autoDispose is inert here. ✅
- **First-entry flow (no prior exit):** provider is initialized fresh at `false` on first watch. Never touched. Unchanged. ✅

### "Modify Provider During Build" Hazard

None introduced. The only mutations of `_exitingDemoProvider` remain (a) inside the `onExitDemoTap` button callback and (b) inside its `catch` block — both are post-frame event handlers, not `build`-time code. The autoDispose modifier is a provider-level attribute; it does not add any build-time mutation.

---

## Database Impact

**None.** This is a pure client-side Flutter state fix.

- No migrations.
- No RLS policy changes.
- No new RPCs; no changes to `exit_demo_session`, `heartbeat_demo_session`, or `provision_demo_session`.
- No `SECURITY DEFINER` / `search_path` / grant / `has_function_privilege` verification needed.

---

## Flutter Architecture Changes

**None beyond the single provider modifier.** No new controllers, providers, repositories, services, widgets, or files. The `_ExitingDemoNotifier` class continues to extend `Notifier<bool>` (Riverpod 3.x uses the same `Notifier<T>` base class for both autoDispose and non-autoDispose provider modifiers).

---

## Files to Create

n/a

---

## Files to Modify

- [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart) — change the `_exitingDemoProvider` declaration from `NotifierProvider<_ExitingDemoNotifier, bool>(_ExitingDemoNotifier.new)` (currently at [L59-L61](lib/features/shell/app_shell.dart#L59-L61)) to `NotifierProvider.autoDispose<_ExitingDemoNotifier, bool>(_ExitingDemoNotifier.new)`. Add a single-line explanatory comment above the provider declaration (~L58) stating that autoDispose is required so the exit-in-progress flag resets when `AppShell` unmounts during sign-out → sign-in, otherwise re-entry renders a stuck overlay. Nothing else in this file changes — the `onExitDemoTap` handler ([L306-L321](lib/features/shell/app_shell.dart#L306-L321)), overlay render site ([L240-L248](lib/features/shell/app_shell.dart#L240-L248)), and `_ExitingDemoNotifier` class body are left as-is.

---

## Files Off-Limits

- [lib/features/auth/demo_session_service.dart](lib/features/auth/demo_session_service.dart) — explicitly out of scope per Feature Input; a separate not-yet-built plan at `docs/features/bug/demo-session-provisioning-not-idempotent/` addresses clone-duplication behavior there. Do not touch.
- Any `supabase/migrations/*.sql` — no DB change is required or permitted for this fix.
- Any `supabase/functions/**` — edge functions are unaffected.
- [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart), [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart), [lib/features/home/widgets/side_drawer.dart](lib/features/home/widgets/side_drawer.dart), [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart) — these are all touched by the in-progress interactive-demo work already on this branch, but this fix does not need any change in them; leaving them untouched preserves the branch's uncommitted diff for its own eventual PR.
- `.github/agents/**` — pipeline configuration, do not modify.
- Everything else in the workspace.

---

## Change Budget

- **Expected net line delta per file:** `lib/features/shell/app_shell.dart` — approximately **+1 line, -0 lines** (one `.autoDispose` insertion plus a one-line clarifying comment; the existing declaration line's total character count changes by ~13 characters).
- **Expected new files:** 0.
- **Expected new public classes/methods:** 0.
- **Expected new dependencies:** 0.
- **Expected new tests:** 0 required. See Verification Plan for the Tier-1 test option and why it is not being mandated.

---

## System Impact Map

| System        | Status                        | Notes                                                                                                                                                                                                                     |
| ------------- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs          | unaffected                    | No touchpoint.                                                                                                                                                                                                            |
| Rehearsals    | unaffected                    | No touchpoint.                                                                                                                                                                                                            |
| Setlists      | unaffected                    | No touchpoint.                                                                                                                                                                                                            |
| Members       | unaffected                    | No touchpoint.                                                                                                                                                                                                            |
| Auth          | unaffected                    | Auth flows untouched; only the UI overlay tied to the demo-exit action changes lifecycle behavior.                                                                                                                        |
| Routing       | unaffected                    | No routing/navigation changes.                                                                                                                                                                                            |
| Notifications | unaffected                    | No touchpoint.                                                                                                                                                                                                            |
| Platforms     | unaffected — parity preserved | Change is a Riverpod provider modifier in `lib/`, shared across all platforms (iOS, Android, macOS, web). No platform-conditional code touched. No difference in behavior between native and web.                         |
| Init order    | unaffected                    | Fixed init sequence (`WidgetsFlutterBinding` → URL strategy → orientation → `AppVersionService` → `validateSupabaseConfig` → `Supabase.initialize` → conditional Firebase → `DeepLinkService` → `runApp`) is not touched. |

---

## Regression Risk — LOW

Justified by:

- Scope is a **single-line modifier on a file-private provider with one watcher and two mutation sites**, all in the same file.
- No auth, session, routing, init-order, or DB code is touched.
- The provider's semantic contract does not change (it is still `Notifier<bool>` with the same `build() => false` and `setExiting(bool)` API). Only its container-lifetime binding changes from "root scope, live forever" to "disposed when no widget watches".
- Both success and failure paths of the exit flow, and the first-entry flow, continue to behave identically for the user (walked step-by-step in "Why autoDispose Alone Is Sufficient" above).

The only non-obvious behavior worth flagging: when `AppShell` unmounts mid-exit, autoDispose will silently dispose the Notifier before the pending `await DemoSessionService.exit` returns. This is harmless — after unmount there is no overlay to render regardless, and the `try`/`catch` in `onExitDemoTap` never re-reads the provider on the success path. On the error path, the `catch` calls `ref.read(_exitingDemoProvider.notifier).setExiting(false)`; Riverpod will re-instantiate the Notifier if it was disposed and set it to `false` — no crash, no visible effect. Note that the pre-existing ref-after-async hazard in the `catch` block (using a possibly-disposed `_MenuDrawerLayer` ref) is **out of scope** here; it predates this fix, has no reported symptom, and is not what causes the stuck spinner.

---

## Engineer Task Breakdown

1. Open [lib/features/shell/app_shell.dart](lib/features/shell/app_shell.dart). Locate the `_exitingDemoProvider` declaration at approximately L59-L61.
2. Add a single-line comment immediately above the provider declaration explaining that `.autoDispose` is required so the exit-in-progress flag resets when `AppShell` unmounts during the sign-out → sign-in cycle (otherwise re-entering the demo renders a stuck overlay). Keep it to one short line — do not restate what the next line does.
3. Change the provider declaration from `NotifierProvider<_ExitingDemoNotifier, bool>(_ExitingDemoNotifier.new)` to `NotifierProvider.autoDispose<_ExitingDemoNotifier, bool>(_ExitingDemoNotifier.new)`. Do not modify the `_ExitingDemoNotifier` class body — it continues to extend `Notifier<bool>` with the same `build()` and `setExiting` methods.
4. Do not touch `onExitDemoTap` ([L306-L321](lib/features/shell/app_shell.dart#L306-L321)), the overlay render site ([L240-L248](lib/features/shell/app_shell.dart#L240-L248)), or any other symbol in the file.
5. Save. Run `flutter analyze`. Expect zero new warnings/errors. If the `.autoDispose` static form is somehow rejected by this exact Riverpod 3.0.3 patch — an outcome not expected given the `FutureProvider.autoDispose` precedent at [notification_controller.dart#L46](lib/features/notifications/notification_controller.dart#L46) — stop and report; do not silently switch to a different API shape.

There is no step 6. The rest is verification (below), not implementation.

---

## Verification Plan

### Tier 1 — Pre-deploy (fast, does not exercise the real bug flow)

**Static verification (required):**

- `flutter analyze` returns clean (no new warnings/errors introduced by the change).
- Read-through of the diff confirms exactly one changed declaration line and one new comment line in `lib/features/shell/app_shell.dart`; no other file modified.

**Widget test (recommended, not required — see rationale):**

`_exitingDemoProvider` is file-private, so a targeted external unit test would require either exposing it (adds public API surface for testing-only concerns) or a `part`-file. Given that:

- The autoDispose semantics themselves are a well-tested guarantee of the Riverpod framework and do not need re-verification at the app level.
- The codebase's test coverage in this feature area is thin (no existing widget tests for `AppShell` demo-overlay behavior).
- The real bug reproduces only across an auth-state cycle (sign-out → sign-in) and an `AppShell` unmount/remount, which requires a mocked Supabase auth harness that does not currently exist.

We do **not** require adding a widget test as a gate for this fix. If Engineer chooses to add one, the minimal shape would be: build `AppShell` inside a `ProviderScope` with a mock auth client; simulate `_exitingDemoProvider = true` (which requires exposing the provider — declare that as a scoped, `@visibleForTesting` change if pursued); unmount `AppShell`; remount; assert the overlay is not rendered. This is explicitly optional. If Engineer skips it, note that in `ENGINEER_REPORT.md` and rely on Tier 2.

**No SQL tests, no `has_function_privilege` checks, no idempotency checks apply** — no DB, RPC, or submission flow is touched by this fix.

### Tier 2 — Post-deploy (on-device, exercises the exact reported repro)

Required on macOS and one iOS device (the two platforms actively used to reproduce demo flows today). Web verification is a nice-to-have but not gating (web push and other web-specific paths are not involved).

Steps:

1. Launch the app (`./run.sh macos` and `./run.sh ios` on a physical device / simulator with the branch's build).
2. From the login screen, tap "Check out the demo band". Confirm the demo band loads normally with no stuck overlay (baseline — first-entry path unchanged).
3. Open the side drawer → tap "Exit Demo". Confirm the overlay appears briefly, then the login screen is shown. No error snackbar.
4. Immediately (within a few seconds) tap "Check out the demo band" again.
5. **Assert:** the demo band loads and is fully interactive; there is no `ModalBarrier` and no `CircularProgressIndicator` overlay stuck on screen. The user can tap tabs, open the drawer, and use the app.
6. Repeat steps 3-5 a second time in the same app session to confirm the fix is stable across multiple exit/re-entry cycles.
7. **Error-path sanity check:** temporarily airplane-mode the device, tap "Exit Demo", confirm the overlay clears and an error snackbar shows ("Couldn't exit the demo — try again."). Re-enable network. This confirms the existing catch path still works — unchanged behavior expected.

Passing all seven steps on macOS and iOS satisfies verification.

---

## QA Regression Areas

- **Exit Demo flow** — happy path and error path, both on native and web (web can be a smoke check).
- **Demo re-entry flow** — the specific bug being fixed.
- **First-entry demo flow** — must be unchanged (no prior state to carry over).
- **Side drawer overlay behavior generally** — the fix does not touch `_MenuDrawerLayer`, `overlayStateProvider`, or drawer open/close, but the exit tap is invoked from the drawer, so a smoke check that opening/closing the drawer works normally is prudent.
- **AppShell tab navigation** — untouched but sits in the same file; a smoke check that tabs still switch normally is prudent.

Explicitly **not** a regression area: gigs, rehearsals, setlists, members, auth flows unrelated to demo, notifications, calendar. None of these have any code path affected by this change.

---

## Rollout Strategy

Standard rollout. This is a client-side single-file bug fix and stacks onto the in-progress `feature/interactive-demo-band-experience` branch — it should ship as part of that same PR (or as an immediate follow-up PR that merges before or with the interactive-demo work). No feature flag, no staged rollout, no migration ordering concerns.

---

## Out of Scope

- The pre-existing latent ref-after-async hazard in the `onExitDemoTap` catch block (using a possibly-disposed `_MenuDrawerLayer` `WidgetRef` for `ref.read(_exitingDemoProvider.notifier).setExiting(false)`). No reported symptom; unchanged by this fix; separate concern if it ever surfaces.
- Demo session idempotency / clone duplication — tracked separately at `docs/features/bug/demo-session-provisioning-not-idempotent/`.
- Demo cold-start / stale anon-session behavior — tracked separately at `docs/features/bug/demo-cold-start-stale-anon-session/`.
- The existing `QA_REPORT.md` for the parent interactive-demo feature — flagged in root-cause analysis as having missed the exit → re-entry lifecycle, but retro-editing that report is out of scope. The current bug's own `QA_REPORT.md` will cover this fix.
- Any refactor of `_MenuDrawerLayer`, `AppShell`, or the overlay stack.
- Extracting `_exitingDemoProvider` into its own file for testability. Its private, single-watcher scope is a deliberate keep-simple choice; extracting it is not justified by this bug.
