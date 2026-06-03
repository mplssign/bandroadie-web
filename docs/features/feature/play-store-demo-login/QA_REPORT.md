# QA Report — Play Store Demo Login

**Feature slug:** `feature/play-store-demo-login`
**Branch:** `feature/play-store-demo-login`
**QA Agent:** AI QA Agent
**Date:** 2026-06-03
**Verdict:** ⚠️ REQUIRES CHANGES

---

## Verdict Summary

The feature implementation itself is **correct and complete**. All Architect-specified tasks were carried out accurately. However, the working tree contains uncommitted out-of-scope modifications — including an explicit `lib/main.dart` change that the Architect plan **prohibits** — that would be bundled into the feature commit as-is. These must be isolated before committing.

---

## Phase 0 — Guardrails

`docs/agents/GUARDRAILS.md` read in full. Present and complete.

---

## Phase 1 — Workspace State

```
Branch: feature/play-store-demo-login  ✓
```

Working tree is **not clean**. Both feature and non-feature changes are present.

**Feature-scope changes (expected):**

- `lib/features/auth/login_screen.dart` ✓
- `dart_defines.json` ✓
- `.env.example` ✓
- `tools/build_web.sh` ✓
- `lib/app/constants/demo_credentials.dart` (untracked, new) ✓
- `docs/features/feature/play-store-demo-login/` (untracked, new) ✓
- `run.sh`, `tools/build_android.sh`, `tools/build_ios.sh` — **gitignored**, verified via grep

**Out-of-scope changes (not in Architect plan):**

| File                                                                    | Note                                       |
| ----------------------------------------------------------------------- | ------------------------------------------ |
| `lib/main.dart`                                                         | **EXPLICITLY FORBIDDEN** by Architect plan |
| `lib/shared/widgets/keyboard_aware_wrapper.dart` (untracked)            | New file outside Architect scope           |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | Keyboard height padding change             |
| `lib/features/lyrics/widgets/lyrics_editor_sheet.dart`                  | Keyboard height shrink change              |
| `ios/Runner.xcodeproj/project.pbxproj`                                  | UUID regeneration from `pod install`       |
| `pubspec.yaml`                                                          | Version bump 1.2.16 → 1.2.17               |
| `web/version.json`                                                      | Version bump 1.2.16 → 1.2.17               |

The Engineer acknowledged all of the above in Deviation #1 and stated "user explicitly directed implementation to proceed." This is noted. However, the out-of-scope changes remain present and uncommitted, and the `lib/main.dart` prohibition is non-negotiable per both the Architect plan and GUARDRAILS §7.

**Note on branch divergence:** `feature/play-store-demo-login` HEAD is identical to `origin/main` (`cdadaf8`). No commits have been made on this branch. All changes are unstaged.

---

## Phase 2 — Documents Resolved

| Document                                                         | Status                 |
| ---------------------------------------------------------------- | ---------------------- |
| `docs/features/feature/play-store-demo-login/ARCHITECT_PLAN.md`  | Found and read in full |
| `docs/features/feature/play-store-demo-login/ENGINEER_REPORT.md` | Found and read in full |

Feature slug in both files: `feature/play-store-demo-login` ✓  
Both files refer to the same feature ✓

---

## Phase 3 — Validation Baseline

**Problem:** Google Play rejected the app; reviewers cannot log in because only magic-link auth exists. No static credentials are available.

**Expected behaviour after fix:** Tapping the BandRoadie logo exactly 7 times on the login screen triggers `signInWithPassword` with demo credentials. `AuthGate` routes to home as normal. No change to the magic-link flow for real users.

**Files expected to change (Architect-approved):**

| File                                      | Type                |
| ----------------------------------------- | ------------------- |
| `lib/app/constants/demo_credentials.dart` | Create              |
| `lib/features/auth/login_screen.dart`     | Modify              |
| `dart_defines.json`                       | Modify              |
| `.env.example`                            | Modify              |
| `run.sh`                                  | Modify (gitignored) |
| `tools/build_android.sh`                  | Modify (gitignored) |
| `tools/build_ios.sh`                      | Modify (gitignored) |
| `tools/build_web.sh`                      | Modify              |

**Files explicitly off-limits:**

- `main.dart`
- New Riverpod providers or notifiers
- `auth_gate.dart`, `auth_state_provider.dart`, `active_band_controller.dart`

**Database impact:** Not applicable — no migrations. Seeding is a manual Tony action.

**Verification plan:** Code-path analysis; manual device testing on all platforms is required (not performed by QA agent). Database seeding is a pre-test prerequisite.

---

## Phase 4 — Implementation Review

### `lib/app/constants/demo_credentials.dart` (new)

```dart
const String kDemoEmail = 'bandroadie2026@gmail.com';
const String kDemoPassword = String.fromEnvironment('DEMO_PASSWORD', defaultValue: '');
```

- Email is a hardcoded constant — public, confirmed safe per Architect plan ✓
- Password uses `String.fromEnvironment` with empty default — no string literal ✓
- File structure and comments match Architect plan exactly, modulo email (see Deviations) ✓

### `lib/features/auth/login_screen.dart`

- `dart:async` import added before `dart:io` ✓
- `../../app/constants/demo_credentials.dart` import added ✓
- `_logoTapCount` and `_logoTapResetTimer` state fields added after `_reduceMotion` ✓
- `_handleLogoTap()` added after `_initHintController()` ✓
  - Increments counter via `setState` ✓
  - Fires on `>= 7` taps, resets counter, calls `_triggerDemoLogin()` ✓
  - Schedules 3-second inactivity reset timer with `mounted` guard ✓
- `_triggerDemoLogin()` added after `_handleLogoTap()` ✓
  - `_isLoading` guard prevents re-entry ✓
  - Sets `_isLoading = true` and clears `_message` before `await` ✓
  - `mounted` guard in both `catch` blocks ✓
  - No `setState` after `async` gap without `mounted` ✓
  - No `_isLoading = false` on success — correct: widget navigates away via AuthGate ✓
- `dispose()` — `_logoTapResetTimer?.cancel()` added before `super.dispose()` ✓
- `_buildLogo()` — wrapped in `GestureDetector(behavior: HitTestBehavior.opaque, onTap: _handleLogoTap)` ✓
- `_buildContentCluster()` — logo `SizedBox` replaced with `Stack` + conditional hint text ✓
  - Hint visible when `_logoTapCount >= 3 && _logoTapCount < 7` ✓
  - Uses `AppColors.primary.withValues(alpha: 0.6)`, fontSize 11 ✓
  - Layout bounds unchanged; `SizedBox` height is still `availableHeight / 2` ✓

### `dart_defines.json`

- `"DEMO_PASSWORD": ""` added as last key ✓
- Value is empty — real password must stay in `.env` only ✓

### `.env.example`

- `DEMO_PASSWORD=your-demo-account-password` added with comment block ✓
- Comment updated to generic wording (omits specific email) — acceptable minor deviation ✓

### `tools/build_web.sh`

- `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"` added after `BUILD_TIMESTAMP` ✓
- `DEMO_PASSWORD` is **not** in `REQUIRED_VARS` ✓
- Formatting matches surrounding `--dart-define` flags ✓

### `run.sh`, `tools/build_android.sh`, `tools/build_ios.sh` (gitignored)

Verified via grep — not visible in `git diff` but confirmed on disk:

| File                                | DEMO_PASSWORD present | In REQUIRED_VARS       |
| ----------------------------------- | --------------------- | ---------------------- |
| `run.sh` (line 41)                  | ✓                     | N/A (no REQUIRED_VARS) |
| `tools/build_android.sh` (line 80)  | ✓                     | No ✓                   |
| `tools/build_ios.sh` (lines 84, 92) | ✓                     | No ✓                   |

`build_ios.sh` correctly applies `--dart-define=DEMO_PASSWORD=...` on both the `flutter build ipa` and `flutter build ios` commands, overriding the empty placeholder in `dart_defines.json` ✓

### Out-of-scope files modified (pre-existing per Engineer report)

**`lib/main.dart`** — imports `KeyboardAwareWrapper` and wraps app with it via `MaterialApp.builder`. This is a functional change. It is **explicitly forbidden** by the Architect plan. Regardless of whether it was pre-existing, it must not be committed as part of this feature.

**`lib/shared/widgets/keyboard_aware_wrapper.dart`** — A new 200-line widget outside Architect scope. No analyzer issues. Pre-existing per Engineer report.

**`lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`** — Adds `MediaQuery.viewInsetsOf(context).bottom` to push sheet above keyboard. Formatting-only change on one line also present. Pre-existing per Engineer report.

**`lib/features/lyrics/widgets/lyrics_editor_sheet.dart`** — Subtracts `keyboardHeight` from slide sheet height. Pre-existing per Engineer report.

**`ios/Runner.xcodeproj/project.pbxproj`** — UUID regeneration from `pod install`. No functional impact. Pre-existing per Engineer report.

**`pubspec.yaml` / `web/version.json`** — Version bump 1.2.16 → 1.2.17. Pre-existing per Engineer report.

---

## Phase 5 — Completeness Check

| Architect Task                                                | Status                                     |
| ------------------------------------------------------------- | ------------------------------------------ |
| Task 1 — Create `demo_credentials.dart`                       | ✓ Complete                                 |
| Task 2a — `dart:async` import                                 | ✓ Complete                                 |
| Task 2b — `demo_credentials.dart` import                      | ✓ Complete                                 |
| Task 2c — State variables                                     | ✓ Complete                                 |
| Task 2d — `dispose()` cleanup                                 | ✓ Complete                                 |
| Task 2e — `_handleLogoTap()`                                  | ✓ Complete                                 |
| Task 2f — `_triggerDemoLogin()`                               | ✓ Complete                                 |
| Task 2g — `_buildLogo()` GestureDetector                      | ✓ Complete                                 |
| Task 2h — Hint text in `_buildContentCluster()`               | ✓ Complete                                 |
| Task 3 — `dart_defines.json` placeholder                      | ✓ Complete                                 |
| Task 4 — `.env.example` documentation                         | ✓ Complete                                 |
| Task 5 — `run.sh` define                                      | ✓ Complete (gitignored — verified locally) |
| Task 6 — `build_android.sh` / `build_ios.sh` / `build_web.sh` | ✓ Complete                                 |

No skipped or partial tasks. All edge cases specified by the Architect (auto-reset timer, `mounted` guard, `DEMO_PASSWORD` not in `REQUIRED_VARS`) are correctly handled.

---

## Phase 6 — Behavior Verification

**Validation method:** Code-path analysis only. Runtime behaviour on device was not exercised by QA.

### Feature behaviour (code-path confirmed)

| Behaviour                                                                | Status                                                        |
| ------------------------------------------------------------------------ | ------------------------------------------------------------- |
| 7 taps triggers `_triggerDemoLogin()`                                    | ✓ Confirmed in code                                           |
| Hint text appears at taps 3–6                                            | ✓ Confirmed in code                                           |
| Hint disappears after tap 7 (`_logoTapCount` resets to 0 via `setState`) | ✓ Confirmed in code                                           |
| 3-second inactivity resets counter                                       | ✓ Confirmed in code                                           |
| `_isLoading` spinner activates on tap 7                                  | ✓ Confirmed in code (first `setState` in `_triggerDemoLogin`) |
| Success: AuthGate handles routing via `authStateProvider` stream         | ✓ Confirmed in code (no routing changes needed)               |
| Failure: error shown in `_message`, `_isLoading` reset                   | ✓ Confirmed in code                                           |
| Password is `String.fromEnvironment`, never a literal                    | ✓ Confirmed in code                                           |
| Empty `kDemoPassword` causes `AuthException`, not a crash                | ✓ Confirmed in code (caught and surfaced as `_message`)       |

### Extra behaviour outside Architect scope

None introduced by the feature implementation. The `KeyboardAwareWrapper` change in `main.dart` is a pre-existing separate piece of work, not a product of this feature.

---

## Phase 7 — Regression Check

**Regression risk: LOW** (feature-only change; no structural modifications)

| System                                 | Impact              | Regression assessment                                                                                                                                               |
| -------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Auth / Session                         | Affected            | New `signInWithPassword` path added. Existing `signInWithOtp` path is **untouched**. `AuthGate` receives the same `signedIn` event for both paths. No regression. ✓ |
| Routing                                | Unaffected          | `AuthGate` and `AppShell` unchanged. ✓                                                                                                                              |
| Gigs / Rehearsals / Setlists / Catalog | Unaffected          | No changes. ✓                                                                                                                                                       |
| Members / RBAC                         | Unaffected          | Demo user uses existing RLS. ✓                                                                                                                                      |
| Push Notifications                     | Unaffected          | Token registration in `AuthGate` is path-agnostic. ✓                                                                                                                |
| Build / CI                             | Affected (low risk) | `DEMO_PASSWORD` is optional; build succeeds without it. `kDemoPassword` is empty string, demo login fails with `AuthException`. No build breakage. ✓                |
| Initialization order                   | Unaffected          | `main.dart` initialization sequence is unchanged (the `main.dart` modification is pre-existing and does not reorder initialization). ✓                              |
| Controller / FocusNode disposal        | Unaffected          | `_logoTapResetTimer?.cancel()` correctly added to `dispose()`. No new controllers. ✓                                                                                |
| `setState` after async gap             | Safe                | `mounted` guards present in all `catch` blocks. ✓                                                                                                                   |

**Special concern — `main.dart` `KeyboardAwareWrapper`:** The pre-existing `main.dart` change wraps the app with a `WidgetsBindingObserver`. This is outside QA scope for this feature, but if committed concurrently it introduces a non-trivial global widget into the tree. This work requires its own QA pass.

---

## Phase 8 — Database Safety

**Database safety: not applicable.**

No migrations. No RLS changes. No RPC changes. The Architect plan explicitly classified database impact as "Not applicable." Seeding of the demo account is a manual Tony prerequisite.

---

## Phase 9 — Baseline Validation

```
flutter analyze
Result: No issues found! (ran in 4.3s)
```

- 0 errors ✓
- 0 warnings ✓
- 0 new warnings introduced by this feature's changes ✓

Tests: Not run. No existing tests cover `login_screen.dart`. Architect plan did not require new tests. Consistent with Engineer report.

---

## Phase 10 — Diff Safety Review

| Check                                    | Result                                                                                                     |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Secrets or API keys in diff              | None. `dart_defines.json` has `"DEMO_PASSWORD": ""` (empty) ✓                                              |
| `kDemoPassword` — no literal password    | Uses `String.fromEnvironment` only ✓                                                                       |
| `kDemoEmail` — hardcoded public email    | Expected per Architect plan; email is public ✓                                                             |
| Debug artifacts (print, TODO, HACK)      | No new debug artifacts introduced by this feature ✓                                                        |
| Pre-existing `debugPrint` calls          | Present in `login_screen.dart` at lines 106, 388, 396 — **pre-existing**, not introduced by this feature ✓ |
| Test scaffolding in production code      | None ✓                                                                                                     |
| Accidental file deletions                | None ✓                                                                                                     |
| `.env` file committed                    | No — `.env` is gitignored ✓                                                                                |
| Real `DEMO_PASSWORD` in any tracked file | Not found ✓                                                                                                |

**Informational — local `.env` formatting issue:** The `.env` file on disk shows `FIREBASE_MEASUREMENT_ID=G-QFC8JXHKDCDEMO_EMAIL=bandroadie2026@gmail.com` concatenated on one line (missing newline from a prior `echo` append). This is in a gitignored local file; it will not be committed. However, it means `FIREBASE_MEASUREMENT_ID` would be read with an incorrect value (`G-QFC8JXHKDCDEMO_EMAIL=bandroadie2026@gmail.com`) when scripts source `.env`. Tony should manually fix this line in `.env`.

---

## Deviations From Architect Plan

| #   | Deviation                                                              | Approved                                                                                                                     |
| --- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| 1   | Working tree contains pre-existing out-of-scope modifications          | Noted by Engineer; user-directed continuation. Does not excuse `main.dart` prohibition.                                      |
| 2   | `kDemoEmail` is `bandroadie2026@gmail.com` (not `demo@bandroadie.com`) | Yes — user instruction. Engineer report explicitly documents this.                                                           |
| 3   | `gen_dart_defines.sh` not updated                                      | Engineer flagged as follow-up ticket. Acceptable — `build_ios.sh` passes `--dart-define` explicitly, which takes precedence. |

---

## Required Changes Before Commit

The following must be resolved before this feature can be committed:

### RC-1 — Isolate `lib/main.dart` change (BLOCKING)

`lib/main.dart` is **explicitly forbidden** by the Architect plan. The `KeyboardAwareWrapper` modification must be extracted to its own branch and committed separately. This feature commit must not touch `main.dart`.

### RC-2 — Isolate all other out-of-scope changes (BLOCKING)

The following must be committed separately (or stashed) before the feature commit:

- `lib/shared/widgets/keyboard_aware_wrapper.dart` (new file)
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`
- `lib/features/lyrics/widgets/lyrics_editor_sheet.dart`
- `ios/Runner.xcodeproj/project.pbxproj`
- `pubspec.yaml`
- `web/version.json`

### RC-3 — Follow-up: Fix `.env` newline issue (NON-BLOCKING)

Manually correct the `FIREBASE_MEASUREMENT_ID` line in `.env` to ensure `DEMO_PASSWORD` is on its own line.

### RC-4 — Follow-up: Update `gen_dart_defines.sh` (NON-BLOCKING)

Add `DEMO_PASSWORD` to `gen_dart_defines.sh` so `dart_defines.json` stays in sync when iOS builds regenerate it.

---

## What Is Correct and Does Not Need to Change

All feature-implementation files are correct as written:

- `lib/app/constants/demo_credentials.dart` ✓
- All changes to `lib/features/auth/login_screen.dart` ✓
- `dart_defines.json` ✓
- `.env.example` ✓
- `tools/build_web.sh` ✓
- `run.sh` (gitignored) ✓
- `tools/build_android.sh` (gitignored) ✓
- `tools/build_ios.sh` (gitignored) ✓

Once RC-1 and RC-2 are resolved and the working tree contains only the approved feature files, the feature is ready to commit.

---

## Pending Pre-Test Prerequisites (Tony action)

These are not Engineer defects — they are manual seeding steps required before the feature can be verified at runtime:

1. Create `bandroadie2026@gmail.com` in Supabase Auth as email + password account with confirmed email
2. Create a `users` row for the demo user with non-null `first_name` and `last_name`
3. Add the demo user as a member of The Banana Stand (`band_id: 9187f897-1731-4337-bbd3-4f80afbe88ec`)
4. Set `DEMO_PASSWORD` to the correct value in `.env` (currently set to `banana-stand-demo` — verify this matches the Supabase Auth account password)
5. Fix the `.env` newline issue (RC-3 above)
