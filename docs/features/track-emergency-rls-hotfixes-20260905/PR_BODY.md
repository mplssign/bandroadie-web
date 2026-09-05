## Summary

Repository-tracking-only chore. Commits three migrations for CRITICAL Supabase advisor findings that were fixed directly in prod earlier today (2026-09-05) as an emergency response, so the migration history matches the live schema. **No SQL is executed by this PR — the fixes are already live.**

## Migrations

1. `20260905190400_fix_bands_real_security_definer.sql` — sets `security_invoker = true` on `bands_real` and revokes `anon`/`authenticated` grants. Closes an RLS bypass that exposed every band via `GET /rest/v1/bands_real`.
2. `20260905193400_fix_band_members_self_insert_privilege_escalation.sql` — removes the `OR user_id = auth.uid()` branch on `band_members_insert_self_or_member`, which allowed any authenticated or anon caller to self-insert as `admin` into any band.
3. `20260905193900_remove_bands_direct_insert_policy.sql` — drops `bands_insert_authenticated`. Safe because `create_band()` and `provision_demo_session()` are both `SECURITY DEFINER` and no client-side insert into `public.bands` exists.

## Verification

- QA verdict: APPROVED (static security review, regression risk LOW).
- Independent Architect review of each fix's SQL against stated intent — all three correct as written.
- Filename/timestamp ordering strict: `20260904120005 < 20260905190400 < 20260905193400 < 20260905193900`.
- All three migrations use idempotent DDL/DCL and include documented rollback SQL in header comments.
- No `.insert()` into `public.bands` or `public.band_members` exists in `lib/**` or `supabase/functions/**`.
- No Supabase MCP action, `apply_migration`, `execute_sql`, `supabase db push`, or dashboard action was performed by the pipeline. Verification was static-only.

## Scope

- Backend/Supabase migration files only. No `lib/` changes. No tooling, config, or CI changes.
- Three feature review docs also included: [ARCHITECT_PLAN.md](docs/features/track-emergency-rls-hotfixes-20260905/ARCHITECT_PLAN.md), [ENGINEER_REPORT.md](docs/features/track-emergency-rls-hotfixes-20260905/ENGINEER_REPORT.md), [QA_REPORT.md](docs/features/track-emergency-rls-hotfixes-20260905/QA_REPORT.md).
