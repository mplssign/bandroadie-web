# Architect Plan — Track Emergency RLS/Security-Definer Hotfixes (2026-09-05)

## Feature Slug

`chore/track-emergency-rls-hotfixes-20260905`

## Feature Title

Commit tracking migrations for emergency RLS/security-definer hotfixes already applied to prod

## Scope Statement (Commit-Only, No Execution)

**This work is repository-tracking only.** The three SQL statements described below
have already been executed directly against the prod Supabase project via the SQL
editor earlier today (2026-09-05) as an emergency security response. This branch
exists to bring the repository's `supabase/migrations/` history back in sync with
the live schema.

The following actions are **explicitly forbidden** anywhere in this pipeline
(plan, Engineer implementation, QA verification):

- `apply_migration` (Supabase MCP tool)
- `execute_sql` (Supabase MCP tool)
- `supabase db push`
- `supabase migration up`
- `supabase db reset`
- Any Supabase dashboard action (SQL editor, policy editor, function editor, view editor)
- Any invocation of `psql`, `pg_dump`, or other direct DB client against any Supabase project (prod, staging, or branch)

Verification is **static SQL review** against the stated intent — reading the
`.sql` files as text and reasoning about their correctness. It is not execution.

## Problem Summary

Three CRITICAL Supabase advisor findings were resolved directly against prod
earlier today. The corresponding tracking migrations exist on disk but were
never committed, so the repo's migration history diverges from the live
schema. If left untracked, they would either (a) be lost on the next
`flutter clean` / repo reclone, or (b) be discovered later and re-applied
by a future `supabase db push` against a branch/staging project, silently
duplicating work.

Files needing to be tracked (untracked on `main` as of `813e6a9`):

- [supabase/migrations/20260905190400_fix_bands_real_security_definer.sql](../../../supabase/migrations/20260905190400_fix_bands_real_security_definer.sql)
- [supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql](../../../supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql)
- [supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql](../../../supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql)

## Root Cause (HIGH confidence)

Emergency hotfixes applied via SQL editor bypassed the normal
Engineer → migration file → PR → merge → `supabase db push` cadence, which is
the only mechanism that keeps `supabase/migrations/` authoritative for the
live schema. This is a **process gap during incident response**, not a code
bug. Confirmed by:

- `git status --short --untracked-files=all` shows exactly the three `.sql`
  files as untracked (no other repo drift).
- `git merge-base HEAD origin/main == git rev-parse origin/main == 813e6a9`
  (repository is otherwise fully aligned with `origin/main`).
- Each `.sql` file's header explicitly states "Applied directly to prod via
  SQL editor on 2026-09-05 and tracked here for reproducibility."

## Existing System Analysis

Static review of the current `supabase/migrations/` history establishes what
each hotfix is targeting and confirms the fix statements match the observed
prior state.

### Fix 1: `bands_real` view was security-invoker=false

Read of [supabase/migrations/20260904120000_demo_bands_schema.sql](../../../supabase/migrations/20260904120000_demo_bands_schema.sql)
(lines ~142–148) confirms the view was originally created as:

```sql
CREATE OR REPLACE VIEW public.bands_real AS
SELECT * FROM public.bands
WHERE is_demo_template = false
  AND is_demo_clone = false;
```

No `security_invoker` reloption was set, which means the view defaulted to
`security_invoker = false` and ran with the view owner's privileges (which
is the DB owner in Supabase — a superuser-equivalent role that bypasses
RLS entirely). Because the view lives in the `public` schema, PostgREST
auto-exposes it at `GET /rest/v1/bands_real`. Verified via
`grep -r "from(['\"]bands_real['\"])" lib/ supabase/functions/` — zero
callers in Flutter code or in edge functions — so no legitimate consumer
depended on the exposed access path.

### Fix 2: `band_members_insert_self_or_member` had a self-insert branch

Read of [supabase/migrations/20260823120000_wrap_rls_auth_functions.sql](../../../supabase/migrations/20260823120000_wrap_rls_auth_functions.sql)
lines ~131–137 and
[supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql](../../../supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql)
confirms the current policy's `WITH CHECK` is:

```sql
WITH CHECK ((is_band_member(band_id) OR (user_id = (select auth.uid()))))
```

The `OR user_id = auth.uid()` branch is the escalation surface — it lets any
authenticated (including anonymous demo) session self-insert into any band's
`band_members` with any `role` value (there is no `CHECK` constraint on
`role` beyond `band_role_type` enum membership, so `'admin'` is valid).
`status` defaults to `'active'` per the `band_members` schema, meaning the
inserted row is immediately live.

Legitimate flows that were confirmed **not** to require this branch:

- `accept_band_invite` (referenced in
  [supabase/migrations/20260822120002_revoke_anon_batch_3_calendar_invite.sql](../../../supabase/migrations/20260822120002_revoke_anon_batch_3_calendar_invite.sql))
  is `SECURITY DEFINER`; invite acceptance also goes through the
  `accept-invite` edge function (service_role client, bypasses RLS entirely).
- `create_band()` (revoked/regranted in
  [supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql](../../../supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql))
  is `SECURITY DEFINER` and does its own `band_members` insert internally.
- `provision_demo_session()` (in
  [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](../../../supabase/migrations/20260904120003_provision_demo_session_rpc.sql))
  is `SECURITY DEFINER`.
- Flutter client: `grep -r "from(['\"]band_members['\"]).insert" lib/`
  returned zero matches — no direct client insert into `band_members`.
- Edge functions: `supabase/functions/{calendar-feed,send-band-invite,send-bug-report}/index.ts`
  reference `band_members`/`bands` only via `.select(...)`; no `.insert(...)`
  found (grep confirmed).

### Fix 3: `bands_insert_authenticated` allowed direct-REST insert

Same references as Fix 2 confirm the policy was:

```sql
FOR INSERT TO authenticated WITH CHECK (created_by = (select auth.uid()))
```

Same rationale: `create_band()` and `provision_demo_session()` are both
`SECURITY DEFINER` and bypass RLS, so removing the policy blocks direct
`POST /rest/v1/bands` calls without breaking the two legitimate creation
paths. Confirmed via `grep -r "from(['\"]bands['\"]).insert" lib/` — zero
client-side matches.

## Independent Static Assessment of Each Fix

Architect's independent read of each `.sql` file, evaluated against the
stated intent in its own header. **All three fixes are correct as written.**
Nothing to flag or push back on.

### Fix 1 — `20260905190400_fix_bands_real_security_definer.sql` — CORRECT

```sql
ALTER VIEW public.bands_real SET (security_invoker = true);
REVOKE ALL ON public.bands_real FROM anon, authenticated;
```

- `SET (security_invoker = true)` is the correct reloption spelling for
  PostgreSQL 15+ (Supabase runs 15). Applying RLS on the underlying
  `bands` table via the querying role is the right fix.
- `REVOKE ALL FROM anon, authenticated` on top of `security_invoker` is
  belt-and-suspenders — either alone would prevent unauthorized reads, but
  both together prevent the view from being exposed via PostgREST at all
  (no `SELECT` grant → no `/rest/v1/bands_real` endpoint availability for
  those roles).
- Not revoked from `service_role` — correct, because service_role is the
  intended admin/analytics consumer per the view's original purpose comment.
- The view was left in `public` schema. Moving it to a non-public schema
  would be defense-in-depth, but is out of scope for a static-tracking
  branch and the `REVOKE + security_invoker` combo is sufficient.

### Fix 2 — `20260905193400_fix_band_members_self_insert_privilege_escalation.sql` — CORRECT

```sql
DROP POLICY IF EXISTS "band_members_insert_self_or_member" ON public.band_members;
CREATE POLICY "band_members_insert_self_or_member" ON public.band_members
FOR INSERT TO authenticated
WITH CHECK (is_band_member(band_id));
```

- Removing the `OR user_id = (select auth.uid())` branch closes the
  self-elevation gap.
- Policy name preserved (`band_members_insert_self_or_member`), which
  matters for the RLS policy graph — anything referring to the policy by
  name (advisor tooling, future migrations, docs) keeps working.
- Note: the retained `is_band_member(band_id)` check by itself would block
  the very first `band_members` insert for a new band (since the creator
  is not yet a member). This is not a regression because `create_band()`
  is `SECURITY DEFINER` and inserts its creator-membership row while
  bypassing RLS. Confirmed by reading
  [supabase/migrations/20260824173132_fix_ensure_catalog_band_creation_race.sql](../../../supabase/migrations/20260824173132_fix_ensure_catalog_band_creation_race.sql)
  and
  [supabase/migrations/087_fix_create_band_no_profile.sql](../../../supabase/migrations/087_fix_create_band_no_profile.sql).
- `is_band_member` is already properly locked down:
  `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated;` in
  [supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql](../../../supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql).
  Combined with `TO authenticated` on the policy, this correctly denies
  anon sessions.
- The policy remains `FOR INSERT` only; the separate UPDATE policy
  ("Admins can update band members" from
  [supabase/migrations/20260823120000_wrap_rls_auth_functions.sql](../../../supabase/migrations/20260823120000_wrap_rls_auth_functions.sql))
  is unchanged, so admin flows continue to work.

### Fix 3 — `20260905193900_remove_bands_direct_insert_policy.sql` — CORRECT

```sql
DROP POLICY IF EXISTS "bands_insert_authenticated" ON public.bands;
```

- With RLS enabled on `bands` and no `INSERT` policy present, inserts
  from any non-bypass role are denied by default. This is the same
  pattern as `archive.bands` / `archive.band_members` (which have zero
  policies), and matches PostgreSQL's default-deny RLS semantics.
- `service_role` and `postgres` bypass RLS entirely, so
  `create_band()` and `provision_demo_session()` (both
  `SECURITY DEFINER`) continue to insert successfully.
- No new `SECURITY DEFINER` function is introduced, so the mode-level
  guardrail about `REVOKE PUBLIC/anon + GRANT authenticated` +
  `has_function_privilege` verification doesn't apply here.

**Nothing to flag. Ready to commit as-is.**

## Database Impact

**None from this branch.** The three `.sql` files are already applied in prod;
merging this branch has zero SQL effect. No new migrations execute, no
`apply_migration`/`execute_sql`/`supabase db push` action is taken by
Engineer or QA.

For future branch/staging environments that reset from
`supabase/migrations/` (via `supabase db reset` locally, or a `supabase
db push` to a fresh project), the tracked files will play forward in
timestamp order:

- Latest previously-tracked: `20260904120005_cleanup_demo_sessions_cron.sql`
- New (in order):
  1. `20260905190400_fix_bands_real_security_definer.sql`
  2. `20260905193400_fix_band_members_self_insert_privilege_escalation.sql`
  3. `20260905193900_remove_bands_direct_insert_policy.sql`

All three sort strictly after the previous tail. The first file assumes
`bands_real` exists (created in `20260904120000_demo_bands_schema.sql`);
the second and third assume the policies they drop exist (created in
`20260825120000_consolidate_permissive_rls_policies.sql`, later touched
by `20260823120000_wrap_rls_auth_functions.sql`). All prerequisite
migrations are tracked and sort earlier. **Ordering is safe.**

## Flutter Architecture Changes

n/a

## Files to Create

- `docs/features/track-emergency-rls-hotfixes-20260905/ARCHITECT_PLAN.md`
  (this file — created by Architect)
- `docs/features/track-emergency-rls-hotfixes-20260905/ENGINEER_REPORT.md`
  (created by Engineer at the end of implementation)
- `docs/features/track-emergency-rls-hotfixes-20260905/QA_REPORT.md`
  (created by QA at the end of verification)

## Files to Track (Not Modify)

Exactly the three untracked `.sql` files, added to git as-is:

- `supabase/migrations/20260905190400_fix_bands_real_security_definer.sql`
- `supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql`
- `supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql`

**No content changes to these files.** If Engineer sees a diff other than
whitespace/EOL normalization, that's a red flag — stop and report.

## Files Off-Limits

Everything else, including but not limited to:

- All of `lib/**` — this branch touches zero application code.
- Every other file in `supabase/migrations/` — no edits to earlier
  migrations, no new migration files beyond the three above.
- All of `supabase/functions/**` — no edge function changes.
- All of `supabase/config.toml` — no config changes.
- All of `test/**` — no test changes (verification is static SQL review).
- All of `pubspec.yaml`, `analysis_options.yaml`, tooling scripts,
  platform config (`android/**`, `ios/**`, `macos/**`, `web/**`,
  `windows/**`, `linux/**`).
- `docs/features/post-demo-docs-tooling-and-card-layout/**` — see
  Discrepancy section below; these files are **already tracked on `main`
  from PR #256** and must not be modified or deleted on this branch.
- Any other `docs/features/**` outside this feature's own slug.
- All `docs/reference/**` — this chore doesn't warrant a runtime/decisions
  update.

## Manager Preflight / Feature Input Discrepancy (flag before Engineer starts)

The Feature Input states:

> docs/features/post-demo-docs-tooling-and-card-layout/{ARCHITECT_PLAN,
> ENGINEER_REPORT,QA_REPORT}.md are stale untracked leftovers, confirmed
> content-duplicates (modulo markdownlint whitespace) of what already
> merged via PR #256 — delete them rather than folding them into this
> branch.

and the Manager task description adds:

> The stale review reports … have already been deleted by Manager
> preflight; do not add them back and do not fold them into this branch.

**Neither is accurate.** Static verification on the current working tree:

- `git ls-files docs/features/post-demo-docs-tooling-and-card-layout/`
  returns all four files (`ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`,
  `PR_BODY.md`, `QA_REPORT.md`) — they are **tracked**, not untracked.
- `git log --oneline -1 origin/main -- docs/features/post-demo-docs-tooling-and-card-layout/`
  points to `813e6a9 chore(guidance): refresh project docs and card
  layout (#256)` — they came in via the merged PR #256.
- `diff -q <(git show origin/main:…) …` on each of `ARCHITECT_PLAN.md`,
  `ENGINEER_REPORT.md`, `QA_REPORT.md` confirms they are **byte-identical**
  to `origin/main`.
- `git status docs/features/post-demo-docs-tooling-and-card-layout/`
  reports "nothing to commit, working tree clean" for that path.

The Manager's earlier `rm -f` in the preflight terminal did **not** remove
these files from the working tree at the time of Architect's check — the
files are present and match the index. Either the `rm` was undone by a
later checkout, or the earlier terminal transcript is misleading. Either
way, the state Architect is branching from is: files present, tracked,
clean, matching `origin/main`.

**Directive to Engineer and QA:**

- Do not `git rm` these files.
- Do not `rm` them from the working tree.
- Do not fold them into this branch's diff.
- If they appear in `git status` output during Engineer's work, that's
  drift from an unknown source — stop and report before continuing.

The Feature Input's underlying concern (avoid re-committing content
that's already merged) is already satisfied because the files are
tracked on `main` — the branch will carry them forward untouched.

## Change Budget

- Expected new tracked files: **3** SQL migrations + **3** docs (this
  plan + Engineer report + QA report) = **6 total**.
- Expected net line delta in existing tracked files: **0**.
- Expected new dependencies: **0** (`pubspec.yaml` unchanged).
- Expected new public classes/methods/RPCs: **0**.
- Expected changes under `lib/**`: **0**.

If the actual PR diff shows any file outside the six listed above,
that's a Warning/Critical against this plan.

## System Impact Map

- **Auth / session** — unaffected (no auth flow changes).
- **Routing / deep links** — unaffected.
- **Init order** — unaffected (no code changes; the mode's fixed init
  sequence is untouched).
- **Gigs / Rehearsals / Setlists / Songs / Members** — data access is
  **already** restricted in prod by the applied SQL. Committing the
  tracking migrations doesn't further change prod behavior.
- **Notifications** — unaffected.
- **Platforms (iOS / Android / macOS / Web)** — unaffected. This branch
  changes zero client code, so platform parity is trivially preserved.
- **Demo band flow** — unaffected (relies on `provision_demo_session()`,
  `SECURITY DEFINER`, which was verified to bypass all three affected
  policies/views).
- **Edge functions** (`accept-invite`, `send-band-invite`,
  `send-bug-report`, `calendar-feed`, etc.) — unaffected. They use
  service_role clients, which bypass RLS.
- **Supabase advisors** — the three CRITICAL findings are already cleared
  in the live project; tracking the migrations does not itself run the
  advisor.

## Regression Risk: **LOW**

Rationale: this branch commits three files that are already deployed to
prod. Merging the PR to `main` produces zero runtime behavior change on
prod (the SQL is already applied) and zero client behavior change (no
`lib/` edits). The only downstream risk is a future `supabase db reset`
or fresh-project `supabase db push` — for which the three files must
play in the correct order after their prerequisite migrations. Static
review confirms filename ordering is correct.

## Engineer Task Breakdown

Engineer executes exactly these steps, in order. Do not add steps. Do
not `apply_migration`. Do not `execute_sql`. Do not `supabase db push`.

1. Confirm you're on branch `chore/track-emergency-rls-hotfixes-20260905`
   with `git branch --show-current`.
2. Confirm `git merge-base HEAD origin/main == git rev-parse origin/main`
   (i.e. the branch base is `origin/main` at commit `813e6a9`, or
   whatever the current tip of `origin/main` is if it advanced). Stop
   and report if they differ.
3. Confirm `git status --short --untracked-files=all` shows exactly the
   three `.sql` files and no other drift. If anything else appears —
   especially anything under `docs/features/post-demo-docs-tooling-and-card-layout/`
   — stop and report (see Discrepancy section).
4. Read each of the three `.sql` files end-to-end and confirm they
   match the content Architect reviewed above. If any differs, stop.
5. `git add supabase/migrations/20260905190400_fix_bands_real_security_definer.sql`
6. `git add supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql`
7. `git add supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql`
8. `git add docs/features/track-emergency-rls-hotfixes-20260905/ARCHITECT_PLAN.md`
9. Verify `git diff --cached --stat` shows exactly four adds (three SQL
   + this plan) with no modifications to existing tracked files. Stop
   and report if the shape differs.
10. Commit with a message that (a) uses the `chore:` prefix, (b) makes it
    clear these are tracking migrations for prod-applied hotfixes, and
    (c) explicitly notes "already applied to prod via SQL editor on
    2026-09-05; committing for reproducibility only". Example:
    `chore(supabase): track 3 emergency RLS hotfixes already applied to prod 2026-09-05`
11. Do not push yet — hand off to QA for static review. QA's report
    lands as a new commit before push.

## Verification Plan

**Static review only. No SQL execution against any Supabase project or
local Postgres.**

### Static SQL review (QA — one section per file)

For each of the three files, QA confirms:

1. The SQL text on disk is **identical** to what Architect reviewed
   above (paste-comparison against this plan).
2. The migration's stated intent (in its own header comment) matches
   what the SQL actually does.
3. The affected object (`bands_real`, `band_members_insert_self_or_member`,
   `bands_insert_authenticated`) is created earlier in the migration
   history at a strictly lower timestamp — the file will replay
   correctly on a fresh project.
4. No `SECURITY DEFINER` function is added by these files (correct — none
   are).
5. Rollback SQL shown in each header comment is syntactically plausible
   (readable check — not executed).

### Git diff shape

QA runs `git diff origin/main...HEAD --stat` and confirms:

- Exactly four added files: the three `.sql` migrations + this
  `ARCHITECT_PLAN.md`.
- Plus Engineer's `ENGINEER_REPORT.md` and QA's own `QA_REPORT.md` once
  those exist (i.e. up to six added files total).
- Zero modified files.
- Zero deleted files.
- Zero changes under `lib/**`.
- Zero changes under `docs/features/post-demo-docs-tooling-and-card-layout/**`.

If any of these fail, QA marks the PR blocking and does not sign off.

### Migration filename ordering

QA confirms:

- `ls supabase/migrations/*.sql | sort | tail -6` shows the previous tail
  (`20260904120005_cleanup_demo_sessions_cron.sql`) followed by the
  three new files in the order:
  1. `20260905190400_fix_bands_real_security_definer.sql`
  2. `20260905193400_fix_band_members_self_insert_privilege_escalation.sql`
  3. `20260905193900_remove_bands_direct_insert_policy.sql`
- All three sort strictly after the previous tail (`20260904…` < `20260905…`).

### What is NOT in scope for verification

- Running `flutter analyze` / `flutter test` — no `lib/` changes.
- Running any SQL against prod, staging, or a local Postgres —
  explicitly forbidden per Scope Statement.
- Re-running Supabase advisors — the fixes are already applied in prod;
  advisor status is a separate operational check, not a PR gate.
- Modifying the `.sql` file contents — flag any drift and stop.

## QA Regression Areas

Because this branch commits zero application code and applies zero SQL,
there are no runtime regression areas to smoke-test. QA's job is
strictly static SQL review + diff-shape verification per the Verification
Plan.

For completeness — the areas that could theoretically regress if this
were an execution branch (they aren't relevant here because nothing runs):

- Band member add/remove (would need a real invite acceptance smoke).
- Band creation via `create_band()` RPC (would need a smoke).
- Demo session provisioning (would need a fresh anon smoke).
- Admin analytics reads against `bands_real` via service_role (would
  need a service_role query smoke).

None of these are required for this PR because the SQL is already live
in prod and every prior smoke against the current prod state has
already succeeded (Tony's ongoing use of the app since 2026-09-05
morning is the operational canary).

## Rollout Strategy

1. Engineer commits the three SQL files + this plan on branch
   `chore/track-emergency-rls-hotfixes-20260905`.
2. QA reviews statically, adds `QA_REPORT.md`, commits.
3. Engineer or Manager opens a PR against `main`.
4. PR merged squash-normally. **No** `supabase db push` at merge time.
   The tracking migrations must remain unexecuted in CI/CD; they only
   ever run against fresh projects that lack the fixes.
5. Next time a branch/staging project is provisioned, `supabase db push`
   or `supabase db reset` will replay the three files in order,
   arriving at the same state prod is already in.

**Rollback:** if these fixes ever need to be reversed on prod (e.g.
because the app quietly depended on the removed policy in a way we
missed), each `.sql` header includes a rollback reference block. The
rollback is executed the same way the original hotfix was (SQL editor
+ later tracking migration), not via the migration file itself.

## Out of Scope

- Any change to `lib/**`, `test/**`, `pubspec.yaml`, `analysis_options.yaml`,
  or platform config directories.
- Any change to `supabase/config.toml`, edge functions, or other
  migration files.
- Any change to `docs/features/post-demo-docs-tooling-and-card-layout/**`
  (see Discrepancy section).
- Any change to `docs/reference/**` — this chore is small enough and
  process-only enough that no `AI_DECISIONS.md` or `RUNTIME_CONFIG.md`
  update is warranted.
- Broadening or narrowing the retained RLS policies beyond what the
  three hotfix files already do. If the retained
  `band_members_insert_self_or_member` `WITH CHECK (is_band_member(band_id))`
  needs further RBAC tightening (e.g. limiting inserts to admins only),
  that's a follow-up feature, not a chore.
- Moving `bands_real` to a non-public schema. Defense-in-depth is
  worthwhile but is a follow-up feature.
- Adding advisor-check automation to CI so the next round of
  CRITICAL findings surfaces without an emergency. Worth doing; not
  this branch.
- Adding a Manager-preflight check that distinguishes tracked-and-clean
  files from actual untracked drift, so the "delete stale leftovers"
  false alarm from this ticket doesn't recur. Worth doing; not this
  branch.
