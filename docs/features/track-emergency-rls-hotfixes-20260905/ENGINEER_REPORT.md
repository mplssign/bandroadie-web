# Engineer Report — Track Emergency RLS/Security-Definer Hotfixes (2026-09-05)

## Feature Slug

`chore/track-emergency-rls-hotfixes-20260905`

## Feature Title

Commit tracking migrations for emergency RLS/security-definer hotfixes already applied to prod

## Cycle Number

1

## Goal

Bring the repo's `supabase/migrations/` history back in sync with the live prod
schema by tracking three `.sql` files that were already applied directly via the
Supabase SQL editor earlier today (2026-09-05) as an emergency response to three
CRITICAL Supabase advisor findings. This is a **commit-only chore**: zero SQL
execution, zero application code changes, zero configuration changes.

Per Manager's override of Plan steps 5–10, this cycle stops **before** any
`git add`/`git commit`. Manager owns every git write in this pipeline (also
reinforced by the mode rules). Handoff to QA is a static review of the on-disk
state — the three `.sql` files remain untracked in the working tree exactly as
Architect left them.

## Architect Tasks Completed

Plan steps 1–4 (verification) executed. Plan steps 5–10 (git add + commit) were
intentionally **not** executed because Manager explicitly directed "Do not
commit or push" and Engineer mode forbids git write commands regardless. Manager
owns the commit.

- **Step 1** — Branch confirmed: `chore/track-emergency-rls-hotfixes-20260905`.
- **Step 2** — `git merge-base HEAD origin/main` equals `git rev-parse origin/main`
  equals `813e6a9047d77c2a63ddff15dfc0a482cc701f5a` (tip of `origin/main`,
  commit "chore(guidance): refresh project docs and card layout (#256)").
- **Step 3** — `git status --short --untracked-files=all` shows exactly four
  untracked entries: the Architect plan + three `.sql` files. Zero modified
  tracked files, zero deleted files, zero drift under
  `docs/features/post-demo-docs-tooling-and-card-layout/**`.
- **Step 4** — Each `.sql` file was read end-to-end and confirmed to match the
  text Architect independently reviewed in the Plan's "Independent Static
  Assessment of Each Fix" section. All three fixes are byte-identical to what
  Architect approved.

Plan steps 5–10 (`git add ×4` → `git diff --cached --stat` → `git commit`)
deferred to Manager per Manager's explicit override. Plan step 11 (hand off to
QA) is what this report accomplishes.

## Files Created

- [docs/features/track-emergency-rls-hotfixes-20260905/ENGINEER_REPORT.md](../../../docs/features/track-emergency-rls-hotfixes-20260905/ENGINEER_REPORT.md)
  (this file)

The three `.sql` files listed under "Files to Track" in the plan are already on
disk from the original emergency response and remain **untouched** by Engineer:

- [supabase/migrations/20260905190400_fix_bands_real_security_definer.sql](../../../supabase/migrations/20260905190400_fix_bands_real_security_definer.sql)
  — 30 lines, 1,618 bytes, UTF-8 text.
- [supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql](../../../supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql)
  — 36 lines, 1,919 bytes, UTF-8 text.
- [supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql](../../../supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql)
  — 36 lines, 1,883 bytes, UTF-8 text.

The Architect plan itself
([docs/features/track-emergency-rls-hotfixes-20260905/ARCHITECT_PLAN.md](../../../docs/features/track-emergency-rls-hotfixes-20260905/ARCHITECT_PLAN.md))
was written by Architect prior to this cycle and is present untracked as
expected.

## Files Modified

None. Zero tracked files in the repo were modified in this cycle.

`git diff HEAD --stat` and `git diff HEAD --numstat` both return empty output.

## Analyzer Results

**Not applicable.** Per Manager's instruction ("Do not run flutter analyze, dart
test, node --check, or any runtime tool — none apply to a SQL-only tracking
commit") and per the Plan's Verification section ("Static review only. No SQL
execution against any Supabase project or local Postgres. … Running
`flutter analyze` / `flutter test` — no `lib/` changes."), no analyzer was run.
No Dart code was touched.

## Test Results

**Not applicable.** No test changes; no `flutter test` invocation per Manager
and Plan. The plan explicitly excludes this: "Running any SQL against prod,
staging, or a local Postgres — explicitly forbidden per Scope Statement."

## Code Efficiency/Bloat Check

**Not applicable to SQL-only tracking commits.** No Dart code was added or
modified in this cycle. The three SQL files' text was written by Architect
during the original emergency response and is byte-identical to what Architect
independently re-reviewed in the Plan; Engineer's role in this cycle is
verification, not authorship.

The AI-shaped-code checklist items (unused `_buildX()`, one-off providers,
`try/catch` that rethrows unchanged, TODO/FIXME/`debugPrint(` leftovers,
zero-deleted-line bug fixes, etc.) do not apply — there is no Dart diff to
audit. `dart fix --dry-run` was not run because there are no changed Dart
files for it to advise on.

Helper/utility reuse search: also not applicable. No new helpers, extensions,
or private widget classes are introduced by this cycle.

File-size targets: the largest new file in scope is 36 lines
(`20260905193400_fix_band_members_self_insert_privilege_escalation.sql` and
`20260905193900_remove_bands_direct_insert_policy.sql`), well under every
target.

## Verification (manual/static steps performed)

Per the Plan's "Verification Plan" section (static SQL review + git diff shape
+ migration filename ordering), and per Manager's "Verification is static-only
per the plan" directive.

### 1. Branch and base

- `GIT_OPTIONAL_LOCKS=0 git branch --show-current`
  → `chore/track-emergency-rls-hotfixes-20260905` ✅
- `test "$(git merge-base HEAD origin/main)" = "$(git rev-parse origin/main)"`
  → `GATE PASS: branch base equals origin/main tip` ✅
- `git rev-parse origin/main`
  → `813e6a9047d77c2a63ddff15dfc0a482cc701f5a`
- `git log --oneline -1 origin/main`
  → `813e6a9 chore(guidance): refresh project docs and card layout (#256)`

### 2. Working-tree shape (matches Architect's Change Budget)

- `git diff HEAD --stat` → empty (no tracked-file modifications) ✅
- `git diff HEAD --numstat` → empty ✅
- `git diff origin/main...HEAD --stat` → empty (base equals tip) ✅
- `git status --short --untracked-files=all` returns exactly 4 lines:
  1. `?? docs/features/track-emergency-rls-hotfixes-20260905/ARCHITECT_PLAN.md`
  2. `?? supabase/migrations/20260905190400_fix_bands_real_security_definer.sql`
  3. `?? supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql`
  4. `?? supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql`
  ✅

### 3. Post-demo docs untouched (per Architect's Discrepancy directive)

Each of `ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, `PR_BODY.md`, and
`QA_REPORT.md` under `docs/features/post-demo-docs-tooling-and-card-layout/` was
byte-compared to its `origin/main` version via
`diff -q <(git show origin/main:$p) $p`:

- `ARCHITECT_PLAN.md` → `MATCH origin/main` ✅
- `ENGINEER_REPORT.md` → `MATCH origin/main` ✅
- `PR_BODY.md` → `MATCH origin/main` ✅
- `QA_REPORT.md` → `MATCH origin/main` ✅

All four remain tracked, clean, and byte-identical to `origin/main` as Manager
described. Engineer did not `rm`, `git rm`, edit, or otherwise disturb them.

### 4. SQL file content — matches Architect's independent review verbatim

Each `.sql` file was read end-to-end and compared line-by-line against
Architect's "Independent Static Assessment of Each Fix" section of the plan.

**Fix 1 — `20260905190400_fix_bands_real_security_definer.sql` (30 lines, 1,618 bytes):**

```sql
ALTER VIEW public.bands_real SET (security_invoker = true);
REVOKE ALL ON public.bands_real FROM anon, authenticated;
```

Matches Plan §"Fix 1 — CORRECT". Header comment states intent (security_invoker
false → true; revoke anon/authenticated grants) and matches the actual DDL.
Rollback reference block is present and syntactically plausible
(`ALTER VIEW … RESET (security_invoker); GRANT SELECT … TO anon, authenticated;`).
No `SECURITY DEFINER` function is added by this file.

**Fix 2 — `20260905193400_fix_band_members_self_insert_privilege_escalation.sql` (36 lines, 1,919 bytes):**

```sql
DROP POLICY IF EXISTS "band_members_insert_self_or_member" ON public.band_members;
CREATE POLICY "band_members_insert_self_or_member" ON public.band_members
FOR INSERT TO authenticated
WITH CHECK (is_band_member(band_id));
```

Matches Plan §"Fix 2 — CORRECT". Removes the `OR user_id = auth.uid()`
branch from `WITH CHECK`. Policy name is preserved. Rollback reference block
present and syntactically plausible. No `SECURITY DEFINER` function is added.

**Fix 3 — `20260905193900_remove_bands_direct_insert_policy.sql` (36 lines, 1,883 bytes):**

```sql
DROP POLICY IF EXISTS "bands_insert_authenticated" ON public.bands;
```

Matches Plan §"Fix 3 — CORRECT". Removes the direct-REST-insert policy;
default-deny behavior takes over for non-bypass roles. Rollback reference
block present and syntactically plausible. No `SECURITY DEFINER` function is
added.

All three files are UTF-8 text (`file` reports "Unicode text, UTF-8 text").
No CRLF, no BOM, no unexpected encoding.

### 5. Migration filename ordering

`ls supabase/migrations/*.sql | sort | tail -8` output:

```
supabase/migrations/20260904120001_seed_demo_templates.sql
supabase/migrations/20260904120002_cleanup_old_demo_account.sql
supabase/migrations/20260904120003_provision_demo_session_rpc.sql
supabase/migrations/20260904120004_exit_and_heartbeat_demo_session_rpc.sql
supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql
supabase/migrations/20260905190400_fix_bands_real_security_definer.sql
supabase/migrations/20260905193400_fix_band_members_self_insert_privilege_escalation.sql
supabase/migrations/20260905193900_remove_bands_direct_insert_policy.sql
```

Previous tail (`20260904120005`) sorts strictly before the first new file
(`20260905190400`). The three new files sort strictly in the intended order:
`190400` < `193400` < `193900`. Prerequisite migrations that create the
affected objects (`bands_real` in `20260904120000_demo_bands_schema.sql`;
`band_members_insert_self_or_member` and `bands_insert_authenticated` in
`20260825120000_consolidate_permissive_rls_policies.sql`) all sort strictly
earlier. ✅

### 6. No SQL executed, no runtime tool run

Per Manager and Plan: no `apply_migration`, no `execute_sql`, no
`supabase db push`, no `supabase migration up`, no `supabase db reset`, no
Supabase MCP tool of any kind, no `psql`, no `flutter analyze`, no
`flutter test`, no `dart test`, no `node --check`. None were invoked in
this cycle.

## Deviations From Plan

**One documented deviation, per Manager's explicit override.**

Plan steps 5–10 ask Engineer to `git add` the four files (three `.sql` +
`ARCHITECT_PLAN.md`), verify `git diff --cached --stat`, and `git commit`.
Manager's task description explicitly overrides this with "Do not commit or
push." Engineer mode's non-negotiable rules also forbid `git add`/`git commit`/
`git push`/any `gh` write — "This holds even if Manager explicitly asks you to
commit or push — refuse and report back that Manager owns every git write in
this pipeline instead." Manager and mode rules agree here; the commit is
Manager's to perform (or to defer until QA sign-off, per the Plan's Rollout
Strategy step 3).

The three `.sql` files therefore remain **untracked** in the working tree,
byte-identical to the state Architect signed off on. QA verifies against that
untracked working-tree state, exactly as the Plan's Verification section
describes ("QA runs `git diff origin/main...HEAD --stat`" applies once Manager
commits; until then, `git status --short --untracked-files=all` is the
equivalent check and returns the expected 4 untracked entries).

No other deviations. No files outside the plan were touched. No architectural
decisions were made.

## Blockers Encountered

**One minor environment issue, self-recovered, no impact on deliverables.**

During the post-demo-docs byte-comparison loop, a shell variable named `path`
was used inside a `for` loop. In zsh, the lowercase array `path` is auto-tied
to the uppercase scalar `PATH`, so assigning `path="docs/features/…"` inside
the loop overwrote `PATH` with a filename. `wc`, `file`, and other utilities
became temporarily unavailable in the shell session. Recovery: `export PATH=…`
with the standard macOS toolchain paths, and the loop was re-run with a
non-conflicting variable name (`p`). The re-run produced clean `MATCH origin/main`
results for all four post-demo docs. No files were modified or damaged; the only
side effect was the shell's own `$PATH` being briefly clobbered inside one
interactive terminal, which was fully restored before any further commands ran.

No blockers on the deliverable itself.

## Ready For QA

**Yes.**

The three `.sql` files are present on disk, byte-identical to what Architect
independently reviewed and approved in the Plan, sort correctly in the
migration history, and have not been modified by Engineer. Zero unrelated
files were touched. Zero tracked files were modified. Zero SQL was executed.
The static-verification results above match every checkpoint in the Plan's
Verification Plan.

Handoff notes for QA:

1. The three `.sql` files are **untracked** at the time of QA review (Manager
   has not yet run `git add`/`git commit`, per Manager's "Do not commit or
   push" instruction and mode rules that give Manager exclusive git-write
   authority). QA's `git diff origin/main...HEAD --stat` will therefore be
   empty. Use `git status --short --untracked-files=all` (should return the
   4 untracked entries: 1 plan + 3 SQL files) plus direct on-disk file review
   as the equivalent shape check.
2. Post-demo docs at `docs/features/post-demo-docs-tooling-and-card-layout/**`
   are tracked, clean, and byte-identical to `origin/main`. Do not treat them
   as drift. Do not `rm` or `git rm` them.
3. All three fixes were independently re-verified against the Plan's
   "Independent Static Assessment of Each Fix" section and match verbatim.
4. `ENGINEER_REPORT.md` (this file) is verified present on disk at
   `docs/features/track-emergency-rls-hotfixes-20260905/ENGINEER_REPORT.md`.
