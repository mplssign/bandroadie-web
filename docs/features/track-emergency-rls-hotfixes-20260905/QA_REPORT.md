# QA Report — Track Emergency RLS/Security-Definer Hotfixes (2026-09-05)

## Feature Slug

`chore/track-emergency-rls-hotfixes-20260905`

## Feature Title

Commit tracking migrations for emergency RLS/security-definer hotfixes already applied to prod

## Cycle Number

1

## Final Verdict

**APPROVED**

Static review only. No SQL was executed by QA against any Supabase project, and
no execution occurred in any prior pipeline step. The three untracked `.sql`
files match the Architect plan verbatim, are correctly ordered in the migration
history, contain idempotent statements with documented rollback references, and
introduce no client-visible regression. The plan's independent security
assessment holds up under QA's independent re-verification against the current
migration graph, Flutter client code, and Supabase edge functions.

## Validation Summary

- **Branch/base**: on `chore/track-emergency-rls-hotfixes-20260905`;
  `git merge-base HEAD origin/main` = `git rev-parse origin/main` =
  `813e6a9047d77c2a63ddff15dfc0a482cc701f5a`.
- **Working-tree shape**: `git diff HEAD --stat` empty, `git diff HEAD --numstat`
  empty, exactly 5 untracked entries (3 SQL + `ARCHITECT_PLAN.md` +
  `ENGINEER_REPORT.md`).
- **SQL execution**: none. `apply_migration`, `execute_sql`,
  `supabase db push`, `supabase migration up`, `supabase db reset`, `psql`,
  `pg_dump`, and every Supabase MCP tool were **not** invoked by QA. Engineer's
  report confirms the same for the Engineer cycle. Working-tree state (nothing
  committed, three files still untracked) is consistent with a
  static-only pipeline.
- **Static SQL review**: each of the three files matches the Architect plan's
  "Independent Static Assessment" section verbatim; each fix closes the stated
  exposure and preserves every legitimate flow named in the plan.
- **Ordering**: `190400 < 193400 < 193900`, all strictly greater than the prior
  tail (`20260904120005`), and all strictly later than every prerequisite
  migration (`20260825120000` for the two policies, `20260904120000` for
  `bands_real`).
- **Post-demo docs**: all four files under
  `docs/features/post-demo-docs-tooling-and-card-layout/**` remain tracked,
  clean, and byte-identical to `origin/main`.

## Architect Scope Review

Plan-listed files vs. actual working-tree drift:

| Path | Plan expectation | Observed | OK? |
|---|---|---|---|
| `supabase/migrations/20260905190400_fix_bands_real_security_definer.sql` | new, untracked | present, untracked, 30 lines | ✅ |
| `supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql` | new, untracked | present, untracked, 36 lines | ✅ |
| `supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql` | new, untracked | present, untracked, 36 lines | ✅ |
| `docs/features/track-emergency-rls-hotfixes-20260905/ARCHITECT_PLAN.md` | authored by Architect, untracked | present, untracked | ✅ |
| `docs/features/track-emergency-rls-hotfixes-20260905/ENGINEER_REPORT.md` | authored by Engineer, untracked | present, untracked | ✅ |
| `docs/features/track-emergency-rls-hotfixes-20260905/QA_REPORT.md` | authored by QA this cycle | this file | ✅ |
| Any `lib/**` change | forbidden | none | ✅ |
| Any other `supabase/migrations/**` change | forbidden | none | ✅ |
| `supabase/functions/**` change | forbidden | none | ✅ |
| `supabase/config.toml` change | forbidden | none | ✅ |
| `docs/features/post-demo-docs-tooling-and-card-layout/**` change | forbidden | byte-identical to `origin/main` | ✅ |
| Other `docs/**`, `test/**`, platform config | forbidden | none | ✅ |

Verified via `git status --short --untracked-files=all` (5 untracked entries,
0 modified, 0 deleted), `git diff HEAD --stat` (empty), and
`diff -q <(git show origin/main:$p) $p` for each of the four
post-demo-docs paths (all four returned `MATCH origin/main`).

No out-of-scope work introduced.

## Completeness Check

Plan's Engineer Task Breakdown steps 1–4 (verification) completed by Engineer.
Steps 5–10 (`git add` + `git commit`) were intentionally deferred per Manager's
explicit "Do not commit or push" instruction and per Engineer-mode rules that
give Manager exclusive git-write authority — this deferral is a documented
protocol adjustment, not a skipped step, and the Manager owns the commit at
Release. QA's task (static review + report) is completed by this document.

No plan checkpoint is skipped or partially implemented. The three `.sql`
files exist in the exact form the plan reviewed; every prerequisite migration
is present in the tree; ordering is strict; the two docs from prior cycles
are on disk.

## Behavior Verification

**Method: static code-path analysis against the on-disk migration graph, Flutter
client code, and Supabase edge functions.** No runtime exercise, no SQL execution,
no device testing. Aligned with the plan's explicit "static review only" scope.

### Fix 1 — `bands_real` security-invoker (CRITICAL data-leak)

- Root cause per plan: view created in `20260904120000_demo_bands_schema.sql`
  without `security_invoker` reloption. In PostgreSQL 15 (Supabase runtime),
  the absent reloption defaults to `security_invoker = false`, so the view
  runs with the owner's (definer's) privileges and bypasses RLS on the
  underlying `bands` table. PostgREST auto-exposes `public.*` views, so any
  authenticated caller could read every real band via
  `GET /rest/v1/bands_real`.
- QA independently confirmed the pre-state by reading
  `20260904120000_demo_bands_schema.sql` lines 140–148 — the view is created
  with no `WITH (security_invoker = …)` clause.
- Fix DDL (`20260905190400_fix_bands_real_security_definer.sql`):

  ```sql
  ALTER VIEW public.bands_real SET (security_invoker = true);
  REVOKE ALL ON public.bands_real FROM anon, authenticated;
  ```

- Root cause is closed by the `security_invoker = true` — RLS on `bands` now
  applies to the querying role, which for `anon`/`authenticated` means the
  existing `bands_select_members` policy governs, denying non-members. The
  additional `REVOKE ALL FROM anon, authenticated` is belt-and-suspenders:
  either alone would deny unauthorized reads, but the revoke also removes the
  PostgREST endpoint availability altogether for those roles.
- `service_role` retains access (not revoked) — correct for the view's stated
  admin/analytics purpose. `service_role` bypasses RLS regardless.
- **Residual read path**: none identified. Verified via
  `grep -r "bands_real" lib/ supabase/functions/` — zero matches; no client
  or edge function consumes the view. The revoke closes REST access; the
  security_invoker flip closes any future consumer's access path.

### Fix 2 — `band_members` privilege escalation (CRITICAL)

- Root cause per plan: policy `band_members_insert_self_or_member` (created in
  `20260825120000_consolidate_permissive_rls_policies.sql` line 345) had
  `WITH CHECK (is_band_member(band_id) OR user_id = (select auth.uid()))`.
  The second clause let any authenticated caller — including anonymous demo
  sessions after `provision_demo_session` — self-insert into any band's
  `band_members` with any `band_role_type` value (including `'admin'`) and
  `status = 'active'` (the column default), producing instant admin escalation
  against any band in the system.
- QA independently confirmed the pre-state by reading
  `20260825120000_consolidate_permissive_rls_policies.sql` lines 340–348 — the
  policy definition matches.
- Fix DDL (`20260905193400_fix_band_members_self_insert_privilege_escalation.sql`):

  ```sql
  DROP POLICY IF EXISTS "band_members_insert_self_or_member" ON public.band_members;
  CREATE POLICY "band_members_insert_self_or_member" ON public.band_members
  FOR INSERT TO authenticated
  WITH CHECK (is_band_member(band_id));
  ```

- Removing the `OR user_id = (select auth.uid())` clause closes the escalation
  branch. The surviving `is_band_member(band_id)` check requires the caller to
  already be an active member (per the definition in
  `20260826000000_fix_membership_status_and_archive_rls_hygiene.sql`, which
  gates membership on `status = 'active'`).
- Policy name preserved — advisor tooling, later migrations, and the RLS
  policy graph continue to reference it by the same identifier.
- **Coverage of legitimate insert paths** — every legitimate flow that inserts
  into `band_members` bypasses the client-facing RLS policy entirely, so the
  fix cannot regress them:
  - `create_band()` — `SECURITY DEFINER`, verified in
    [supabase/migrations/087_fix_create_band_no_profile.sql](../../../supabase/migrations/087_fix_create_band_no_profile.sql)
    lines 9–91. Inserts creator into `band_members` internally; bypasses RLS.
    Client callsite is `supabase.rpc('create_band', …)` in
    [lib/features/bands/band_form_screen.dart](../../../lib/features/bands/band_form_screen.dart)
    line 334 and
    [lib/features/settings/data_backup_service.dart](../../../lib/features/settings/data_backup_service.dart)
    line 382 — both go through the RPC, not a direct table insert.
  - `accept_band_invite()` — `SECURITY DEFINER`, verified in
    [supabase/migrations/20260717085528_add_intended_role_to_invitations.sql](../../../supabase/migrations/20260717085528_add_intended_role_to_invitations.sql)
    lines 28–75. Client never calls it directly; the only caller is the
    `accept-invite` edge function
    ([supabase/functions/accept-invite/index.ts](../../../supabase/functions/accept-invite/index.ts)
    line 173), which uses a `service_role` client
    (line 38, `createClient(supabaseUrl, serviceRoleKey)`) — this bypasses
    RLS entirely regardless of the policy.
  - `provision_demo_session()` — `SECURITY DEFINER`, verified in
    [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](../../../supabase/migrations/20260904120003_provision_demo_session_rpc.sql)
    lines 11–14. Client callsite is
    [lib/features/auth/demo_session_service.dart](../../../lib/features/auth/demo_session_service.dart)
    line 30 (`.rpc('provision_demo_session')`). Bypasses RLS.
  - `restore_band_members()` — `SECURITY DEFINER` with server-side authority
    checks, verified in
    [supabase/migrations/20260621000002_restore_band_members_rpc.sql](../../../supabase/migrations/20260621000002_restore_band_members_rpc.sql)
    lines 14–66. Client callsite is
    [lib/features/settings/data_backup_service.dart](../../../lib/features/settings/data_backup_service.dart)
    line 470 (`.rpc('restore_band_members', …)`). Bypasses RLS. Not called out
    in the plan but QA identified and verified it independently — same
    conclusion: unaffected.
- **Direct client insert check**: `grep -r "\.from\(['\"]band_members['\"]\)"
  lib/` returned 17 matches across 10 files, and `grep -r "\.insert\("
  lib/` returned 43 matches across 20 files. QA cross-referenced the two:
  every `.from('band_members')` call chains to `.select()`, `.update()`,
  `.delete()`, or `.upsert()` — **zero** chain to `.insert()`. The one nearby
  callsite in
  [lib/features/contacts/widgets/invite_members_screen.dart](../../../lib/features/contacts/widgets/invite_members_screen.dart)
  reads `band_members` at line 134 (`.select('id')` for a duplicate-member
  check) and inserts into `band_invitations` at line 173 — a different table.
  Plan's "grep found zero" claim holds.
- **Anon exposure**: `is_band_member(p_band_id uuid)` has grants
  `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated` per
  [supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql](../../../supabase/migrations/20260822120006_revoke_anon_batch_7_band_mgmt.sql)
  lines 36–37. Combined with `TO authenticated` on the policy, anon sessions
  (non-demo) can neither invoke the check nor satisfy it. Demo sessions are
  authenticated (anonymous JWTs are still `role: authenticated` in Supabase),
  but the surviving `is_band_member` clause blocks them because they are not
  yet members of any real band — they only reach real-band membership via
  `provision_demo_session()`, which is `SECURITY DEFINER` and bypasses this
  policy.
- No regression to legitimate flows identified.

### Fix 3 — `bands` direct-insert policy removal (spam/integrity)

- Root cause per plan: policy `bands_insert_authenticated` (created in
  `20260825120000_consolidate_permissive_rls_policies.sql` line 28) allowed
  `FOR INSERT TO authenticated WITH CHECK (created_by = (select auth.uid()))`.
  This permitted any authenticated caller to `POST /rest/v1/bands` directly,
  bypassing `create_band()`'s side effects (user-row backfill via
  `handle_new_user`, `avatar_color` default, creator-member `band_members`
  insert, catalog setlist auto-creation).
- Fix DDL (`20260905193900_remove_bands_direct_insert_policy.sql`):

  ```sql
  DROP POLICY IF EXISTS "bands_insert_authenticated" ON public.bands;
  ```

- With RLS enabled on `bands` and no `INSERT` policy remaining, PostgreSQL
  denies all inserts for non-bypass roles. Same pattern as `archive.bands` /
  `archive.band_members` per the plan's own reference. Standard default-deny.
- **Coverage of legitimate insert paths**:
  - `create_band()` — `SECURITY DEFINER`, verified above.
  - `provision_demo_session()` — `SECURITY DEFINER`, verified above.
  - Both bypass RLS regardless of the removed policy.
- **Direct client insert check**: same grep pass as Fix 2. Every
  `.from('bands')` call in `lib/` chains to `.select()` or `.update()`, never
  `.insert()`. The nearby `.insert()` in
  [lib/features/bands/band_form_screen.dart](../../../lib/features/bands/band_form_screen.dart)
  line 368 is on `.from('band_invitations')` at line 366, not `.from('bands')`
  (which was the `.update()` chain at line 358–361 for the timezone save).
  Plan's "grep found zero" claim holds.
- **Edge functions**: `send-band-invite`, `send-bug-report`, and
  `calendar-feed` reference `bands` via `.select(...)` only — QA confirmed
  no `.from('bands').insert(...)` anywhere under `supabase/functions/`.
- No regression to legitimate flows identified.

### Summary

All three fixes close their respective exposures without breaking any
legitimate flow. Root causes — not just symptoms — are addressed. Behavior
verification was code-path analysis only; the plan explicitly forbids runtime
exercise and the fixes are already live in prod (any real-world verification
predates this pipeline).

## Regression Check

Systems from the plan's Impact Map, re-evaluated after QA's independent review:

- **Auth / session** — unaffected. No auth or session code changes; magic-link
  flow and demo-session provisioning unchanged. **LOW.**
- **Routing / deep links** — unaffected. Zero client changes. **LOW.**
- **Init order** — unaffected. No client changes. **LOW.**
- **Gigs / Rehearsals / Setlists / Songs / Members** — data access already
  restricted in prod by the applied SQL; committing tracking migrations is
  runtime-null on prod. On a future branch/staging reset, the three
  migrations play forward in order after their prerequisites. **LOW.**
- **Notifications** — unaffected. No notification-trigger or push-config
  changes. **LOW.**
- **Platforms (iOS / Android / macOS / Web)** — unaffected. Zero client code
  changes; platform parity trivially preserved. **LOW.**
- **Demo band flow** — `provision_demo_session()` is `SECURITY DEFINER` and
  bypasses all three affected views/policies. Verified in
  [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](../../../supabase/migrations/20260904120003_provision_demo_session_rpc.sql).
  **LOW.**
- **Edge functions** (`accept-invite`, `send-band-invite`, `send-bug-report`,
  `calendar-feed`) — use `service_role` clients that bypass RLS; verified no
  direct writes to `bands` or `band_members` in
  [supabase/functions/accept-invite/index.ts](../../../supabase/functions/accept-invite/index.ts)
  (uses `accept_band_invite` RPC),
  [supabase/functions/calendar-feed/index.ts](../../../supabase/functions/calendar-feed/index.ts)
  (reads only), and
  [supabase/functions/send-bug-report/index.ts](../../../supabase/functions/send-bug-report/index.ts)
  (reads only). **LOW.**
- **Supabase RPC signatures / parameter order** — no RPC signature changes
  introduced. **LOW.**
- **Controller/FocusNode disposal, `setState` after async gaps, rebuild
  triggers** — no Dart code changed. **LOW.**

**Overall regression risk: LOW.** Zero runtime effect on prod (SQL already
applied); zero client changes; only future-project fresh-play semantics
depend on the tracked files, and those play forward in the correct order.

## Database Safety

**Reviewed statically as required by the plan. Not applied by QA to any
Supabase project.**

- **Migrations match the plan**: SQL text on disk is byte-identical to what
  Architect independently reviewed and approved. Verified by direct read of
  each of the three `.sql` files.
- **Filename ordering**: `20260904120005 < 20260905190400 < 20260905193400 <
  20260905193900`. Strictly increasing lexicographic order. Prerequisites all
  sort earlier (`bands_real` in `20260904120000`,
  `band_members_insert_self_or_member` and `bands_insert_authenticated` in
  `20260825120000`).
- **No self-referencing RLS**: none of the three files introduces or modifies
  an RLS policy that references its own table via a non-SECURITY-DEFINER
  helper. Fix 2's `is_band_member(band_id)` is `SECURITY DEFINER` and
  `STABLE` per
  [supabase/migrations/20260826000000_fix_membership_status_and_archive_rls_hygiene.sql](../../../supabase/migrations/20260826000000_fix_membership_status_and_archive_rls_hygiene.sql)
  lines 19–33 — that's the intended pattern to avoid RLS-recursion on the
  `band_members` table.
- **No privilege escalation**: fixes strictly *reduce* privilege — closing an
  escalation branch (Fix 2), removing a direct-insert policy (Fix 3), and
  revoking view grants (Fix 1). No `GRANT` widens surface area; no new
  `SECURITY DEFINER` function is introduced.
- **No destructive cascade / no data loss**: fixes are DCL-only (policy
  drop/recreate, view alter, revokes). No `DROP TABLE`, no `TRUNCATE`, no
  `DELETE`, no data-carrying `ALTER TABLE` in any of the three files.
- **RPC signature stability**: no RPC touched by these files. `create_band`,
  `accept_band_invite`, `provision_demo_session`, and `restore_band_members`
  signatures unchanged. Client callsites remain valid.
- **New / changed `SECURITY DEFINER` grants**: none. The plan's mode-level
  guardrail about `has_function_privilege` verification does not apply
  because no `SECURITY DEFINER` function is added or altered by these three
  files.
- **Migration apply verification**: **not performed by QA, and this is
  intentional.** The mode's `has_function_privilege` step normally requires
  applying to a temporary `qa-<slug>` branch to confirm clean apply — but the
  Manager task description, the plan's Scope Statement, and the mode's Hard
  Rules ("never fall back to testing against production… never touch the
  production project") together with the fact that the SQL is already applied
  to prod, together forbid any migration-apply action here (including to a
  temporary branch that would then need cleanup). Static SQL correctness has
  been established by paste-comparison against the Architect plan, by
  reading each rollback-reference block, and by verifying every referenced
  identifier exists in the pre-branch migration graph. This is the
  "static SQL review" the plan explicitly defines as the acceptable
  substitute in this exact scenario.
- **Idempotency**:
  - Fix 1: `ALTER VIEW … SET (security_invoker = true)` is idempotent (setting
    the same reloption value is a no-op). `REVOKE ALL … FROM anon,
    authenticated` is idempotent (revoking nothing is a no-op).
  - Fix 2: `DROP POLICY IF EXISTS` + `CREATE POLICY` — idempotent because the
    conditional drop handles re-runs. (Note: `CREATE POLICY` without `OR
    REPLACE` would fail if the DROP were removed — but the DROP is present.)
  - Fix 3: `DROP POLICY IF EXISTS` — idempotent.
- **Rollback**: each file's header comment includes an explicit
  rollback-reference SQL block. Statements are syntactically plausible on
  read:
  - Fix 1 rollback: `ALTER VIEW public.bands_real RESET (security_invoker);
    GRANT SELECT ON public.bands_real TO anon, authenticated;` — correct
    reloption reset syntax; grant restores prior state.
  - Fix 2 rollback: reinstates the exact prior policy with the escalation
    branch — do **not** execute; documented as historical reference only.
  - Fix 3 rollback: reinstates the prior `bands_insert_authenticated` policy —
    do **not** execute; documented as historical reference only.

## Analyzer Results

**Not applicable.** No Dart / Flutter code was added or modified by this
branch (verified via `git diff HEAD --stat` returning empty). The plan's
Verification section explicitly excludes running `flutter analyze` because
there are no `lib/` changes for the analyzer to evaluate.

## Test Results

**Not applicable.** No test changes; no runtime SQL execution permitted by
the plan. The plan explicitly excludes `flutter test`, `dart test`, and any
Supabase execution against prod / staging / local.

## Diff Safety Review

- **Secrets / API keys**: none. `grep` of the three `.sql` files for `KEY|
  SECRET|TOKEN|PASSWORD` returned only English words in comments
  (`token` inside "rollback the token migration" phrasing wouldn't apply
  here; none of the three files mention any credential material).
- **`TODO` / `FIXME` / `debugPrint(`**: `grep -nE
  "TODO|FIXME|debugPrint\(" supabase/migrations/20260905190400_*
  supabase/migrations/20260905193400_* supabase/migrations/20260905193900_*`
  returned zero matches. None of these tokens can appear in valid PostgreSQL
  DDL/DCL anyway, but the check was performed.
- **Test scaffolding / accidental deletions**: none. Working tree shows zero
  modifications and zero deletions.
- **Unrelated formatting churn**: none. No tracked files were touched.
- **Post-demo docs drift**: none. Byte-identical to `origin/main` (see
  Architect Scope Review table above).

## Change Budget Review

Plan's Change Budget: **6 total** new files (3 SQL + 3 docs), **0** net line
delta in existing tracked files, **0** new dependencies, **0** new public
classes/methods/RPCs, **0** `lib/**` changes.

Actual working-tree state at end of QA cycle:

- **Untracked files**: 5 (3 SQL + `ARCHITECT_PLAN.md` + `ENGINEER_REPORT.md`)
  → 6 once this `QA_REPORT.md` is written.
- **Modified files**: 0.
- **Deleted files**: 0.
- **New dependencies**: 0 (`pubspec.yaml` untouched).
- **New public classes / methods / RPCs**: 0.
- **`lib/**` changes**: 0.

Exact match to Change Budget. Within budget; no expansion.

## Code Efficiency Review

**Not applicable.** No Dart code was added, modified, or removed by this
branch. Every "AI-shaped code" check in the mode's bloat rubric (unused
`_buildX()` methods, one-off providers, `try/catch` that rethrows unchanged,
zero-deletion bug fixes, single-call-site abstractions, "for future use"
config flags, single-use helpers, restated comments) has no Dart diff to
audit against. The three `.sql` files are minimal DCL — each performs
exactly the single operation its header comment describes and nothing more.

- Fix 1: 2 executable statements, 26 lines of header comment context.
- Fix 2: 2 executable statements (DROP + CREATE), 30 lines of header comment
  context including rollback reference.
- Fix 3: 1 executable statement, 30 lines of header comment context including
  rollback reference.

Every line of executable SQL is load-bearing. No over-broad revokes, no
sweep-style policy drops, no defensive `EXCEPTION WHEN OTHERS` blocks — all
three files are direct and minimal.

## Issues Found

**None (Critical, Warning, or Suggestion).**

All independent security-review requirements from the Manager task pass:

1. **`bands_real` hotfix — verified.** `security_invoker = true` correctly
   applies RLS on the underlying `bands` table to the querying role, closing
   the definer-privilege bypass. Anon/authenticated grants revoked; no
   residual read path exists (zero consumers in `lib/**` or
   `supabase/functions/**`).
2. **`band_members` privilege escalation hotfix — verified.** Removal of the
   `OR user_id = (select auth.uid())` branch prevents self-insert-as-admin.
   The surviving `WITH CHECK (is_band_member(band_id))` captures no
   legitimate flow because every legitimate insert path (`create_band`,
   `accept_band_invite`, `provision_demo_session`, `restore_band_members`) is
   `SECURITY DEFINER` and bypasses the policy entirely.
3. **`bands_insert_authenticated` removal — verified.** `create_band()` and
   `provision_demo_session()` are both `SECURITY DEFINER` and unaffected.
   No client-side or edge-function `.insert()` into `public.bands` exists.
4. **Filename / timestamp ordering — verified.** `190400 < 193400 < 193900`,
   all strictly greater than the previous tail `20260904120005`, and all
   prerequisite migrations sort earlier.
5. **Idempotency and rollback notes — verified.** All three files use
   idempotent DDL/DCL (`SET reloption`, `DROP … IF EXISTS + CREATE`,
   `DROP … IF EXISTS`, `REVOKE ALL`) and include documented rollback SQL in
   their header comments.
6. **No SQL executed by any prior pipeline step — verified.** Confirmed by
   working-tree state (nothing committed, three files still untracked),
   Engineer's report (explicit statement that no execution occurred), and
   absence of any Supabase CLI, MCP, or `psql` invocation in QA's own
   session.

The Engineer report notes one minor shell-environment side effect during
byte-comparison (a `path` local variable clobbering `$PATH` in one interactive
zsh loop, self-recovered). This is a housekeeping observation about
Engineer's own shell, does not affect any deliverable, and does not warrant
even a Suggestion-level finding.
