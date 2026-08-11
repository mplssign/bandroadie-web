# Architect Plan: Staging-2 Migration Ledger Repair

## Feature Slug

`chore/staging-ledger-repair`

## Problem Summary

Staging-2 (Supabase project `hpjvbagybmmaykamsgpd`) has migration ledger drift from the local `supabase/migrations/` directory. As of 2026-07-31, staging-2's ledger had 2 orphan migration entries not present locally and was missing approximately 17 recent local migrations (everything from mid-July 2026 onward). The actual gap today is likely larger since the repo has continued moving forward. Production (project `nekwjxvgbveheooyorjo`) is 100% correct — all 80 local migrations are applied with zero drift — and must not be touched.

This task repairs staging-2 incrementally to restore it as a trustworthy pre-deployment verification environment. A full `supabase db reset --linked` is known broken (missing `bands` table migration, sequential-numbered migrations 073-088 sort lexically after timestamp-format migrations they depend on) and is explicitly out of scope.

## Root Cause

**Confidence: HIGH**

Staging-2 was paused, then unpaused on 2026-07-31. During the pause window, migrations were applied to production but not to staging-2, causing the ledger to diverge. No mechanism auto-synced the migration ledger when staging-2 was unpaused. The 7/31 snapshot showed the gap floor; continued development since then (including PR #113 on 2026-08-03: gig expenses, and PR #114 on 2026-08-03: song key/tuning None option) has widened the gap further.

## Reference Docs Consulted

- `/Users/tonyholmes/apps/bandroadie/docs/reference/deployment/deployment.md` — Supabase CLI commands
- `/Users/tonyholmes/apps/bandroadie/docs/reference/architecture/database_schema.md` — Database schema reference
- `/Users/tonyholmes/apps/bandroadie/docs/features/gig-venue-autocomplete/ENGINEER_REPORT.md` — Prior successful migration repair example (2026-08-02 production drift repair)
- Repo memory: `/memories/repo/supabase.md` — Known migration repair patterns and CLI failure modes

## Existing System Analysis

### Current State (verified 2026-08-09)

**Local repository:**

- 80 migration files in `supabase/migrations/`
- Migrations span from `073_fix_gig_responses_unique_constraint.sql` through `20260804200000_reorder_setlists_rpc.sql`
- Sequential-numbered migrations (073-088) sort lexically before timestamp-format migrations (20260109...) but depend on tables created by later-sorting files — this breaks `supabase db reset --linked` but is out of scope

**Production (nekwjxvgbveheooyorjo):**

- All 80 local migrations applied and verified
- `financial_entries.is_reimbursed`, `reimbursed_date`, and `financial_entries_reimbursement_consistency` constraint present (PR #113, migration `20260803120000`)
- `clear_song_metadata(UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN)` with 6-arg signature present (PR #114, migration `20260803153000`)
- Zero ledger drift confirmed by Manager

**Staging-2 (hpjvbagybmmaykamsgpd):**

- Last verified state: 2026-07-31 (point-in-time snapshot, must be re-verified)
- 7/31 snapshot showed 2 orphan ledger entries + ~17 missing migrations
- Was paused, then unpaused 2026-07-31
- Actual current state unknown — requires fresh diagnosis via `supabase migration list --linked`

**Current workspace link:**

- Linked to production: `nekwjxvgbveheooyorjo` (verified via `cat supabase/.temp/project-ref`)

### Known CLI Failure Mode

`supabase db push --linked` can hang on "Initialising login role..." indefinitely (network/firewall issue, not a bug). Prior workaround: apply SQL directly via Dashboard SQL Editor, then use `supabase migration repair --linked --status applied <version>` to stamp the ledger.

### Known From-Scratch Rebuild Defect (Out of Scope)

No tracked migration creates the `bands` table. Sequential migrations 073-088 sort before timestamp migrations but depend on tables those create. This breaks `supabase db reset --linked` — deliberately not fixed in this task per Tony's explicit deferral. If re-confirmed during diagnosis, document as a known follow-up but do not attempt repair.

## Proposed Solution

Use incremental migration ledger repair, not a full reset:

1. **Switch link to staging-2** and confirm project-ref safety:

   ```bash
   supabase link --project-ref hpjvbagybmmaykamsgpd
   cat supabase/.temp/project-ref  # MUST show hpjvbagybmmaykamsgpd
   ```

2. **Diagnose current ledger state:**

   ```bash
   supabase migration list --linked > staging2_migration_list.txt
   ls -1 supabase/migrations/ > local_migration_list.txt
   ```

   Compare lists to identify:
   - **Orphan entries:** versions in remote ledger not present locally → mark as `reverted`
   - **Missing entries:** local files not in remote ledger → apply via `db push` or manual SQL
   - **Version drift:** same content, different stamped version → repair version only

3. **Repair orphan entries:**
   For each orphan version found:

   ```bash
   supabase migration repair --linked --status reverted <version>
   ```

4. **Apply missing migrations:**
   - **Option A (preferred):** `supabase db push --linked --dry-run` to preview, then `supabase db push --linked`
   - **Option B (if CLI hangs):** For each missing migration:
     1. Copy SQL content to Dashboard SQL Editor
     2. Execute manually
     3. Stamp ledger: `supabase migration repair --linked --status applied <version>`

5. **Verify final state via direct schema queries:**
   - All 80 local migration versions present in ledger:
     ```sql
     SELECT COUNT(*) FROM supabase_migrations.schema_migrations;
     -- Expected: 80
     ```
   - financial_entries columns exist (PR #113):
     ```sql
     SELECT column_name, data_type, is_nullable
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'financial_entries'
       AND column_name IN ('is_reimbursed', 'reimbursed_date')
     ORDER BY column_name;
     ```
   - financial_entries constraint exists:
     ```sql
     SELECT constraint_name, constraint_type
     FROM information_schema.table_constraints
     WHERE table_schema = 'public'
       AND table_name = 'financial_entries'
       AND constraint_name = 'financial_entries_reimbursement_consistency';
     ```
   - clear_song_metadata has 6-arg signature (PR #114):
     ```sql
     SELECT pg_get_functiondef('public.clear_song_metadata(uuid,uuid,boolean,boolean,boolean,boolean)'::regprocedure);
     -- Should include p_clear_musical_key parameter
     ```

6. **Switch back to production:**
   ```bash
   supabase link --project-ref nekwjxvgbveheooyorjo
   cat supabase/.temp/project-ref  # MUST show nekwjxvgbveheooyorjo
   ```

## ⚠️ Contingency: Early-Migration Failure Due to Missing Base Tables

**Context:** On 2026-08-02, during the `gig-venue-autocomplete` feature deployment, `supabase db push --linked --include-all` against staging-2 failed at migration `073_fix_gig_responses_unique_constraint.sql` with error `relation "gig_responses" does not exist`. This was one week after the initial "17 missing migrations" diagnosis, indicating that the actual gap is much larger than a recent-migrations tail and may be the same untracked-`bands`-table ordering defect documented as explicitly out of scope for this task.

**Detection Point:** Phase 1 diagnosis (Task 1.5) may reveal missing migrations span back to the 073-088 range, or Phase 3 dry-run (Task 3.1) may show `db push` would fail on an early-numbered migration.

**STOP Condition:** If Phase 1 diagnosis OR Phase 3 dry-run reveals:

- Missing migrations include files numbered 073-088 (early sequential-format migrations), OR
- Dry-run output indicates `db push` would fail with "relation does not exist" errors for core tables (`bands`, `gigs`, `gig_responses`, `venues`, `rehearsals`, `setlists`, `songs`, etc.)

**Then Engineer MUST:**

1. **STOP immediately** — do not proceed with Phase 3.4 (applying migrations)
2. Document the exact failure in ENGINEER_REPORT.md:
   - Full dry-run output showing which migration would fail
   - Missing table names from the error message
   - Full list of missing migration versions from Phase 1 diagnosis
3. **DO NOT attempt manual/ad hoc schema patches** to create missing base tables — that would be an undocumented fix to the out-of-scope defect and would leave staging-2 in a hybrid state diverged from both production and the tracked migrations
4. Escalate to Manager (Tony) with the diagnostic evidence — this task may not be completable as pure incremental repair if the underlying from-scratch rebuild defect has propagated into staging-2's current state

**Rationale:** The incremental repair strategy in this plan assumes staging-2's schema is mostly correct and only the migration ledger has drift. If core tables are missing entirely, staging-2 is not "mostly correct" — it's in the same broken state that blocks `db reset --linked`, which is the defect Tony explicitly deferred as a separate repo-level fix. Attempting to patch around it here would create undocumented drift and is outside this task's scope.

## Database Impact

**Affected:**

- `supabase_migrations.schema_migrations` table on staging-2 — ledger entries will be added/modified during repair
- `public.financial_entries` table on staging-2 — will gain `is_reimbursed`, `reimbursed_date` columns and constraint (from migration `20260803120000`)
- `public.clear_song_metadata()` RPC on staging-2 — will be replaced with 6-arg version (from migration `20260803153000`)

**Unaffected:**

- Production database (nekwjxvgbveheooyorjo) — explicitly off-limits, no changes
- No RLS policy changes in the migrations being applied
- No database trigger changes in the migrations being applied

**Migration policy:** Not required — using existing 80 tracked migration files, no new migrations created

## Flutter Architecture Changes

Not applicable — database infrastructure task only, no application code changes.

## Files to Create

None.

## Files to Modify

None — this is a database migration ledger repair task. All work is performed via Supabase CLI commands and direct SQL queries against the staging-2 database. Local migration files in `supabase/migrations/` remain unchanged.

## Files Off-Limits

| File                                       | Reason                                                            |
| ------------------------------------------ | ----------------------------------------------------------------- |
| `supabase/migrations/*.sql`                | Migration history is immutable; existing files must not be edited |
| `lib/**/*.dart`                            | Application code not in scope                                     |
| `supabase/functions/**/*.ts`               | Edge functions not in scope                                       |
| Production database (nekwjxvgbveheooyorjo) | Already correct, explicitly off-limits per acceptance criteria    |

## System Impact Map

| System                                 | Impact                                                  |
| -------------------------------------- | ------------------------------------------------------- |
| Gigs                                   | unaffected                                              |
| Rehearsals                             | unaffected                                              |
| Setlists / Catalog                     | affected (clear_song_metadata RPC updated on staging-2) |
| Members / RBAC                         | unaffected                                              |
| Auth / Session                         | unaffected                                              |
| Routing                                | unaffected                                              |
| Notifications                          | unaffected                                              |
| Platform (iOS / Android / Web / macOS) | unaffected                                              |
| Financial Entries                      | affected (new columns and constraint on staging-2)      |

## Regression Risk

**Level: LOW**

**Rationale:**

- No application code changes
- No changes to production (already 100% correct)
- Staging-2 is a pre-deployment environment, not user-facing
- All migrations being applied (especially PR #113, PR #114) are already verified and running in production with zero issues
- Migration repair workflow is well-documented and has been successfully executed before (production repair on 2026-08-02 for `gig-venue-autocomplete` feature)
- The only risk is applying the wrong migrations to the wrong environment — mitigated by mandatory `cat supabase/.temp/project-ref` verification before every `db push`

## Engineer Task Breakdown

### Pre-work: Safety Confirmation

- [ ] Task 0.1 — Confirm current workspace is on branch `chore/staging-ledger-repair`
- [ ] Task 0.2 — Confirm current Supabase link is to production: `cat supabase/.temp/project-ref` returns `nekwjxvgbveheooyorjo`

### Phase 1: Switch Link and Diagnose

- [ ] Task 1.1 — Link to staging-2: `supabase link --project-ref hpjvbagybmmaykamsgpd`
- [ ] Task 1.2 — **CRITICAL SAFETY CHECK:** `cat supabase/.temp/project-ref` must return exactly `hpjvbagybmmaykamsgpd`. If not, stop immediately.
- [ ] Task 1.3 — Capture remote ledger state: `supabase migration list --linked > staging2_migration_list.txt`
- [ ] Task 1.4 — Capture local migration list: `ls -1 supabase/migrations/ > local_migration_list.txt`
- [ ] Task 1.5 — Compare lists and document in ENGINEER_REPORT.md:
  - Orphan entries (in remote, not local)
  - Missing entries (in local, not remote)
  - Total remote count vs. expected 80
  - **⚠️ CONTINGENCY CHECK:** If missing entries include migrations numbered 073-088, document the full missing range and proceed to Task 1.6 before continuing to Phase 2.
- [ ] Task 1.6 — **STOP CONDITION EVALUATION (if Task 1.5 flagged concern):** Query staging-2 for core table existence:
  ```sql
  SELECT table_name
  FROM information_schema.tables
  WHERE table_schema = 'public'
    AND table_name IN ('bands', 'gigs', 'gig_responses', 'venues', 'rehearsals', 'setlists', 'songs')
  ORDER BY table_name;
  ```

  - **Expected if OK to proceed:** All 7 tables present
  - **If fewer than 7 tables:** STOP immediately, follow Contingency protocol (see "⚠️ Contingency: Early-Migration Failure" section), escalate to Manager. DO NOT proceed to Phase 2.

### Phase 2: Repair Orphan Entries

- [ ] Task 2.1 — For each orphan entry identified in Task 1.5, execute:
  ```bash
  supabase migration repair --linked --status reverted <version>
  ```
  Document each repair in ENGINEER_REPORT.md.
- [ ] Task 2.2 — If no orphan entries found, document: "No orphan entries detected."

### Phase 3: Apply Missing Migrations

- [ ] Task 3.1 — Run dry-run to preview: `supabase db push --linked --dry-run`
- [ ] Task 3.2 — Document dry-run output in ENGINEER_REPORT.md:
  - Full list of migrations that would be applied
  - Any errors or warnings shown in dry-run output
  - **⚠️ CONTINGENCY CHECK:** If dry-run output shows errors like `relation "gig_responses" does not exist`, `relation "bands" does not exist`, or similar missing-table errors for core tables, STOP immediately and follow Contingency protocol (see "⚠️ Contingency: Early-Migration Failure" section). Escalate to Manager. DO NOT proceed to Task 3.3 or 3.4.
- [ ] Task 3.3 — **CRITICAL SAFETY CHECK (repeat):** `cat supabase/.temp/project-ref` must return exactly `hpjvbagybmmaykamsgpd`. If not, stop immediately.
- [ ] Task 3.4 — Apply migrations (only if Tasks 3.1-3.3 passed):
  - **If CLI succeeds:** `supabase db push --linked`
  - **If CLI hangs on "Initialising login role":** Use Dashboard SQL Editor method:
    1. Open https://supabase.com/dashboard/project/hpjvbagybmmaykamsgpd/sql
    2. For each missing migration in order:
       - Copy SQL content to editor
       - Execute
       - Verify no errors
       - Run: `supabase migration repair --linked --status applied <version>`
    3. Document each manual application in ENGINEER_REPORT.md
- [ ] Task 3.5 — Document final `supabase migration list --linked` output showing all 80 migrations applied

### Phase 4: Verification

- [ ] Task 4.1 — Run all Tier 2 verification queries against staging-2 (see Verification Plan below)
- [ ] Task 4.2 — Document verification results in ENGINEER_REPORT.md
- [ ] Task 4.3 — Confirm all verification queries passed with expected results

### Phase 5: Restore Production Link

- [ ] Task 5.1 — Link back to production: `supabase link --project-ref nekwjxvgbveheooyorjo`
- [ ] Task 5.2 — **CRITICAL SAFETY CHECK:** `cat supabase/.temp/project-ref` must return exactly `nekwjxvgbveheooyorjo`. Document in ENGINEER_REPORT.md.

### Deliverables

- [ ] Task 6.1 — ENGINEER_REPORT.md with:
  - Before/after ledger diff (orphan count, missing count, total count)
  - All repair commands executed
  - All verification query results
  - Confirmation of final production link restoration
- [ ] Task 6.2 — Staging-2 ledger repaired to match local migrations exactly

## Verification Plan

### Tier 1 — Pre-deployment

Not applicable — this task repairs an existing environment, it does not create new migrations to test in isolation.

### Tier 2 — Post-deployment (Run After Repair Completes)

**Context:** All tests run against staging-2 project `hpjvbagybmmaykamsgpd` after migration repair completes. Use `supabase db query --linked -f <test.sql>` or Dashboard SQL Editor.

**-- POST-DEPLOY TEST 1: Ledger count matches local**

```sql
-- Expected: 80 (matching local migration count)
SELECT COUNT(*) AS total_migrations
FROM supabase_migrations.schema_migrations;
```

**-- POST-DEPLOY TEST 2: No orphan entries remain**

```sql
-- Expected: 0 rows (all remote entries correspond to local files)
-- This test is a manual check: compare supabase migration list --linked output
-- against ls -1 supabase/migrations/ — document any discrepancies
```

**-- POST-DEPLOY TEST 3: financial_entries columns exist (PR #113)**

```sql
-- Expected: 2 rows
-- is_reimbursed | boolean | NO
-- reimbursed_date | date | YES
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'financial_entries'
  AND column_name IN ('is_reimbursed', 'reimbursed_date')
ORDER BY column_name;
```

**-- POST-DEPLOY TEST 4: financial_entries constraint exists**

```sql
-- Expected: 1 row
-- financial_entries_reimbursement_consistency | CHECK
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND table_name = 'financial_entries'
  AND constraint_name = 'financial_entries_reimbursement_consistency';
```

**-- POST-DEPLOY TEST 5: clear_song_metadata has 6-arg signature (PR #114)**

```sql
-- Expected: function definition contains:
-- 1. SECURITY DEFINER
-- 2. SET search_path = public
-- 3. Six parameters: p_song_id, p_band_id, p_clear_bpm, p_clear_duration, p_clear_tuning, p_clear_musical_key
-- 4. Body includes: musical_key = CASE WHEN p_clear_musical_key THEN NULL ELSE musical_key END
SELECT pg_get_functiondef('public.clear_song_metadata(uuid,uuid,boolean,boolean,boolean,boolean)'::regprocedure);
```

**-- POST-DEPLOY TEST 6: Verify specific recent migrations applied**

```sql
-- Expected: 2 rows
-- 20260803120000 | add_reimbursement_fields_to_financial_entries
-- 20260803153000 | add_clear_musical_key_to_clear_song_metadata
SELECT version, name
FROM supabase_migrations.schema_migrations
WHERE version IN ('20260803120000', '20260803153000')
ORDER BY version;
```

**-- POST-DEPLOY TEST 7: Production unchanged (safety check)**

```sql
-- Run against production (nekwjxvgbveheooyorjo) AFTER switching link back
-- Expected: 80 (same as before repair started)
SELECT COUNT(*) AS prod_migration_count
FROM supabase_migrations.schema_migrations;
```

## QA Regression Areas

### Primary Validation

1. **Ledger parity:** Staging-2 `supabase_migrations.schema_migrations` contains all 80 local migration versions, no orphans, no gaps
2. **Schema verification (PR #113):** financial_entries.is_reimbursed, reimbursed_date, and financial_entries_reimbursement_consistency constraint all present on staging-2
3. **RPC verification (PR #114):** clear_song_metadata has 6-arg signature with p_clear_musical_key parameter on staging-2

### Safety Verification

4. **Production unchanged:** nekwjxvgbveheooyorjo migration ledger count remains 80, no new entries, no changed entries
5. **Link restoration:** Final `supabase/.temp/project-ref` reads `nekwjxvgbveheooyorjo` (production)

### Documentation Quality

6. **Before/after diff:** ENGINEER_REPORT.md clearly documents the ledger state before repair (orphan count, missing count) and after repair (all 80 applied)
7. **Verification queries:** All POST-DEPLOY tests executed and results documented with pass/fail status

## Rollout / Migration Strategy

Not applicable — this is a staging environment repair, not a production deployment. Once staging-2 is repaired, future features will be able to verify against staging-2 before deploying to production per the standard BandRoadie workflow.

## Out of Scope

Explicitly excluded from this task:

1. **Any changes to production (nekwjxvgbveheooyorjo):** Production is already correct and must remain untouched.
2. **`supabase db reset --linked` / from-scratch rebuild:** Known broken due to missing `bands` table migration and sequential-number / timestamp-format ordering defect. Do not attempt to fix this underlying repo defect in this task.
3. **Fixing the missing `bands` table migration:** If re-confirmed during diagnosis, log it clearly in ENGINEER_REPORT.md as a known follow-up issue, but do not create or modify migrations to fix it here.
4. **Fixing migration numbering / ordering:** Sequential migrations 073-088 sorting before timestamp migrations is a separate repo defect. Document if encountered, but do not fix.
5. **Application code changes:** No changes to `lib/`, `supabase/functions/`, or any Dart/TypeScript source files.
6. **New migrations:** This task uses existing tracked migrations only. Do not create new migration files.
