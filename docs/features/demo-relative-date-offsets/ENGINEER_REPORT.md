# Engineer Report

## Feature Slug

`feature/demo-relative-date-offsets`

## Feature Title

Make Demo Band Gig/Rehearsal/Financial Dates Relative to Provisioning Time Instead of Hardcoded

## Cycle Number

4

## Goal

Create the planned demo-template date-offset lookup and replace `provision_demo_session()` so cloned gig, rehearsal, and financial-entry dates are relative to the provisioning date.

## Architect Tasks Completed

- Created the timestamped migration.
- Added `demo_template_date_offsets`, its table index, and RLS with no policies.
- Added all 32 idempotent offset rows with the planned per-table values.
- Replaced `provision_demo_session()` with the planned anchor-relative date lookups and fallback behavior.
- Preserved the planned function revoke/grant posture.
- Completed the mandatory isolated PostgreSQL apply, ACL, and rollback-wrapped RPC verification requested by QA Cycle 3.

## Files Created

- `supabase/migrations/20260912122827_demo_relative_date_offsets.sql`
- `docs/features/demo-relative-date-offsets/ENGINEER_REPORT.md`

## Files Modified

- `docs/features/demo-relative-date-offsets/ENGINEER_REPORT.md` (Cycle 4 verification evidence only)

The product migration was not modified in Cycle 4 because isolated execution exposed no implementation defect.

## Analyzer Results

`flutter analyze` passed: `No issues found!` (3.4s).

`dart fix --dry-run` passed: `Nothing to fix!`

## Test Results

`flutter test` passed: 297 tests, 0 failures.

Isolated PostgreSQL 18.3 validation passed. The real feature migration compiled, applied, and reapplied without error. The real `provision_demo_session()` executed twice under an authenticated role with anonymous JWT claims inside a transaction that was rolled back.

## Code Efficiency/Bloat Check

The implementation remains limited to the plan-listed table, index, offset rows, and RPC date substitutions. No helper, dependency, schema, product code, or migration change was added in Cycle 4. The temporary harness reused actual repository definitions where tracked and supplied only the omitted baseline objects and auth/catalog behavior required by the immutable seed and RPC. The migration is 498 lines because PostgreSQL requires the complete replacement function body.

## Verification

- Left the Manager-owned `pipeline.lock` untouched. Ran `bash scripts/clear_stale_git_lock.sh`, `GIT_OPTIONAL_LOCKS=0 git branch --show-current`, and `GIT_OPTIONAL_LOCKS=0 git status --short`; branch and expected worktree state passed.
- Initialized `/tmp/bandroadie-demo-offsets-pg-cycle4/data` with `/opt/homebrew/Cellar/postgresql@18/18.3/bin/initdb --auth-local=trust --auth-host=trust --no-locale --encoding=UTF8`.
- Started only the disposable server with `pg_ctl ... -o '-p 55439 -k /tmp/bandroadie-demo-offsets-pg-cycle4/socket -c listen_addresses=127.0.0.1' start`. No remote database or Supabase command was used.
- Attempted all 135 repository migrations in filename order with `psql -X -v ON_ERROR_STOP=1`. The blank-database history boundary is the first file: `073_fix_gig_responses_unique_constraint.sql` fails at line 13 because baseline relation `gig_responses` is absent; zero migrations applied. This confirms the repository migration directory is incremental over an untracked Supabase baseline and cannot bootstrap a blank PostgreSQL database.
- Built `/tmp/bandroadie-demo-offsets-pg-cycle4/harness.sql` from the actual columns referenced by `20260904120001_seed_demo_templates.sql` and `20260912122827_demo_relative_date_offsets.sql`, plus tracked table definitions from `20260410000000_contacts_venues_tables.sql`, `20260519160119_add_rehearsal_multi_date_support.sql`, and `20260601000000_create_financial_entries.sql`. Auth shims read `request.jwt.claims`; the catalog trigger implements the behavior explicitly required by both provisioning RPC migrations.
- Applied the harness, then the repository's real `20260601000000_create_financial_entries.sql`, `20260904120000_demo_bands_schema.sql`, `20260904120001_seed_demo_templates.sql`, `20260908194500_reduce_demo_session_ttl_to_15min.sql`, and `20260912122827_demo_relative_date_offsets.sql`, all unchanged, using `psql -X -v ON_ERROR_STOP=1`. Every file applied successfully.
- Reapplied `20260912122827_demo_relative_date_offsets.sql` unchanged. It succeeded; row counts remained `financial_entries=10`, `gigs=14`, `rehearsals=8`.
- Effective `has_function_privilege` results were `anon=false`, `authenticated=true`, and `public_probe=false`. `public_probe` is a fresh role with only privileges inherited from PostgreSQL `PUBLIC`, because `PUBLIC` is a pseudo-role and cannot itself be passed as the role-name argument on standalone PostgreSQL.
- Executed the RPC twice under `SET LOCAL ROLE authenticated` with `request.jwt.claims={sub: <isolated anonymous user>, is_anonymous: true}` inside `BEGIN ... ROLLBACK`. Both results were identical, one demo session and exactly two clone bands existed, and rollback left zero sessions.
- Both clone bands had exactly 3 past and 4 future gigs, 4 rehearsals, and 5 financial entries. All cloned dates were within the planned +/-200-day anchor window and explicit assertions found no NULL gig, rehearsal, or financial-entry dates.
- The Motherboy/PA-rental difference was exactly 1 day; the Cornballer gig/pay difference was exactly 0 days.
- `expires_at - provisioned_at` was exactly `00:15:00`.
- A deterministic real-band gig was hashed before provisioning and compared in both set-difference directions afterward; `real_band_unchanged=true`.
- Stopped the disposable PostgreSQL server with `pg_ctl ... stop -m fast` and removed only `/tmp/bandroadie-demo-offsets-pg-cycle4` after all evidence was captured.

## Deviations From Plan

- Full migration-history bootstrap was infeasible because the tracked history starts after the required Supabase baseline. The exact first-file failure is documented above. Per the Cycle 4 instruction, validation continued in a schema-equivalent isolated harness built from actual repository migration, seed, and RPC definitions.
- The Architect's literal `has_function_privilege('public', ...)` form is not executable on standalone PostgreSQL because `PUBLIC` is not a login role. A fresh no-login `public_probe` role verified the effective inherited PUBLIC posture instead.

## Blockers Encountered

None remaining. The absent baseline prevents a full-history blank-database bootstrap but did not prevent faithful isolated compilation and runtime verification of this migration.

## Ready For QA

Yes. The sole QA Cycle 3 Critical finding is resolved by isolated PostgreSQL apply, effective ACL checks, and rollback-wrapped RPC execution. No implementation defect was exposed.
