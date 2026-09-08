# QA Report

## Feature Slug

`bug/demo-session-cleanup-orphaned-anonymous-users`

## Feature Title

Demo session cleanup (cron sweep + Exit Demo button) leaves orphaned anonymous `auth.users` rows

## Cycle Number

7 (previous cycle: 6, REQUIRES CHANGES)

## Final Verdict

**APPROVED**

Cycle 6's sole blocker — Test B (the FK-violation-handling path) never having been executed against the Cycle 2 corrected (per-user `FOREACH`) function body — is now closed. Tony re-ran Test B himself this cycle directly against the actual Cycle 2 function body (not the old Cycle 1 batched-delete version), and all 8 assertions passed, including `C_auth_user_gone` — the control user in the same batch as the FK-violating user is no longer collateral damage. Combined with Test A (6/6, passing since Cycle 5/6) and Test C (2/2, passing since Cycle 1), all three Tier 1 DB tests now have real execution evidence against the corrected code, not code-path analysis alone. The diff itself is unchanged since Cycle 2 and remains clean on every other Tier 1 gate item.

## Validation Summary

- Branch `bug/demo-session-cleanup-orphaned-anonymous-users` confirmed via `GIT_OPTIONAL_LOCKS=0 git branch --show-current`. `bash scripts/clear_stale_git_lock.sh` reported no stale lock. Manager already holds `pipeline.lock` for this run (per explicit instruction); QA did not attempt to acquire its own.
- `GIT_OPTIONAL_LOCKS=0 git status` — clean-except-expected, identical shape to Cycles 1–6: `lib/features/auth/demo_session_service.dart` and `supabase/config.toml` modified (tracked); `docs/features/bug/.../`, `supabase/functions/exit-demo-session/`, and `supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql` untracked. Nothing staged or committed — expected and correct at this pipeline stage.
- `GIT_OPTIONAL_LOCKS=0 git diff --stat HEAD` / `--numstat HEAD` on the two tracked files: `demo_session_service.dart` +6/-1, `config.toml` +3/-0 — byte-for-byte identical to every prior cycle. Zero drift.
- Re-read the full migration file `supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql` (84 lines) this cycle: content is exactly the Cycle 2 per-user `FOREACH`/independent-`BEGIN/EXCEPTION`-per-iteration body described in `ENGINEER_REPORT.md`, unchanged from Cycles 2–6.
- Re-read `supabase/functions/exit-demo-session/index.ts` (untracked, no git diff possible): content identical to Cycles 1–6 — CORS/OPTIONS/405 handling, `isAnonymousDemo` accept-only-anon guard, user-scoped client → `exit_demo_session()` RPC → service-role client → `admin.deleteUser(uid)`, 500 on either failure, 200 on success.
- `flutter analyze lib/features/auth/demo_session_service.dart` → **No issues found!** — clean.
- `deno check supabase/functions/exit-demo-session/index.ts` → same pre-existing, diff-unrelated failure (`npm:openai@^4.52.5` type resolution via the `edge-runtime.d.ts` import chain), reproduced with byte-identical error text/location against the untouched `supabase/functions/send-bug-report/index.ts` baseline. Confirms this is an environment/dependency issue orthogonal to the diff. Pass-by-elimination for Tier 1 item 9, same as Cycles 2–6.
- `git diff --numstat HEAD` matches Change Budget (see Change Budget Review). Migration file 84 lines (~80–100 budget); Edge Function 100 lines (~90–110 budget).
- Secrets/debug-artifact scan (`grep -rniE "TODO|FIXME|debugPrint\(|api[_-]?key\s*=|secret\s*="`) across all four plan-scoped files: two `debugPrint(` hits in `demo_session_service.dart` lines 44–45, both outside this diff's hunk (pre-existing code in the untouched `provisionAndEnter` method). No secrets found.
- **MCP/DB re-attempt this cycle, per explicit instruction to try again first**: no `tool_search` (or equivalent deferred-tool-loading) function is present in this session's tool schema, and no Supabase/MCP-prefixed tool (branch create/list, migration apply, `execute_sql`, branch delete, or equivalent) exists among either the directly-callable or declared-deferred tool sets. Identical to Cycle 6's finding — same class of blocker, unchanged. No workaround attempted (no `psql`, no connection string, no credential requested).
- Given the above, this cycle relies on Tony's out-of-band manual execution for Test B, run specifically against the Cycle 2 corrected function body (not the Cycle 1 body Cycle 6's blocker was about). This is legitimate human-verified execution evidence for the specific gate item that was open, per this cycle's explicit instruction — QA's own inability to independently execute does not block APPROVED when a trustworthy human execution result exists against the actual corrected code.
- The three local test files (`/tmp/qa_test_a_normal_cascade.sql`, `/tmp/qa_test_b_fk_violation.sql`, `/tmp/qa_test_backfill.sql`) remain on disk from prior-cycle preparation; still not independently re-run by QA (no reachable schema this cycle either), but no longer load-bearing given Tony's confirmed results.

## Architect Scope Review

Only the four plan-authorized files are touched (reconfirmed via `git status` and content re-read this cycle):

- Created: `supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql` (Cycle 2 fix lands here), `supabase/functions/exit-demo-session/index.ts` (untouched since Cycle 1)
- Modified: `supabase/config.toml` (+3/-0, untouched since Cycle 1), `lib/features/auth/demo_session_service.dart` (+6/-1, untouched since Cycle 1)

No off-limits files touched. No unrelated formatting churn.

## Completeness Check

Cycle 2's single task — replace the batched `DELETE FROM auth.users WHERE id = ANY(...)` with a per-user guarded loop — remains fully implemented and unchanged since last cycle's review:

- `v_user_id uuid` declared alongside the existing `v_expired_user_ids uuid[]`.
- `FOREACH v_user_id IN ARRAY v_expired_user_ids LOOP` wraps a `BEGIN ... EXCEPTION WHEN foreign_key_violation THEN RAISE WARNING ...; END;` block around a single-row `DELETE FROM auth.users WHERE id = v_user_id;` — each iteration's exception handler is scoped to that iteration only (plpgsql creates an implicit subtransaction per `BEGIN/EXCEPTION` block), so a violation on one user rolls back only that user's delete attempt and lets the loop continue to the next `v_user_id`.
- The `DELETE FROM public.demo_sessions WHERE auth_user_id = ANY(v_expired_user_ids);` batched cascade-trigger statement is unchanged from Cycle 1 (this was never the defective statement).
- Comment above the loop accurately describes the per-user guarantee.
- `REVOKE`/`GRANT` lines and the backfill `DO` block: untouched, verbatim since Cycle 1.

No partial implementation. All Engineer Task Breakdown steps accounted for.

## Behavior Verification

Both code-path analysis (this cycle, QA) and real execution (Tony, out-of-band, against the Cycle 2 corrected body):

- **Root-cause fix confirmed by execution**: Tony's re-run of Test B against the actual Cycle 2 `FOREACH`/independent-exception-handler body passed all 8 assertions, including `C_auth_user_gone` — the previously-collateral-damaged control user in the same sweep batch as the FK-violating user is now correctly deleted. This is the exact defect mechanism the Cycle 2 diff targets, now verified against the real corrected code rather than inferred from reading the SQL.
- **Test A** (normal cascade, no FK violations) — 6/6, confirmed passing against the corrected body (carried forward from Cycle 5/6, reaffirmed this cycle per the task instructions as already-passing and not requiring re-verification).
- **Test C** (backfill filter) — 2/2, confirmed passing; the backfill `DO` block is unchanged since Cycle 1 and was never in question.
- No scope creep: no changes to `provisionAndEnter`, `heartbeat`, the `exit_demo_session()` RPC body, the Edge Function, `config.toml`, or any off-limits migration.
- **Carried-forward minor observation (unchanged, still not blocking)**: `demo_session_service.dart`'s `exit()` still doubles the error message on a non-2xx Edge Function response (`"Demo exit failed: Demo exit failed: HTTP 500"`), a direct consequence of the plan's own instruction, not an Engineer deviation. Still a Suggestion.

## Regression Check

- **Auth**: only the demo-exit call site and the cron-only cleanup function changed; real-user auth flows untouched.
- **Init order**: not touched.
- **Platform parity**: change is in shared `lib/features/auth/demo_session_service.dart` and a `postgres`-only cron function; no platform-conditional code.
- Per-row `FOREACH` vs. batched `DELETE`: negligible performance concern — expired-session batch sizes are small (demo sessions cap at 30 minutes lifetime; a 5-minute sweep interval bounds batch size to whatever entered in a 5-minute window), and this is a `postgres`-superuser cron job, not a client-facing hot path.
- No test file references `DemoSessionService`, `demo_session_service`, `cleanup_expired_demo_sessions`, or `exit-demo-session` anywhere in `test/` — no existing coverage to run or break.
- **Overall regression risk: MEDIUM**, unchanged from the plan and Cycles 1–6 — the fix is architecturally sound per code review and now confirmed by execution against the corrected body for all three Tier 1 DB tests. No open regression concerns remain.

## Database Safety

**All three Tier 1 DB tests now have confirmed execution evidence against the Cycle 2 corrected function body.**

QA's own MCP/DB access path remains unreachable this cycle (re-checked first, per instruction — see Validation Summary): no `tool_search` function and no Supabase/MCP-prefixed tool exist in this session's schema. No workaround attempted, consistent with this mode's permanent retirement of raw-connection routes.

Per this cycle's explicit instruction, Tony's out-of-band manual re-run of Test B — this time executed directly against the actual Cycle 2 corrected function body, not the stale Cycle 1 body Cycle 6's blocker was about — is accepted as legitimate human-verified execution evidence for that gate item:

- **Test A** — human-verified PASS (6/6) against the corrected body.
- **Test B** — human-verified PASS (8/8, including `C_auth_user_gone`) against the corrected body. This closes the sole open item from Cycle 6.
- **Test C** — human-verified PASS (13/13 template-exclusion + 2/2 template-band-intact) against the corrected body (backfill block unchanged since Cycle 1).

All three Tier 1 gate items (Verification Plan items 4–8) are satisfied with real execution evidence, not code-path reasoning alone. `has_function_privilege`-style grant checks and the SQL syntax/topology items were reviewed by direct SQL reading in prior cycles and remain unchanged (function signature, `SECURITY DEFINER`, grants all untouched from Cycle 1).

## Analyzer Results

`flutter analyze lib/features/auth/demo_session_service.dart` → **No issues found!** Clean at every severity.

## Test Results

`flutter test` not run — plan does not require it for this bug, Engineer did not run it, and no existing test coverage references any of the changed files/functions (confirmed by grep across `test/`).

## Diff Safety Review

- No secrets or API keys in the diff.
- No `TODO`/`FIXME` in the diff. Two pre-existing `debugPrint(` calls exist in `demo_session_service.dart` but sit outside this diff's hunk (lines 44–45, inside the untouched `provisionAndEnter` method) — not introduced by this change, not flagged.
- No leftover test scaffolding, no accidental deletions, no unrelated churn.

## Change Budget Review

| File                                                                | Budget        | Actual         | Verdict                                           |
| ------------------------------------------------------------------- | ------------- | -------------- | ------------------------------------------------- |
| `supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql` | ~80–100 lines | 84 lines       | within budget                                     |
| `supabase/functions/exit-demo-session/index.ts`                     | ~90–110 lines | 100 lines      | within budget                                     |
| `supabase/config.toml`                                              | +3            | +3/-0          | exact match                                       |
| `lib/features/auth/demo_session_service.dart`                       | ~+4 net       | +6/-1 (net +5) | within tolerance (<1.5x), unchanged since Cycle 1 |

No new files this cycle (migration file was created in Cycle 1; only its internal content changed in Cycle 2). No new public classes/methods/dependencies introduced by the Cycle 2 change — `v_user_id` is a plpgsql local variable inside an existing function, not a new symbol requiring a duplicate-helper search.

## Code Efficiency Review

- Cycle 2's change is a minimal, surgical correction: batched statement → `FOREACH` loop with per-iteration exception scoping. No new helpers, abstractions, or providers introduced.
- No hand-rolled logic duplicating an existing utility — this is plpgsql control flow, not application code with a `package:collection` equivalent.
- Comment update accurately reflects the new behavior (verified in Completeness Check) rather than being cosmetic or misleading.

## Manual Verification Punch List

Everything below requires a running/live database or on-device execution and is Tony's to run, not QA's. Items 1–2 (re-running Tests A/B against the Cycle 2 body) are now complete and removed from this list; the remaining Tier 2 items are carried forward unchanged from the plan (`ARCHITECT_PLAN.md` → Verification Plan → Tier 2 → items 10–17).

1. Apply migration `supabase/migrations/20260908120000_fix_demo_auth_user_cleanup.sql` against prod (`supabase db push` or Dashboard). Expected result: applies without error; migration log shows a `RAISE NOTICE 'backfill deleted % orphaned anon auth.users rows'` with a count near 59.
2. Run: `SELECT count(*) FROM auth.users WHERE is_anonymous = true AND (raw_user_meta_data->>'demo_placeholder') IS DISTINCT FROM 'true';` — expected result: `0`.
3. Run: `SELECT count(*) FROM auth.users WHERE id IN ('00000000-0000-4000-8000-000000000001', /* remaining 12 template ids */);` — expected result: `13`.
4. Run: `SELECT count(*) FROM public.bands WHERE is_demo_template = true;` — expected result: `2`.
5. Deploy the Edge Function: `supabase functions deploy exit-demo-session`. Confirm Dashboard JWT-verification setting matches `verify_jwt = true` in `config.toml`.
6. On-device: enter demo mode, tap "Exit Demo," then immediately run `SELECT * FROM auth.users WHERE id = '<the demo visitor's uid>';` against prod. Expected result: zero rows.
7. On-device: enter demo mode, background the app 30+ minutes to expire the session, then re-run the query from step 6. Expected result: zero rows after the next cron tick.
8. (Optional) In the Supabase Auth dashboard, check whether the automatic-anonymous-cleanup toggle exists and consider enabling it as a complementary safety net.

## Issues Found

### Critical

None.

### Warnings

None. Cycle 6's sole Warning (Test B unverified against the corrected body) is closed this cycle by Tony's confirmed execution against the actual Cycle 2 function body.

### Suggestions

- **[code-quality]** Carried forward from Cycles 1–6: `DemoSessionService.exit()`'s `catch (e)` unconditionally rewraps any thrown `DemoSessionException` from the new response-status check, producing a doubled message (`"Demo exit failed: Demo exit failed: HTTP 500"`) for non-2xx Edge Function responses. Direct consequence of the plan's own instruction, not an Engineer deviation. Not blocking.
