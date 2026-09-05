# Engineer Report — Demo Exit/Re-Entry Stuck Spinner

**Feature Slug:** `bug/demo-exit-reentry-stuck-spinner`
**Feature Title:** Re-entering the demo after "Exit Demo" leaves a permanent loading overlay stuck on screen
**Cycle Number:** 1
**Branch:** `feature/interactive-demo-band-experience`

---

## Goal

Fix the stuck full-screen `ModalBarrier` + `CircularProgressIndicator` overlay that renders on demo re-entry after a prior "Exit Demo". Root cause: `_exitingDemoProvider` in `lib/features/shell/app_shell.dart` is a top-level, non-autoDispose provider whose Notifier lives at root-container scope for the whole app process. `onExitDemoTap` sets it `true` and only resets it in the `catch` block, never on the success path — so after exit → sign-out → re-entry, `AppShell` remounts and reads a stale `true` with nothing left to clear it.

## Architect Tasks Completed

1. Located the `_exitingDemoProvider` declaration in `lib/features/shell/app_shell.dart`.
2. Added a single-line explanatory comment above the declaration stating why `autoDispose` is required (so the flag is discarded when `AppShell` unmounts during sign-out → sign-in, otherwise re-entry renders a stuck overlay).
3. Changed the declaration from `NotifierProvider<_ExitingDemoNotifier, bool>(_ExitingDemoNotifier.new)` to `NotifierProvider.autoDispose<_ExitingDemoNotifier, bool>(_ExitingDemoNotifier.new)`. `_ExitingDemoNotifier` continues to extend `Notifier<bool>` with the same `build()` and `setExiting` methods — unchanged.
4. Left `onExitDemoTap`, the overlay render site, and the `_ExitingDemoNotifier` class body untouched.

This is exactly the plan's mechanism. The alternatives the plan rejected (post-`await` `ref.read` reset; `initState` reset) were not added.

## Files Created

- `docs/features/bug/demo-exit-reentry-stuck-spinner/ENGINEER_REPORT.md` (this report).

## Files Modified

- `lib/features/shell/app_shell.dart` — converted `_exitingDemoProvider` to `NotifierProvider.autoDispose<...>` and added one explanatory comment line. Net source change: the provider declaration plus a 3-line comment. No other symbol in the file changed.

## Analyzer Results

Command: `flutter analyze lib/features/shell/app_shell.dart`

Result: **0 errors, 0 warnings.** 6 `info`-level lints reported — all pre-existing, all in regions the plan forbids me to touch, none introduced by this change:

- `app_shell.dart:211:13` `prefer_const_constructors` — inside the pre-existing `if (kIsWeb) ... NativeAppBanner` block (interactive-demo branch work, not part of this fix).
- `app_shell.dart:216:24`, `217:27`, `218:34` `avoid_redundant_argument_values` — same `NativeAppBanner` block.
- `app_shell.dart:247:13`, `248:22` `prefer_const_constructors` — the exit-demo overlay render site (`Center` / `CircularProgressIndicator`). The plan explicitly directs this render site be left "as-is" ("Nothing else in this file changes — the ... overlay render site ([L240-L248]) ... left as-is"), so fixing these would contradict the plan and exceed scope.

All 6 pre-date this edit (they belong to the uncommitted interactive-demo branch diff that already existed in the working tree). The one-line `.autoDispose` change plus comment introduces **zero** new analyzer issues; the `.autoDispose` static form analyzed cleanly (no API-shape rejection, consistent with the `FutureProvider.autoDispose` precedent noted in the plan).

## Test Results

**No test added.** Per the plan, the widget test is explicitly optional ("We do not require adding a widget test as a gate for this fix"), and I confirmed via an honest feasibility attempt that an offline widget test is not feasible within scope:

- `_exitingDemoProvider` is file-private (`_` prefix) — it cannot be imported, overridden, or set to `true` from a test in `test/features/` without a `@visibleForTesting` export, which the plan forbids ("Nothing else in this file changes").
- The overlay only renders inside a fully built `AppShell`, which watches `activeBandProvider`, `currentUserPermissionsProvider`, `userProfileProvider`, `overlayStateProvider`, `currentTabProvider` and builds `HomeTabContent` and the setlists/calendar/contacts tab contents — heavy widgets that spin up timers/network. The reference test `test/features/auth/auth_gate_anonymous_recovery_test.dart` deliberately avoids ever building `AppShell` for exactly this reason (see its `_FakeActiveBandNotifier` `loadedIsLoading` comment).
- The only in-app way to set the flag `true` is tapping "Exit Demo" → `DemoSessionService.exit(ref)` (RPC `exit_demo_session` + `signOut`). `DemoSessionService` is off-limits per the plan, and driving it would require a full mocked Supabase RPC + auth + band/permission harness that does not currently exist.

This matches the plan's own documented rationale for not mandating the test. `flutter test` was not run for the changed area because it has no existing coverage and no test was added (per engineer-mode step 4: run tests only if the plan requires it or the changed area has coverage — neither applies). Verification is deferred to the plan's Tier-2 on-device steps (macOS + iOS exit → re-entry cycles).

## Code Efficiency/Bloat Check

- **Searched for an existing equivalent before changing anything:** the fix is a modifier on an existing file-private provider, so no new helper/util/widget was created. Grepped the plan's cited precedent — the codebase already uses the `.autoDispose` static-form idiom (`FutureProvider.autoDispose<int>` in `lib/features/notifications/notification_controller.dart`), so this fix reuses an established pattern rather than introducing a new one.
- **No AI-shaped code:** no new provider/notifier, no new model field, no new parameter, no `FutureBuilder`/`StreamBuilder`, no barrel file, no speculative flags. The comment states only the non-obvious "why" (lifetime/semantics mismatch) rather than restating the line below it.
- **Zero deleted lines is expected here and is correct:** the plan's chosen root-cause fix is a lifetime change to the provider, not removal of defective code — the defect is a _missing_ disposal, so the correct fix aligns the provider's lifetime with its intended semantics (a modifier insertion) rather than deleting a wrong line. This is the mechanism the plan explicitly selected over the reset-based alternatives.
- **File size:** `app_shell.dart` is large and pre-existing; this change adds ~4 lines (comment + reflowed declaration) and does not push it past any new threshold introduced by me. No new abstraction added to it.

## Verification (manual steps performed)

- Confirmed on branch `feature/interactive-demo-band-experience` with the expected working tree (the plan's `docs/features/bug/demo-exit-reentry-stuck-spinner/` folder untracked; `app_shell.dart` and other files pre-modified by in-progress branch work).
- Read the full `ARCHITECT_PLAN.md`; confirmed its Feature Slug matches.
- Applied the change and re-read the diff: exactly one changed declaration (now wrapped as `.autoDispose`) plus one 3-line comment; no other symbol touched; `onExitDemoTap`, the overlay render site, and the `_ExitingDemoNotifier` class body are byte-for-byte unchanged from the pre-edit working tree.
- Ran `flutter analyze` on the touched file — 0 errors/warnings; only the 6 pre-existing off-limits info lints remain.
- Traced the three flows from the plan by inspection: successful exit (unmount disposes the sole watcher → re-entry `build() => false`, no overlay), failed exit (`AppShell` stays mounted, existing `catch` resets to `false` + snackbar), first-entry (fresh `false`). All consistent with the plan.

## Deviations From Plan

None. The plan's optional widget test was not added; the plan documents this as acceptable and directs noting it here and relying on Tier-2 — which is done.

## Blockers Encountered

None blocking the source fix. The offline widget test is infeasible within scope (detailed under Test Results); this is anticipated and permitted by the plan, not a blocker.

## Ready For QA

**Yes.** Analyzer is error/warning-clean on the touched file (only pre-existing, plan-protected info lints remain); the source fix matches the plan exactly; no test was required. Recommend QA execute the plan's Tier-2 on-device exit → re-entry verification on macOS and iOS.
