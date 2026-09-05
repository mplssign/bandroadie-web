# QA REPORT — Interactive Demo Band Experience

## Feature Slug

`interactive-demo-band-experience`

## Feature Title

Public, self-resetting interactive demo bands ("Check Out the Demo Band")

## Cycle Number

2

## Final Verdict

**APPROVED**

All four Cycle 1 findings (C1 ordering bug + W1/W2/W3 out-of-scope changes) are correctly
resolved. No new issues found. Tier-2 SQL execution remains deferred per the known infra
blocker — expected and not a blocker for approval.

---

## Validation Summary

| Area                                                                                          | Result   | Method                                                                                                |
| --------------------------------------------------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------- |
| Branch / working tree                                                                         | PASS     | `git branch --show-current`, `git status --short`                                                     |
| Plan ↔ Engineer report slug match                                                             | PASS     | Reviewed in code                                                                                      |
| C1 — provision RPC band ordering (ORDER BY id ASC)                                            | **PASS** | Reviewed-in-code; template UUIDs confirmed against seed migration                                     |
| W1 — active_band_controller out-of-scope changes reverted                                     | **PASS** | `git diff --numstat` (+13/0, no deletions); `activeBand: null` and `imageUrl: null` confirmed in code |
| W2 — side_drawer Container restored (ColoredBox reverted)                                     | **PASS** | `grep -n ColoredBox` — zero; `git diff --numstat` (+25/0, no deletions)                               |
| W3 — app_shell NativeAppBanner explicit args + login_screen AppButtonVariant.primary restored | **PASS** | Read in code at app_shell.dart:199–202, login_screen.dart:636                                         |
| Easter egg / DEMO_PASSWORD retirement                                                         | PASS     | `grep -rn` — zero matches in lib/, tools/, run.sh, dart_defines.json, .env.example                    |
| Login screen demo button                                                                      | PASS     | Reviewed-in-code + tests                                                                              |
| Exit Demo drawer item + gating                                                                | PASS     | Reviewed-in-code                                                                                      |
| Auth-gate heartbeat (no new timer)                                                            | PASS     | Reviewed-in-code                                                                                      |
| Band-switch invalidation fix                                                                  | PASS     | Reviewed-in-code; excluded providers spot-checked                                                     |
| Demo session service                                                                          | PASS     | Reviewed-in-code                                                                                      |
| Seed content spec compliance                                                                  | PASS     | Reviewed-in-code                                                                                      |
| Off-limits files                                                                              | PASS     | `git diff --name-only` — 11 files, all in-plan                                                        |
| flutter analyze (diff files)                                                                  | PASS     | Actually-exercised — 24 info issues, all pre-existing in main; 0 new at any severity                  |
| New tests                                                                                     | PASS     | Actually-exercised: `flutter test` — 5/5 passed                                                       |
| DB safety Tier-1                                                                              | PASS     | Manual SQL review (unchanged from C1 except C1 ordering fix)                                          |
| DB safety Tier-2                                                                              | DEFERRED | Infra blocker — see note below                                                                        |
| Secrets / debug artifacts                                                                     | PASS     | `grep -rn` — zero hits; no new debugPrint in diff hunks                                               |

---

## Architect Scope Review

**Slugs match:** ARCHITECT_PLAN.md (`feature/interactive-demo-band-experience`) ↔
ENGINEER_REPORT.md (`interactive-demo-band-experience`) ↔ branch name
(`feature/interactive-demo-band-experience`). ✓

All 14 Architect tasks reported complete in the Cycle 2 Engineer Report.

---

## Completeness Check

All 14 tasks verified; no partial implementations. Status unchanged from Cycle 1 except
Task 4 which now fully passes.

| Task                                                         | Verified | Notes                                                                           |
| ------------------------------------------------------------ | -------- | ------------------------------------------------------------------------------- |
| 1 — `20260904120000_demo_bands_schema.sql`                   | ✓        | Schema reviewed (C1 pass, unchanged)                                            |
| 2 — `20260904120001_seed_demo_templates.sql`                 | ✓        | Banana Stand UUID `...8100-000000000001` confirmed in seed                      |
| 3 — `20260904120002_cleanup_old_demo_account.sql`            | ✓        | DO-block guard confirmed (C1 pass, unchanged)                                   |
| 4 — `20260904120003_provision_demo_session_rpc.sql`          | ✓        | **C1 ordering bug fixed** — see Behavior Verification                           |
| 5 — `20260904120004_exit_and_heartbeat_demo_session_rpc.sql` | ✓        | Both functions reviewed (C1 pass, unchanged)                                    |
| 6 — `20260904120005_cleanup_demo_sessions_cron.sql`          | ✓        | pg_cron caveat noted (C1 pass, unchanged)                                       |
| 7 — `demo_session_service.dart`                              | ✓        | 46 lines reviewed (C1 pass, unchanged)                                          |
| 8 — `login_screen.dart` easter-egg removal + demo button     | ✓        | Dead code removed; demo button with text variant confirmed                      |
| 9 — Delete `demo_credentials.dart`                           | ✓        | Absent from working tree; zero import refs remain                               |
| 10 — `active_band_controller.dart` invalidation              | ✓        | `_invalidateBandScopedProviders()` + call sites confirmed; W1 reverts confirmed |
| 11 — `side_drawer.dart` / `app_shell.dart` Exit Demo wiring  | ✓        | Present and gated; W2/W3 reverts confirmed                                      |
| 12 — `auth_gate.dart` heartbeat branch                       | ✓        | `_lastDemoHeartbeatAt` + reused timer confirmed (C1 pass, unchanged)            |
| 13 — DEMO_PASSWORD retirement from build tools               | ✓        | `grep -rn DEMO_PASSWORD` → zero matches across all paths                        |
| 14 — New tests                                               | ✓        | 5/5 tests passing                                                               |

---

## Behavior Verification

All behavior verification is **reviewed-in-code** (code-path analysis) unless otherwise noted.

### C1 Resolution — provision_demo_session band ordering

**Cycle 1 defect:** `ORDER BY name` caused Figrin D'an (F) to iterate first (v_band_idx=1),
so `v_bs_band_id` (returned as `banana_stand_band_id`) contained the Modal Nodes clone.

**Cycle 2 fix (reviewed-in-code):**

- `provision_demo_session_rpc.sql` now uses `ORDER BY id ASC` on the template-band cursor.
- Banana Stand UUID: `00000000-0000-4000-8100-000000000001` (confirmed from seed migration
  lines 19–20 and grep output).
- Modal Nodes UUID: `00000000-0000-4000-8100-000000000002`.
- `ORDER BY id ASC` → Banana Stand iterates first (v_band_idx=1) → stored in `v_bs_band_id`
  → returned as `'banana_stand_band_id'` ✓
- Modal Nodes iterates second (v_band_idx=2) → stored in `v_mn_band_id`
  → returned as `'modal_nodes_band_id'` ✓
- Idempotency path: `clone_band_ids = ARRAY[v_bs_band_id, v_mn_band_id]` →
  RETURN uses `clone_band_ids[1]` for `banana_stand_band_id` and `clone_band_ids[2]` for
  `modal_nodes_band_id` — consistent with primary path ✓
- No other name-ordering assumption remains in the RPC ✓
- `DemoSessionService.provisionAndEnter` passes `result['banana_stand_band_id']` to
  `loadAndSelectBand()` → visitor now correctly defaults into The Banana Stand ✓

### W1 Resolution — active_band_controller.dart

- `activeBand: null` explicitly passed alongside `clearActiveBand: true` in all four call
  sites: `loadUserBands` null-result path, `loadUserBands` empty-bands path,
  `loadAndSelectBand` empty-bands path, `refreshBands` empty-bands path (all reviewed-in-code).
- `imageUrl: null` present in `DraftBandNotifier.updateAvatarColor()` Band constructor
  (reviewed-in-code at line 93).
- `_invalidateBandScopedProviders()` definition confirmed (invalidates `membersProvider`,
  `contactsProvider`, `venuesProvider`); call sites in `selectBand` (direct),
  `loadAndSelectBand` (via `Future.microtask`), `refreshBands` (direct) all confirmed.
- `git diff --numstat`: +13/0 — zero deletions from main confirms no out-of-scope removals.

### W2 Resolution — side_drawer.dart

- `grep -n ColoredBox side_drawer.dart` → zero results (reviewed with terminal).
- `build()` returns `Container(...)` at line 239; scrim containers at lines 854/1065 use
  `Container(color: Colors.transparent)` (pre-existing main state, pre-existing info lint).
- `onExitDemoTap: VoidCallback?` prop present; Exit Demo item rendered conditionally above
  Log Out when callback is non-null ✓
- `git diff --numstat`: +25/0 — zero deletions from main.

### W3 Resolution — app_shell.dart + login_screen.dart

- `app_shell.dart` line 199: `NativeAppBanner` with explicit args `delay: Duration(seconds: 4)`,
  `position: BannerPosition.top`, `hideOnAuthPages: true` (restored, reviewed-in-code) ✓
- `login_screen.dart` line 636: `variant: AppButtonVariant.primary` on "Email Login Link"
  button (restored, confirmed by grep and code read) ✓
- `login_screen.dart` line 650: `variant: AppButtonVariant.text` on "Check Out the Demo Band"
  button ✓
- `onExitDemoTap` wired and gated on `currentUser?.isAnonymous == true` ✓
- `git diff --numstat` for app_shell.dart: +18/0 — zero deletions from main.

---

## Regression Check

All regressions confirmed LOW from Cycle 1; no new risk introduced by C2 changes.

| System                          | Risk | Notes                                                  |
| ------------------------------- | ---- | ------------------------------------------------------ |
| Provision RPC (ordering)        | LOW  | C1 defect resolved; ordering deterministic by UUID ✓   |
| Auth / anonymous sign-in        | LOW  | Unchanged from C1 ✓                                    |
| AuthGate timer                  | LOW  | Unchanged from C1 ✓                                    |
| Login screen widget lifecycle   | LOW  | Unchanged from C1 ✓                                    |
| Band-switch invalidation        | LOW  | Unchanged from C1 ✓                                    |
| Side drawer / app_shell         | LOW  | W2/W3 reverts restore original behavior; no new risk ✓ |
| Real users (non-anonymous)      | LOW  | All demo paths gated on `isAnonymous == true` ✓        |
| Platform parity (web vs native) | LOW  | Flutter layer only; no platform-specific code added ✓  |
| Setlist mega-file               | LOW  | Not touched ✓                                          |

---

## Database Safety

**Tier-2 (real execution) checks: DEFERRED.** Managed Supabase branch creation is blocked
project-wide at migration 073. No migrations were executed in any environment. Expected per
the Manager brief — not a QA failure. Tony must verify at manual apply time:

1. All 6 migrations apply cleanly in order.
2. `SELECT has_function_privilege('authenticated', 'public.provision_demo_session()', 'EXECUTE')` → `true`.
3. `SELECT has_function_privilege('anon', 'public.provision_demo_session()', 'EXECUTE')` → `false`.
4. Same `has_function_privilege` checks for `exit_demo_session`, `heartbeat_demo_session`, `cleanup_expired_demo_sessions`.
5. pg_cron is available on this Supabase project tier (migration 005 will error at `CREATE EXTENSION` if not).

**Tier-1 SQL review (unchanged from Cycle 1 except Migration 003):**

All Tier-1 findings from Cycle 1 carry forward as PASS. Migration 003 re-reviewed:

- `SECURITY DEFINER` ✓ | `SET search_path = public` ✓
- `REVOKE ALL ... FROM PUBLIC, anon` + `GRANT EXECUTE TO authenticated` at end of file ✓
- Anonymous caller guard ✓ | Idempotency check ✓ | Single transaction ✓
- `ORDER BY id ASC` correctly maps Banana Stand (…0001) to idx=1 → `banana_stand_band_id`,
  Modal Nodes (…0002) to idx=2 → `modal_nodes_band_id` ✓
- Idempotency RETURN consistent with primary path ✓
- No remaining name-ordering assumption ✓

---

## Analyzer Results

Actually-exercised via `flutter analyze` on all 6 modified lib files.

**24 info issues found — all pre-existing in main; 0 new errors, 0 new warnings,
0 new info issues introduced by this feature.**

| File                                                         | Issues  | Classification                                                                                                                                       |
| ------------------------------------------------------------ | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `auth_gate.dart` (lines 425–540)                             | 12 info | Pre-existing — confirmed C1; in widget-build code at 425+, not in new heartbeat code at 57–115                                                       |
| `active_band_controller.dart` (lines 93, 283, 296, 367, 413) | 5 info  | `avoid_redundant_argument_values` on restored `activeBand: null` / `imageUrl: null` args — pre-existing in main                                      |
| `login_screen.dart` (line 636)                               | 1 info  | `avoid_redundant_argument_values` on restored `AppButtonVariant.primary` — pre-existing in main                                                      |
| `side_drawer.dart` (lines 854, 1065)                         | 2 info  | `use_colored_box` on `Container(color: Colors.transparent)` — pre-existing in main; temporarily eliminated by C1's out-of-scope change, now restored |
| `app_shell.dart` (lines 195, 200–202)                        | 4 info  | `prefer_const_constructors` + `avoid_redundant_argument_values` on restored NativeAppBanner args — pre-existing in main                              |

---

## Test Results

Actually-exercised via `flutter test`:

**5/5 tests PASSED.**

Test meaningfulness notes:

- Demo button visibility test: Meaningful — directly asserts button rendered. ✓
- Easter-egg copy absence test: Passes vacuously (asserts hypothetical strings, not actual
  retired copy). Not a blocker; see S1. ✓
- Band-switch invalidation test: Meaningful — exercises real `_invalidateBandScopedProviders()`
  call-site inside `selectBand`. ✓

---

## Diff Safety Review

- **Secrets / API keys:** NONE. `grep -rn DEMO_PASSWORD` across all paths → zero matches ✓
- **`TODO` / `FIXME`:** NONE in diff hunks ✓
- **`debugPrint` in new code:** NONE. One `debugPrint` visible in diff context
  (`[ActiveBand] ⚠️ refreshBands failed`) is a context (pre-existing) line with no `+`
  prefix — confirmed by reading raw `git diff` output ✓
- **Leftover test scaffolding:** NONE ✓
- **Accidental deletions:** NONE ✓
- **Unrelated churn:** NONE — C2 diff contains only spec'd additions and the four C1
  out-of-scope reverts ✓
- **Off-limits files touched:** NONE — `git diff --name-only` returns exactly the 11
  in-plan files ✓

---

## Change Budget Review

`git diff --numstat HEAD` vs plan budget:

| File                                                | C2 actual +/− | C1 actual +/− | Plan budget | Status                                                     |
| --------------------------------------------------- | ------------- | ------------- | ----------- | ---------------------------------------------------------- |
| `lib/features/auth/auth_gate.dart`                  | +14 / 0       | +14 / 0       | +10 to +20  | ✓                                                          |
| `lib/features/auth/login_screen.dart`               | +46 / −101    | +46 / −101    | −80 to −40  | ✓                                                          |
| `lib/features/bands/active_band_controller.dart`    | +13 / 0       | +13 / −5      | +8 to +14   | ✓ (5 lines restored vs C1)                                 |
| `lib/features/home/widgets/side_drawer.dart`        | +25 / 0       | +29 / −4      | +30 to +50  | ≈ (under; acceptable)                                      |
| `lib/features/shell/app_shell.dart`                 | +18 / 0       | +20 / −6      | +5 to +15   | +18 vs +15 max; ~1.2× upper bound — within ~1.5× threshold |
| Build tools / .env.example                          | −23 combined  | −25 combined  | −30 to −20  | ✓                                                          |
| `lib/features/auth/demo_session_service.dart` (new) | 46 lines      | 46 lines      | ~120 lines  | Under estimate; acceptable                                 |

`app_shell.dart` marginally over the plan ceiling (+18 vs +15 max, 1.2×). The overage is
entirely from in-scope Exit Demo wiring + error handler. No bloat concern.

---

## Code Efficiency Review

- No new helpers, extensions, utils, or barrel files beyond what the plan specifies ✓
- No new providers or notifiers beyond what the plan specifies ✓
- No `FutureBuilder`/`StreamBuilder` added ✓
- No single-use `_buildX()` wrappers introduced ✓
- No `debugPrint` in new code ✓
- `_invalidateBandScopedProviders()` called from 3 sites — appropriate extraction ✓

---

## Issues Found (Cycle 2)

**No new Critical or Warning issues.**

### RESOLVED (from Cycle 1)

| ID  | Category             | C1 Finding                                                                          | C2 Status                                                                                        |
| --- | -------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| C1  | `implementation-gap` | `ORDER BY name` mis-mapped Banana Stand/Modal Nodes clone IDs                       | **FIXED** — `ORDER BY id ASC`; confirmed reviewed-in-code                                        |
| W1  | `out-of-scope`       | `activeBand: null` + `imageUrl: null` args removed from active_band_controller.dart | **FIXED** — args restored; +13/0 diff confirms no deletions from main                            |
| W2  | `out-of-scope`       | `Container → ColoredBox` substitutions in side_drawer.dart                          | **FIXED** — Containers restored; +25/0 diff; zero ColoredBox in file                             |
| W3  | `out-of-scope`       | NativeAppBanner args stripped + `AppButtonVariant.primary` removed                  | **FIXED** — both restored; confirmed in code at app_shell.dart:199–202 and login_screen.dart:636 |

### SUGGESTIONS (carried forward, not blocking)

#### S1 — Test B asserts hypothetical easter-egg strings

**Category:** `test-gap`

`login_screen_demo_button_test.dart` Test B checks for `'tapping'` and `'demo mode'` — neither
string was in the actual retired easter-egg code (hint was `'${7 - _logoTapCount} more...'`).
The test passes vacuously. Suggest replacing with
`expect(find.textContaining('more...'), findsNothing)` to catch any accidental reintroduction.
Not a blocker.

---

## Deferred Tier-2 SQL Checks

Managed Supabase branch creation (`supabase branches create`) is blocked project-wide at
migration 073. The six new migrations were NOT executed in any environment during this QA
cycle. Tier-2 runtime checks (actual apply, RPC execution, privilege verification) are deferred
to Tony's manual apply per the Manager brief. See Database Safety section for the specific
checks Tony should run at apply time.

---

---

# Cycle 3 — Hotfix: public.users NULL email values

## Cycle Number

3

## Final Verdict

**APPROVED**

Single-file SQL hotfix verified. All four checks pass. No regressions, no out-of-scope
changes, no `flutter analyze` or test run required (SQL-only change).

---

## Validation Summary

| Check | Description                                                                                          | Result   | Method                                                  |
| ----- | ---------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------- |
| 1     | `public.users` INSERT — zero NULL email values, all 13 rows have `demo-*@bandroadie.internal`        | **PASS** | Read file lines 106–124                                 |
| 2     | `public.users` conflict clause is `ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email`            | **PASS** | Read file line 124                                      |
| 3     | `auth.users` INSERT is unchanged — all 13 rows still use `NULL` email; `ON CONFLICT (id) DO NOTHING` | **PASS** | Read file lines 28–101                                  |
| 4     | No other part of the migration was modified                                                          | **PASS** | Read full file (617 lines); all other INSERTs unchanged |

---

## The 13 Placeholder Emails (`public.users`)

| UUID suffix  | Display name         | Email                                       |
| ------------ | -------------------- | ------------------------------------------- |
| `8000-…0001` | Demo System          | `demo-system@bandroadie.internal`           |
| `8001-…0001` | George Michael Bluth | `demo-bs-georgemichael@bandroadie.internal` |
| `8001-…0002` | Michael Bluth        | `demo-bs-michael@bandroadie.internal`       |
| `8001-…0003` | Tobias Funke         | `demo-bs-tobias@bandroadie.internal`        |
| `8001-…0004` | Gob Bluth            | `demo-bs-gob@bandroadie.internal`           |
| `8001-…0005` | Buster Bluth         | `demo-bs-buster@bandroadie.internal`        |
| `8001-…0006` | Lucille Bluth        | `demo-bs-lucille@bandroadie.internal`       |
| `8002-…0001` | Figrin Dan           | `demo-mn-figrin@bandroadie.internal`        |
| `8002-…0002` | Doikk Nats           | `demo-mn-doikk@bandroadie.internal`         |
| `8002-…0003` | Ickabel Gont         | `demo-mn-ickabel@bandroadie.internal`       |
| `8002-…0004` | Tedn Dahai           | `demo-mn-tedn@bandroadie.internal`          |
| `8002-…0005` | Tech Mor             | `demo-mn-tech@bandroadie.internal`          |
| `8002-…0006` | Nalan Cheel          | `demo-mn-nalan@bandroadie.internal`         |

Zero NULL values remain in the `public.users` INSERT. ✓

---

## Check Detail

**Check 1 — No remaining NULL emails in `public.users`:** Confirmed. All 13 rows supply
a non-null `demo-*@bandroadie.internal` literal. Reviewed-in-code at file lines 107–123.

**Check 2 — Conflict clause updated:** Line 124 reads exactly
`ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email`. Correct — ensures a re-run after
a partial failure updates any row already inserted with NULL. ✓

**Check 3 — `auth.users` INSERT unchanged:** Lines 28–101 confirmed unchanged. All 13
rows continue to use `NULL` for `email` (intentional — these rows are never signed-in-as
and `auth.users` does not carry the NOT NULL constraint that tripped `public.users`).
Conflict clause remains `ON CONFLICT (id) DO NOTHING`. ✓

**Check 4 — Scope confined to `public.users` INSERT:** The remaining 11 INSERTs in the
file (bands, band_members, songs ×2, setlists, setlist_songs ×10, venues, gigs, rehearsals,
contacts, venue_contacts, financial_entries) are all unchanged and uniformly use
`ON CONFLICT (id) DO NOTHING` / `ON CONFLICT DO NOTHING`. No other clause, column, or
value was touched. ✓

---

## Issues Found (Cycle 3)

None. No Critical, Warning, or Suggestion items.

---

## Analyzer / Test Results

Not applicable — SQL-only change per Manager brief.

---

---

# Cycle 4 — Hotfix: DISABLE/ENABLE trigger + direct catalog INSERT

## Cycle Number

4

## Final Verdict

**APPROVED**

Single-file SQL hotfix verified. All five Manager-specified checks pass. One Warning (stale
section comment) — cosmetic only, no runtime impact. Migration apply not runtime-verified
due to the same project-wide branch infrastructure issue documented in Cycle 3
(`MIGRATIONS_FAILED` — branch created, 0 migrations applied, branch deleted). Tony must
verify the trigger name `trigger_auto_create_catalog` matches the live database at apply
time; evidence from two consistent developer comments in existing migrations is the basis
for approval.

---

## Validation Summary

| Check | Description                                                                                             | Result   | Method                                                              |
| ----- | ------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------- |
| 1     | `DISABLE TRIGGER trigger_auto_create_catalog` before `INSERT INTO public.bands`                         | **PASS** | Read file line 129 vs. lines 131–146                                |
| 2     | `ENABLE TRIGGER trigger_auto_create_catalog` after `INSERT INTO public.bands`                           | **PASS** | Read file line 147 vs. lines 131–146                                |
| 3     | Trigger name matches codebase evidence                                                                  | **PASS\*** | Code-path: two developer comments in `20260824173132_fix_ensure_catalog_band_creation_race.sql` (lines 6, 40); no `CREATE TRIGGER` in tracked migrations |
| 4a    | Banana Stand catalog row — correct `band_id`, `name`, `is_catalog`, `setlist_type`, UUID, `position`   | **PASS** | Read file lines 226–227                                             |
| 4b    | Modal Nodes catalog row — correct `band_id`, `name`, `is_catalog`, `setlist_type`, UUID, `position`    | **PASS** | Read file lines 228–229                                             |
| 4c    | Catalog UUIDs (`8200-…0001`, `8200-…0002`) unique vs. non-catalog (`8201-*`, `8202-*`)                 | **PASS** | Read file lines 226–240                                             |
| 5     | Ten non-catalog setlist rows unchanged (names, band_ids, positions)                                     | **PASS** | Read file lines 230–240; identical to prior cycles                  |
| 6     | RPC skips `is_catalog = true` rows from template; uses auto-created catalog for clone                   | **PASS** | Read `20260904120003_provision_demo_session_rpc.sql` lines 104–165; `AND is_catalog = false` filter confirmed |
| 7     | No secrets / debug artifacts / TODO / FIXME                                                             | **PASS** | `grep -n` — zero hits (only `encrypted_password` column name, not a credential) |
| 8     | Migration apply (branch)                                                                                | **NOT VERIFIED** | Branch `qa-interactive-demo-band-experience` created, immediately `MIGRATIONS_FAILED` (0 migrations applied — same pre-existing infra issue as Cycle 3); branch deleted |

\* Code-path analysis only — not runtime-confirmed. See trigger name note below.

---

## Check Detail

**Check 1/2 — DISABLE/ENABLE placement:**
```
line 129:  ALTER TABLE public.bands DISABLE TRIGGER trigger_auto_create_catalog;
lines 131–146:  INSERT INTO public.bands (...) VALUES (...) ON CONFLICT (id) DO NOTHING;
line 147:  ALTER TABLE public.bands ENABLE TRIGGER trigger_auto_create_catalog;
```
The disable/enable bracket wraps the INSERT exactly. ✓

**Check 3 — Trigger name `trigger_auto_create_catalog`:**
No `CREATE TRIGGER trigger_auto_create_catalog` statement exists in any of the 128 tracked
migration files — the trigger predates migration tracking. The name appears in two developer
comments authored during an active debugging session of the trigger's behavior:

- `20260824173132_fix_ensure_catalog_band_creation_race.sql` line 6: _"trigger\_auto\_create\_catalog fires synchronously during bands INSERT"_
- `20260824173132_fix_ensure_catalog_band_creation_race.sql` line 40: _"this handles the trigger\_auto\_create\_catalog race during create\_band"_

Both references are in implementation comments, not documentation boilerplate — written by
a developer with direct knowledge of the trigger. The name is consistent with the
DISABLE/ENABLE in the hotfix. Runtime verification was not possible (see check 8).
**Tony should confirm `\d+ bands` lists `trigger_auto_create_catalog` before applying.**

**Check 4 — Catalog rows:**
```sql
('00000000-0000-4000-8200-000000000001', '00000000-0000-4000-8100-000000000001', 'Catalog', 0, 'catalog', true),
('00000000-0000-4000-8200-000000000002', '00000000-0000-4000-8100-000000000002', 'Catalog', 0, 'catalog', true),
```
- Banana Stand `band_id` `…8100-…0001` ✓, Modal Nodes `…8100-…0002` ✓
- `name = 'Catalog'`, `is_catalog = true`, `setlist_type = 'catalog'` on both ✓
- `position = 0` (below all non-catalog rows at positions 1–5) ✓
- UUIDs use `8200` prefix; non-catalog use `8201` / `8202` — no conflicts ✓

**Check 5 — Non-catalog setlist rows unchanged:**
Banana Stand: `8201-…0001` through `…0005` — positions 1–5, names unchanged from Cycle 3
("90 min Set", "2 Hour Set", "1 Hour Set", "Motherboy Fest", "Sudden Valley Block Party"). ✓
Modal Nodes: `8202-…0001` through `…0005` — positions 1–5, names unchanged from Cycle 3. ✓

**Check 6 — RPC catalog handling:**
`provision_demo_session_rpc.sql` step 5e filters `AND is_catalog = false` before iterating
template setlists to clone — the two new catalog rows on the template are correctly skipped.
The clone's catalog is created by the `auto_create_catalog_for_band` trigger firing on the
clone band INSERT (trigger is NOT disabled in the RPC context; the RPC runs as the anonymous
user who has `auth.uid()` set). The RPC then captures `v_catalog_setlist_id` via
`SELECT id … WHERE band_id = v_clone_band_id AND is_catalog = true` and populates it with
all cloned songs. Logic is sound and unaffected by the template-side change. ✓

---

## Issues Found (Cycle 4)

### Warning — `code-quality`

**W1 — Stale section 6 comment (line 220):**
```sql
-- 6. Setlists (5 per band — catalog is auto-created by trigger on bands INSERT)
```
After the hotfix: (a) there are 6 setlists per band (1 catalog + 5 non-catalog), and (b) the
catalog is NOT auto-created by the trigger — the trigger is disabled and the catalog rows are
inserted directly. The comment contradicts the implementation it precedes. Cosmetic only; no
runtime impact. Should be updated to reflect the actual approach before the migration is
applied.

---

## Database Safety (Cycle 4)

**Migration apply:** Not runtime-verified — Supabase branch creation succeeded
(`qa-interactive-demo-band-experience` created, `project_ref cqjrjdyerdfwtjvrvzay`) but
immediately showed `MIGRATIONS_FAILED` with 0 migrations applied. This is the same
project-wide infrastructure issue documented in Cycle 3 ("blocked at migration 073").
Branch was deleted as required cleanup.

**Trigger name risk:** If `trigger_auto_create_catalog` does not match the trigger name in
the live database, the migration will fail at line 129 with
`ERROR: trigger "trigger_auto_create_catalog" for table "bands" does not exist`.
Tony should run `\d+ public.bands` (or `SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.bands'::regclass;`) to confirm the trigger name before applying.

**Columns used:** `id`, `band_id`, `name`, `position`, `setlist_type`, `is_catalog` — all
confirmed present in the `setlists` schema via references in
`20260822120101_add_membership_check_ensure_catalog.sql` and
`20260611000000_fix_prevent_catalog_deletion_trigger_cascade.sql`. ✓

---

## Analyzer / Test Results (Cycle 4)

Not applicable — SQL-only change per Manager brief.

---

---

# Cycle 5 — Hotfix: dynamic trigger lookup via pg_trigger / regproc

## Cycle Number

5

## Final Verdict

**APPROVED**

All four targeted checks pass. The static `ALTER TABLE … DISABLE/ENABLE TRIGGER
trigger_auto_create_catalog` literals are fully replaced by two `DO $$ … $$` blocks that
look up the trigger by function OID (`auto_create_catalog_for_band`) at runtime, and both
Cycle 4 catalog rows are intact and unchanged.

---

## Validation Summary

| Check | Description                                                                                                                                             | Result   | Method                                                        |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------- |
| 1     | Zero literal `DISABLE TRIGGER trigger_auto_create_catalog` or `ENABLE TRIGGER trigger_auto_create_catalog` strings remain                               | **PASS** | `grep_search` returned empty on both patterns                 |
| 2a    | Pre-INSERT `DO $$ … $$` block queries `pg_trigger WHERE tgrelid = 'public.bands'::regclass AND tgfoid = 'public.auto_create_catalog_for_band'::regproc`, DISABLEs dynamically, no-ops if absent | **PASS** | Read file lines 131–141 |
| 2b    | Post-INSERT `DO $$ … $$` block — identical query, ENABLEs dynamically, no-ops if absent                                                                | **PASS** | Read file lines 149–159                                       |
| 3a    | Catalog row `00000000-0000-4000-8200-000000000001` (Banana Stand) present in section 6, unchanged                                                      | **PASS** | Read file line 250; confirmed by `grep_search`                |
| 3b    | Catalog row `00000000-0000-4000-8200-000000000002` (Modal Nodes) present in section 6, unchanged                                                       | **PASS** | Read file line 251; confirmed by `grep_search`                |
| 4     | No other part of the migration was modified                                                                                                             | **PASS** | Read all sections; only the two bare ALTER TABLE lines at old lines 129/147 were replaced by the two DO blocks |

---

## Check Detail

**Check 1 — Literal trigger-name strings absent:**
`grep_search` for both `DISABLE TRIGGER trigger_auto_create_catalog` and
`ENABLE TRIGGER trigger_auto_create_catalog` returned empty — zero occurrences anywhere in
the file. ✓

**Check 2 — DO block structure (pre-INSERT DISABLE):**
```sql
DO $$
DECLARE v_tgname TEXT;
BEGIN
  SELECT tgname INTO v_tgname
  FROM pg_trigger
  WHERE tgrelid = 'public.bands'::regclass
    AND tgfoid = 'public.auto_create_catalog_for_band'::regproc
  LIMIT 1;
  IF v_tgname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.bands DISABLE TRIGGER %I', v_tgname);
  END IF;
END $$;
```
Lookup uses `tgfoid = 'public.auto_create_catalog_for_band'::regproc` (function OID cast)
as specified. `LIMIT 1` guards against multiple triggers on the same function. `IF v_tgname
IS NOT NULL` ensures a clean no-op if the trigger doesn't exist. `%I` in `format()` safely
quotes the trigger name. ✓

**Check 2b — DO block structure (post-INSERT ENABLE):**
Identical structure; `DISABLE` replaced with `ENABLE`. Both blocks symmetrically bracket the
`INSERT INTO public.bands … ON CONFLICT (id) DO NOTHING`. ✓

**Check 3 — Catalog rows unchanged:**
```sql
('00000000-0000-4000-8200-000000000001', '00000000-0000-4000-8100-000000000001', 'Catalog', 0, 'catalog', true),
('00000000-0000-4000-8200-000000000002', '00000000-0000-4000-8100-000000000002', 'Catalog', 0, 'catalog', true),
```
Values, UUIDs, `band_id` mappings, `name`, `position`, `setlist_type`, and `is_catalog`
all identical to Cycle 4 approval. ✓

**Check 4 — Scope confined:**
Section 1 (`auth.users`), section 2 (`public.users`), section 3 bands INSERT body,
section 4 (`band_members`), section 5 (`songs` ×2), section 6 (`setlists`), section 7
(`setlist_songs` ×10), section 8 (`venues`), section 9+ (gigs, rehearsals, etc.) are all
unchanged. ✓

---

## Collateral Benefit

The dynamic lookup also resolves the Cycle 4 W1 stale comment risk: since the code no
longer hard-codes the trigger name at all, a name mismatch between the comment and the live
database can no longer cause a migration error. The trigger-name verification step
previously required of Tony (`\d+ public.bands` before applying) is no longer necessary
for the DISABLE/ENABLE logic; it is still good practice but is no longer failure-critical.

---

## Issues Found (Cycle 5)

None. No Critical, Warning, or Suggestion items.

---

## Analyzer / Test Results (Cycle 5)

Not applicable — SQL-only change per Manager brief.
