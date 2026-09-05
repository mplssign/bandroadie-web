# ENGINEER_REPORT — Interactive Demo Band Experience

## Feature Slug

`interactive-demo-band-experience`

## Feature Title

Public, self-resetting interactive demo bands ("Check Out the Demo Band")

## Cycle Number

2

## Goal

Replace the hidden 7-tap easter-egg demo login (shared `hello@bandroadie.com` account) with a
visible "Check Out the Demo Band" button that provisions each visitor a private, fully-populated
anonymous-auth clone of two template bands, manages session lifetime via heartbeat + server-side
sweep, and retires the `DEMO_PASSWORD` build-secret pipeline entirely.

---

## Architect Tasks Completed

| #   | Task                                                                                                                                                                                                                                                                                                                                                                         | Status       |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------ |
| 1   | Author `20260904120000_demo_bands_schema.sql` — `demo_sessions` table + RLS, `bands` columns (`is_demo_template`, `is_demo_clone`, `demo_session_id`), template-write-guard trigger applied to 8 tables                                                                                                                                                                      | **Complete** |
| 2   | Author `20260904120001_seed_demo_templates.sql` — 13 dummy auth.users + public.users, 2 template bands (The Banana Stand / Figrin D'an and the Modal Nodes), 6 band_members each, 16 songs each, 5 setlists each, setlist_songs, 7 gigs each, gig_dates, venues, contacts, rehearsals, financial_entries; deterministic literal UUIDs only                                   | **Complete** |
| 3   | Author `20260904120002_cleanup_old_demo_account.sql` — DO-block guard raising if templates are absent, then deletes `hello@bandroadie.com` (id `4b8b4b6c-...`) and old bands `e89bea44-...` / `f9184316-...` / `fc379e2d-...`                                                                                                                                                | **Complete** |
| 4   | Author `20260904120003_provision_demo_session_rpc.sql` — `provision_demo_session()` SECURITY DEFINER, idempotent, single transaction, `REVOKE FROM PUBLIC/anon` + `GRANT EXECUTE TO authenticated`                                                                                                                                                                           | **Complete** |
| 5   | Author `20260904120004_exit_and_heartbeat_demo_session_rpc.sql` — `exit_demo_session()` + `heartbeat_demo_session()`, same grant pattern                                                                                                                                                                                                                                     | **Complete** |
| 6   | Author `20260904120005_cleanup_demo_sessions_cron.sql` — `cleanup_expired_demo_sessions()` + pg_cron schedule every 5 min, `CREATE EXTENSION IF NOT EXISTS pg_cron`                                                                                                                                                                                                          | **Complete** |
| 7   | Create `lib/features/auth/demo_session_service.dart` — `DemoSessionService` with static `provisionAndEnter(WidgetRef)` / `exit(WidgetRef)` / `heartbeat()` wrapping the three RPCs; `DemoSessionException`; uses `banana_stand_band_id` key and `activeBandProvider.notifier.loadAndSelectBand()`                                                                            | **Complete** |
| 8   | Edit `lib/features/auth/login_screen.dart` — remove 7-tap easter egg (`_logoTapCount`, `_logoTapResetTimer`, `_handleLogoTap`, `_triggerDemoLogin`, GestureDetector on logo, tap-count hint); convert to `ConsumerStatefulWidget`/`ConsumerState`; add visible "Check Out the Demo Band" `AppButton` (text variant) with `_isDemoLoading` spinner + brand-voice inline error | **Complete** |
| 9   | Delete `lib/app/constants/demo_credentials.dart`                                                                                                                                                                                                                                                                                                                             | **Complete** |
| 10  | Edit `lib/features/bands/active_band_controller.dart` — add `_invalidateBandScopedProviders()` invalidating `membersProvider` / `contactsProvider` / `venuesProvider`; call from `selectBand`, `loadAndSelectBand`, `refreshBands` (see Deviations §1–2)                                                                                                                     | **Complete** |
| 11  | Edit `lib/features/home/widgets/side_drawer.dart` + `lib/features/shell/app_shell.dart` — "Exit Demo" drawer item above Log Out via `onExitDemoTap` callback; wired in `app_shell.dart` only when `Supabase.instance.client.auth.currentUser?.isAnonymous == true`, calling `DemoSessionService.exit(ref)` with brand-voice error snackbar on failure                        | **Complete** |
| 12  | Edit `lib/features/auth/auth_gate.dart` — `_lastDemoHeartbeatAt` field + heartbeat branch inside existing `_startSessionSyncTimer` callback; calls `unawaited(DemoSessionService.heartbeat())` at most every 60 s while session user is anonymous; no new timer                                                                                                              | **Complete** |
| 13  | Remove `DEMO_PASSWORD` from `run.sh`, `dart_defines.json`, `tools/gen_dart_defines.sh`, `tools/build_android.sh`, `tools/build_ios.sh`, `tools/build_web.sh`, `tools/build_mobile_release.sh`, `tools/deploy_web.sh`, `.env.example`; grep confirms zero remaining references in `lib/` or any build-config file                                                             | **Complete** |
| 14  | Write tests: `test/features/auth/login_screen_demo_button_test.dart` (renders "Check Out the Demo Band"; asserts retired easter-egg hint copy is absent; offline); `test/features/bands/active_band_controller_invalidation_test.dart` (primes members/contacts/venues providers, calls `selectBand()`, asserts each provider re-built to initial state)                     | **Complete** |

---

## Files Created

| File                                                                         | Purpose                                                                   | Lines |
| ---------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ----- |
| `supabase/migrations/20260904120000_demo_bands_schema.sql`                   | Schema: `demo_sessions` table + RLS, `bands` columns, write-guard trigger | 136   |
| `supabase/migrations/20260904120001_seed_demo_templates.sql`                 | Seed both template bands + all content (~46 KB)                           | 616   |
| `supabase/migrations/20260904120002_cleanup_old_demo_account.sql`            | Retire `hello@bandroadie.com` + old bands                                 | 49    |
| `supabase/migrations/20260904120003_provision_demo_session_rpc.sql`          | `provision_demo_session()` RPC                                            | 335   |
| `supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql` | `exit_demo_session()` + `heartbeat_demo_session()` RPCs                   | 55    |
| `supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql`          | Sweep function + pg_cron schedule                                         | 36    |
| `lib/features/auth/demo_session_service.dart`                                | Client wrapper for the three RPCs and provisioning flow                   | 46    |
| `test/features/auth/login_screen_demo_button_test.dart`                      | Offline widget test: demo button visible, easter-egg copy absent          | —     |
| `test/features/bands/active_band_controller_invalidation_test.dart`          | Unit test: band-switch invalidation of members/contacts/venues            | —     |
| `docs/features/interactive-demo-band-experience/ENGINEER_REPORT.md`          | This document                                                             | —     |

## Files Modified

| File                                             | Change                                                                                                  |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `lib/features/auth/login_screen.dart`            | Removed 7-tap easter egg; converted to `ConsumerStatefulWidget`; added "Check Out the Demo Band" button |
| `lib/features/bands/active_band_controller.dart` | Added `_invalidateBandScopedProviders()` called from `selectBand`, `loadAndSelectBand`, `refreshBands`  |
| `lib/features/home/widgets/side_drawer.dart`     | Added `onExitDemoTap` callback prop; conditional "Exit Demo" item above Log Out                         |
| `lib/features/shell/app_shell.dart`              | Wires `onExitDemoTap` into drawer when user `isAnonymous`                                               |
| `lib/features/auth/auth_gate.dart`               | Added `_lastDemoHeartbeatAt` field and heartbeat branch inside existing sync timer                      |
| `run.sh`                                         | Removed `--dart-define=DEMO_PASSWORD` line                                                              |
| `dart_defines.json`                              | Removed `DEMO_PASSWORD` key                                                                             |
| `tools/gen_dart_defines.sh`                      | Removed `DEMO_PASSWORD` line from heredoc                                                               |
| `tools/build_android.sh`                         | Removed `--dart-define=DEMO_PASSWORD` from `DART_DEFINES`                                               |
| `tools/build_web.sh`                             | Removed `--dart-define=DEMO_PASSWORD`                                                                   |
| `tools/build_mobile_release.sh`                  | Removed `DEMO_PASSWORD` validation block, `BUILD_ARGS` reference, and artifact-verification grep        |
| `tools/deploy_web.sh`                            | Removed `DEMO_PASSWORD` guard and `--dart-define=DEMO_PASSWORD` on web build                            |
| `.env.example`                                   | Removed `# ── Demo Account (Play Store App Access) ──` block and `DEMO_PASSWORD=` line                  |

Note: `tools/build_ios.sh` is listed in the plan but showed no `DEMO_PASSWORD` references at
implementation time (the plan cited a prior ARCHITECT_PLAN as evidence; the file had no such
reference in the current working tree). No change was needed and none was made.

## Files Deleted

| File                                      | Reason                            |
| ----------------------------------------- | --------------------------------- |
| `lib/app/constants/demo_credentials.dart` | Password-based demo login retired |

## Files Outside the Plan Touched

**None.**

---

## Analyzer Results

`flutter analyze` (full project):

- **Errors:** 0
- **New warnings introduced by this feature:** 0
- Pre-existing info-level lints: 547 (all pre-existing; no file touched by this feature
  introduced new ones). The single pre-existing warning is an unrecognised lint rule in
  `analysis_options.yaml`; that file was not touched by this feature.

`dart fix --dry-run` reviewed; no applicable suggestions within the plan's file list.

## Test Results

| Test file                                                           | Result   |
| ------------------------------------------------------------------- | -------- |
| `test/features/auth/login_screen_demo_button_test.dart`             | **PASS** |
| `test/features/bands/active_band_controller_invalidation_test.dart` | **PASS** |

---

## Code Efficiency / Bloat Check

- **`demo_session_service.dart` (46 lines):** Three static methods + one exception class. No
  Notifier, no provider — intentionally stateless as the plan specifies. Under target.
- **`active_band_controller.dart` (530 lines):** Exceeds the 500-line target by 30 lines. The
  file was already over the guideline before this feature; the net addition is 8 lines
  (`_invalidateBandScopedProviders` helper + three call sites). Pre-existing overage is not
  attributable to this feature; no refactoring done (out of scope).
- **`side_drawer.dart` (1125 lines):** Already a large file; this feature added ~30 lines for
  the `onExitDemoTap` callback threading and the conditional Exit Demo item. No new structural
  widget classes introduced; the drawer item reuses existing `DrawerNavItem` patterns.
- **No new helpers, extensions, or utils created.** Searched `lib/` for an existing stateless
  RPC-wrapper pattern before creating `demo_session_service.dart`; closest analog is
  `data_backup_service.dart`, which is domain-specific to settings/restore. Finding: no
  existing helper for a stateless anonymous-auth provisioning wrapper. Reuse not applicable.
- **No AI-shaped code:** no unused imports, no dead fields, no `debugPrint` left in diff, no
  `TODO`/`FIXME` comments. `_invalidateBandScopedProviders` is called from three sites —
  justified as a named helper (not inlined) to keep the three call sites DRY.

---

## Verification (Manual Steps Performed)

- Confirmed `lib/app/constants/demo_credentials.dart` deleted (absent from working tree).
- Confirmed zero `DEMO_PASSWORD` matches across `lib/`, `tools/`, `run.sh`,
  `dart_defines.json`, `.env.example` via `grep -rn DEMO_PASSWORD`.
- Confirmed `login_screen.dart` has `ConsumerStatefulWidget`, `_isDemoLoading`, and
  `'Check Out the Demo Band'` label; no remaining `_logoTapCount`/`_handleLogoTap` references.
- Confirmed `active_band_controller.dart` has `_invalidateBandScopedProviders()` called at
  `selectBand`, `loadAndSelectBand`, and `refreshBands`.
- Confirmed `side_drawer.dart` has `onExitDemoTap` callback and "Exit Demo" label.
- Confirmed `app_shell.dart` passes `onExitDemoTap` gated on `isAnonymous == true`.
- Confirmed `auth_gate.dart` has `_lastDemoHeartbeatAt` field and 60-second throttled heartbeat
  branch inside the existing `_startSessionSyncTimer` callback.
- All six migration files present in `supabase/migrations/` with correct timestamps.
- Both test files present in `test/features/auth/` and `test/features/bands/` and pass.

---

## Deviations From Plan

### 1. Invalidation set is `membersProvider` / `contactsProvider` / `venuesProvider` only

The plan asked the Engineer to grep `features/{gigs,rehearsals,setlists,members,contacts,
settings}/*_controller.dart` and invalidate exactly the band-scoped providers that could bleed.
After grepping, the correct minimal set is those three providers. The others (gig, rehearsal,
setlists, financials, calendar, bandFullState) already call `ref.watch(activeBandIdProvider)` in
their `build()` method and self-import `active_band_controller.dart` — meaning Riverpod already
invalidates them reactively on band switch, and adding explicit `ref.invalidate` calls from this
file would create a circular import. The three invalidated providers do not watch
`activeBandIdProvider` reactively and therefore required the explicit call. This is the correct
minimal fix, not a shortcut.

### 2. `selectBandById` covered transitively, not directly

The plan listed `selectBandById` alongside `selectBand`, `loadAndSelectBand`, and `refreshBands`
as sites needing invalidation. `selectBandById` delegates to `selectBand` unconditionally, so
invalidation fires through the delegate. No direct call was added to `selectBandById`; adding
one would be redundant double-invalidation on the same tick. Verified by reading the method body.

### 3. Implementation chunked by Manager across focused sub-tasks

Migrations were authored first, then client code, then build-config, then tests — across
separate Engineer invocations. This has no effect on the resulting diff or behaviour; recorded
for traceability.

---

## Migration Application Notes

**Migrations are authored only — they have NOT been applied. Tony must apply them manually in
numeric order:**

1. `20260904120000_demo_bands_schema.sql`
2. `20260904120001_seed_demo_templates.sql`
3. `20260904120002_cleanup_old_demo_account.sql` — **destructive**: deletes
   `hello@bandroadie.com` and the three old demo bands. Do not apply until
   `20260904120001` has applied cleanly and the template bands exist.
4. `20260904120003_provision_demo_session_rpc.sql`
5. `20260904120004_exit_and_heartbeat_demo_session_rpc.sql`
6. `20260904120005_cleanup_demo_sessions_cron.sql` — **pg_cron caveat**: contains
   `CREATE EXTENSION IF NOT EXISTS pg_cron`. If pg_cron cannot be enabled on this Supabase
   project's tier, this migration will fail at that statement. In that case, pause at migration 5,
   do not apply 6, and raise a follow-up feature for an Edge Function fallback. Orphaned anonymous
   `auth.users` rows will accumulate but cause no functional harm; accepted as v1 tech debt.

---

## Blockers Encountered

None.

---

## Cycle 2 Changes (QA REQUIRES CHANGES — addressed)

### C1 — Fixed: wrong `ORDER BY` in `provision_demo_session` RPC

`20260904120003_provision_demo_session_rpc.sql` template-band loop used `ORDER BY name`, which
sortes "Figrin D'an and the Modal Nodes" (F) before "The Banana Stand" (T), so `v_band_idx = 1`
was the Modal Nodes clone — making `banana_stand_band_id` return the wrong band and defaulting
every visitor into the wrong band.

Fix: changed to `ORDER BY id ASC`. Template UUIDs are deterministic: Banana Stand =
`00000000-0000-4000-8100-000000000001`, Modal Nodes = `...000000000002`. Ascending id order
makes the first loop iteration the Banana Stand, so `v_bs_band_id` (and therefore the returned
`banana_stand_band_id` JSON key) is now correct. Comment updated to reflect the id-based ordering.

### W1 — Reverted: out-of-scope `activeBand: null` / `imageUrl: null` removals

Restored `activeBand: null` in all four `copyWith(clearActiveBand: true, ...)` call sites
(refreshBands×2, loadAndSelectBand×1, and the refreshBands empty-list path) and
`imageUrl: null` in `DraftBandNotifier.updateAvatarColor`. The intended
`_invalidateBandScopedProviders()` method and its three call sites are intact.

### W2 — Reverted: `Container → ColoredBox` conversions in scrim subtrees

Restored all four `ColoredBox` instances back to `Container` in `_DrawerOverlayState` and
`_DrawerOverlayContentState`. The intended `onExitDemoTap` callback plumbing and Exit Demo item
are intact.

### W3 — Reverted: `NativeAppBanner` default-args and missing `variant`

- `app_shell.dart`: restored `NativeAppBanner` explicit constructor args
  (`delay`, `position`, `hideOnAuthPages`) and removed `const` from the outer `Positioned`.
- `login_screen.dart`: restored `variant: AppButtonVariant.primary` on the magic-link button.
  The new `_buildDemoButton()` / `_enterDemo()` and "Check Out the Demo Band" button are intact.

### Analyzer / tests (Cycle 2)

- `flutter analyze` on changed files: 0 errors, 0 warnings; 12 info-level lints (all pre-existing
  on `main` — the redundant-arg lints are the original reason the Cycle 1 engineer removed them;
  they are intentionally restored to match main).
- `flutter test` on the two required test files: **5/5 pass**.

---

## Ready For QA

**Yes**
