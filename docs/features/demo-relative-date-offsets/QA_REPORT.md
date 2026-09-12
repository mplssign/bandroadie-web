# QA Report

## Feature Slug

`feature/demo-relative-date-offsets`

## Feature Title

Make Demo Band Gig/Rehearsal/Financial Dates Relative to Provisioning Time Instead of Hardcoded

## Cycle Number

5

## Final Verdict

APPROVED

## Validation Summary

The implementation matches the Architect plan and the sole Cycle 3 Critical
`database-safety` finding is resolved. QA independently reviewed every product
hunk, ran the Flutter gates, cross-checked all offset IDs against the immutable
seed, and applied/reapplied the exact feature migration on disposable local
PostgreSQL 18. Engineer Cycle 4 additionally executed the unchanged real seed,
TTL migration, feature migration, and replaced RPC in a schema-equivalent local
harness with rollback.

No remote database was contacted. No app, simulator, emulator, browser
automation, or live instance was launched. Runtime UI checks remain Tony's
owner-run responsibility and are listed below.

## Architect Scope Review

- Branch, Architect plan, and Engineer report all identify
  `feature/demo-relative-date-offsets`.
- Product scope is exactly one planned migration. No Flutter, existing
  migration, dependency, configuration, trigger, view, or production-table
  schema was changed.
- The migration creates the planned offset table and index, enables RLS with no
  policies, seeds 32 offsets, replaces the existing RPC, and restores the
  planned function grants.
- Architect, Engineer, and QA documents are pipeline artifacts, not product
  scope expansion.

## Completeness Check

All Architect tasks are complete. Static review confirmed the exact table
constraint, index, RLS posture, `14/8/10` offset distribution, idempotent
upsert, one transaction-stable anchor date, all five date-bearing clone paths,
fallback behavior, unchanged RPC signature, and unchanged non-date behavior.
All 32 offset UUIDs occur in the real seed.

## Behavior Verification

**QA-executed:** The exact migration applied and reapplied successfully on a
disposable local PostgreSQL 18 server. Counts remained `gigs=14`,
`rehearsals=8`, and `financial_entries=10`. This independently exercises SQL
parse/DDL/function creation, idempotent seed behavior, RLS setup, and grants;
it does not execute the RPC body.

**Engineer-executed, independently reviewed by QA:** Cycle 4 ran the unchanged
real seed, TTL migration, and feature migration against a disposable local
PostgreSQL 18.3 schema-equivalent harness, then called the real RPC twice under
an authenticated role with anonymous JWT claims inside `BEGIN ... ROLLBACK`.
It observed identical RPC results, one session/two clone bands, `3` past and
`4` future gigs per band, `4` rehearsals and `5` financial entries per band,
all dates within the offset window, no NULL dates, linked-date differences of
`1` and `0` days, a 15-minute TTL, rollback cleanup, and no real-band mutation.

The harness is faithful enough to resolve the Cycle 3 finding. The repository
cannot bootstrap from blank because its first tracked migration assumes an
untracked Supabase baseline. The harness supplied only that missing baseline,
using actual referenced columns and tracked table definitions, auth shims for
the two functions the RPC calls, and the required catalog-trigger behavior.
The material migrations were applied unchanged. Successful execution traversed
the seeded clone paths and therefore exercised the added date logic in its real
RPC context. Omitted unrelated baseline policies or constraints cannot alter
the scoped date computation, migration ACL, or rollback results.

## Regression Check

Overall regression risk: **MEDIUM**, matching the Architect assessment because
the anonymous demo provisioning RPC is replaced.

- Demo gigs/rehearsals/financials: **MEDIUM**; all changed paths were executed
  in Cycle 4 and produced the planned counts and relationships.
- RPC idempotency/capacity/session behavior: **LOW**; replacement diff preserves
  the original control flow, and the second call returned the same clones.
- Real bands: **LOW**; no real-band code path changed and Cycle 4's before/after
  guard found no mutation.
- Auth/RLS/grants: **LOW**; auth logic is unchanged and effective ACL was
  independently verified.
- TTL/cleanup, template-write guard, and `bands_real`: **LOW**; no relevant
  definitions changed, and Cycle 4 confirmed the 15-minute TTL.
- Setlists/members/notifications/platforms/init order: **LOW**; no client or
  shared behavior changed and the original clone flow is preserved.

## Database Safety

- QA local apply/reapply: passed on disposable PostgreSQL 18; no remote access.
- Effective privilege checks: `anon=false`, `authenticated=true`, and a fresh
  role inheriting only PostgreSQL `PUBLIC` privileges=`false`.
- Offset table: RLS enabled, forced RLS disabled as planned, zero policies, and
  no client grants added.
- Migration is additive except for `CREATE OR REPLACE` of the existing RPC. It
  adds no destructive cascade, privilege escalation, trigger, or policy.
- Cycle 4 rollback-wrapped RPC checks passed and left zero demo sessions.
- Cycle 4's disposable server and QA's disposable server were both stopped and
  removed after validation.

## Analyzer Results

QA executed `flutter analyze`: `No issues found!` in 3.7 seconds.

## Test Results

QA executed the complete Flutter test suite: 297 passed, 0 failed.

## Diff Safety Review

- No secrets, API keys, `TODO`, `FIXME`, `debugPrint(`, test scaffolding, or
  accidental deletion appears in the product change.
- Direct comparison with the predecessor RPC shows only the planned offset
  table/seed and date-path substitutions.
- Working tree contains only the expected feature documents and migration.
- No commit, push, deploy, remote database call, or pipeline-lock operation was
  performed.

## Change Budget Review

Actual product scope is one new 498-line migration, zero modified product files,
one table, one index, zero new functions, and zero dependencies. The plan budget
was one new migration and 350-450 lines; 498 lines is about `1.11x` the upper
estimate and therefore within the `1.5x` QA threshold. Engineer documented that
the complete PostgreSQL replacement function body accounts for the size.

## Code Efficiency Review

No equivalent pre-existing offset table, index, or offset helper exists in the
migration history. The single lookup table avoids five production-table schema
changes and matches the planned abstraction. There are no unused fields,
single-call wrappers, speculative flags, duplicate providers, or new client
symbols.

## Manual Verification Punch List

1. In Supabase Studio -> SQL editor, run:
   ```sql
   SELECT template_table, count(*)
   FROM public.demo_template_date_offsets
   GROUP BY template_table
   ORDER BY template_table;
   ```
   **Expected:** three rows: `financial_entries=10`, `gigs=14`,
   `rehearsals=8`.
2. Sign out entirely; on the marketing landing page, click "Try demo" (or the
   equivalent anonymous demo entry point). **Expected:** anonymous demo
   provisioning starts without an authentication or capacity error.
3. Wait for provisioning and land on the Banana Stand dashboard. **Expected:**
   the Banana Stand demo opens successfully.
4. On Banana Stand, verify **Upcoming Gigs** shows exactly "Sudden Valley Block
   Party", "Gob's Magic Show Afterparty", "Bluth Company Holiday Party", and
   "Tobias Nevernude Benefit". **Expected:** exactly 4 upcoming gigs, all dated
   in the future relative to today.
5. On Banana Stand, verify **Past Gigs** shows exactly "Motherboy XXX",
   "Cornballer Fundraiser", and "Banana Stand Grand Opening". **Expected:**
   exactly 3 past gigs, all dated in the past relative to today.
6. Switch to Modal Nodes and inspect both gig lists. **Expected:** exactly 4
   upcoming gigs ("Spice Mine Benefit", "Rebel Alliance Fundraiser",
   "Galactic New Year", "Chalmun's Anniversary") and exactly 3 past gigs
   ("Mos Eisley Grand Opening", "Mandalorian Bar Mitzvah", "Imperial
   Celebration"), each on the correct side of today.
7. Open Banana Stand Financials. Find "PA rental for Motherboy XXX" and
   "Cornballer Fundraiser gig pay". **Expected:** the PA rental is exactly one
   day before Motherboy XXX, and the Cornballer payment is on the same date as
   the Cornballer Fundraiser gig.
8. Exit the demo, sign in as a real user in a real band, and open Gigs,
   Rehearsals, and Financials. **Expected:** no dates differ from their last
   known values.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.