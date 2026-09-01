## 1. Feature Slug

`bug/notification-trigger-gaps`

## 2. Problem Summary

Gig, rehearsal, and block-out creation notifications have multiple content and delivery defects in live Postgres trigger functions. Verified issues are: block-out creation emits no notification, gig title is event name instead of fixed title, rehearsal body date omits year, and gig actor name falls back to a generic string due to invalid user-name lookup. The defects are server-side and affect all client platforms because notification rows are authored in database trigger functions.

## 3. Root Cause

Primary root cause (HIGH confidence): trigger-function drift and schema drift.

- `notify_gig_created()` still reads `users.name` (column does not exist), so actor lookup errors and falls back to `A band member`.
- `notify_gig_created()` sets `v_title := COALESCE(NEW.name, 'New Gig')` instead of fixed `Gig Scheduled`.
- `notify_rehearsal_created()` formats date with `TO_CHAR(NEW.date, 'MON FMDD')`, omitting year by design from prior recurring-rehearsal copy.
- `notify_blockout_created()` is not bound to the live `block_dates` table (no trigger exists).
- Additional confirmed blocker: live `notify_blockout_created()` expects `NEW.start_date` / `NEW.end_date`, but live `block_dates` schema has `date` only. Even if a trigger were attached today, function logic would not match table shape.

Failure-mode investigation results:

1. Trigger not called: confirmed for block-outs (no trigger on `block_dates`) -> primary for missing block-out notifications.
2. Recipient resolution fails: not observed in `notify_band_members`; member loop is present and actor excluded intentionally.
3. Preference gate blocks send: not primary; `should_receive_notification()` defaults true on missing prefs and checks expected toggles.
4. Token missing/stale: not implicated in the content defects; could affect delivery generally but not these four reported content/path issues.
5. Edge function/backend error: not primary for these defects; notification-row creation defects happen before push delivery.
6. RLS blocks read: not primary in this path; authoring functions are `SECURITY DEFINER` owned by `postgres`.

## 4. Reference Docs Consulted

Read fully from `docs/reference/notifications/`:

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/notifications.md`

Note: notification reference docs contain internal inconsistencies (webhook vs cron delivery notes; older copy patterns), but live database introspection was used as source of truth for current behavior.

## 5. Existing System Analysis

Current event-created notification flow:

1. Inserts into `gigs` / `rehearsals` fire `AFTER INSERT` triggers (`gig_created_notification`, `rehearsal_created_notification`).
2. Trigger functions compose title/body/metadata and call `notify_band_members(...)`.
3. `notify_band_members(...)` iterates band members, checks `should_receive_notification(...)`, inserts rows into `notifications`.
4. `on_notification_inserted` trigger on `notifications` calls `trigger_send_push_notification()` to invoke Edge Function `send-push` asynchronously.

Verified live definitions:

- `users` columns are `first_name`/`last_name`; `name` does not exist.
- `notify_gig_created()` and `notify_blockout_created()` still query `COALESCE(name, 'A band member') FROM users`.
- `notify_rehearsal_created()` correctly uses `first_name`/`last_name` fallback but uses yearless date format.
- `block_dates` table exists; `block_out_dates` does not.
- No trigger exists on `block_dates`.

Audit for sibling functions referencing nonexistent `users.name` inside `notify_*` functions:

- `notify_gig_created` -> affected
- `notify_blockout_created` -> affected
- `notify_rehearsal_created` -> unaffected (already using first/last name)
- No additional `notify_*` sibling function with `FROM users` found beyond these three.

## 6. Proposed Solution

Apply one targeted SQL migration that does all of the following:

1. Replace `notify_gig_created()`:

- All three functions must use this exact actor lookup expression, verbatim, so the implementations cannot drift from each other:

```sql
   SELECT COALESCE(
     NULLIF(TRIM(first_name), ''),
     SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
     'Someone'
   ) INTO v_actor_name
   FROM users
   WHERE id = auth.uid();
```

- Use the same exact expression in `notify_gig_created()`, `notify_rehearsal_created()`, and `notify_blockout_created()`.
- Title decision for this migration: choose the minimal-scope fix for the reported bug. `NEW.is_potential = true` gigs keep their current title behavior, `COALESCE(NEW.name, 'New Gig')`, unchanged. Only the non-potential branch gets the fixed `Gig Scheduled` title. This matches the report's scope (confirmed gigs), and no parity decision is required for potential gigs in this migration.

2. Replace `notify_rehearsal_created()`:

- keep recurring-series parent-only behavior.
- use the exact same actor lookup expression above.
- update date formatting to include year in both one-off and recurring variants (for example `MON FMDD, YYYY` uppercased).

3. Replace `notify_blockout_created()`:

- align function with live `block_dates` schema (`NEW.date`), removing legacy `start_date/end_date` dependence.
- all three functions must use this exact actor lookup expression, verbatim:

```sql
   SELECT COALESCE(
     NULLIF(TRIM(first_name), ''),
     SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
     'Someone'
   ) INTO v_actor_name
   FROM users
   WHERE id = auth.uid();
```

- preserve fixed title `Member Unavailable` and year-inclusive date copy.

4. Ensure block-out trigger is attached to live table:

- `DROP TRIGGER IF EXISTS blockout_created_notification ON public.block_dates;`
- `CREATE TRIGGER blockout_created_notification AFTER INSERT ON public.block_dates FOR EACH ROW EXECUTE FUNCTION notify_blockout_created();`

5. Keep `notify_band_members()` and push-delivery trigger path unchanged.

Must not change:

- notification preference schema or behavior.
- push Edge Function contract.
- unrelated notification types.
- Flutter/Dart code.

## 7. Database Impact

- Migrations: affected (new migration required).
- RLS policies: unaffected.
- RPC functions: unaffected.
- Trigger logic: affected (`gigs`, `rehearsals`, `block_dates` event-created notification triggers/functions).

## 8. Flutter Architecture Changes

None.

- State management: unaffected.
- Widgets/screens: unaffected.
- Repositories/controllers: unaffected.

## 9. Files to Create

- `supabase/migrations/<timestamp>_fix_notification_trigger_gaps.sql`
  - Justification: required to atomically update trigger functions and attach missing `block_dates` trigger.

## 10. Files to Modify

| File                                                                | What changes                                                                                                                                                                              |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<timestamp>_fix_notification_trigger_gaps.sql` | New migration with `CREATE OR REPLACE FUNCTION` updates for `notify_gig_created`, `notify_rehearsal_created`, `notify_blockout_created`, plus `CREATE TRIGGER` binding for `block_dates`. |

## 11. Files Off-Limits

| File                                                     | Reason                                                                       |
| -------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `lib/**`                                                 | This bug is DB-trigger logic only; no Flutter behavior change required.      |
| `supabase/functions/send-push/index.ts`                  | Delivery transport is not root cause for these defects.                      |
| `supabase/migrations/*` (existing historical migrations) | Preserve migration history; fix via additive migration only.                 |
| `ios/**`, `android/**`, `web/**`, `macos/**`             | Platform clients are unaffected by server-side trigger copy/binding defects. |

## 12. System Impact Map

| System                                 | Impact                                                 |
| -------------------------------------- | ------------------------------------------------------ |
| Gigs                                   | affected                                               |
| Rehearsals                             | affected                                               |
| Setlists / Catalog                     | unaffected                                             |
| Members / RBAC                         | unaffected                                             |
| Auth / Session                         | unaffected                                             |
| Routing                                | unaffected                                             |
| Notifications                          | affected                                               |
| Platform (iOS / Android / Web / macOS) | affected (server-side behavior visible on all clients) |

## 13. Regression Risk

`MEDIUM`

Rationale: change touches three trigger functions and one trigger binding in production DB path, but scope is narrowly constrained to notification-content generation and one missing trigger attachment. No auth flow, app init, routing, or Flutter code changes are involved.

## 14. Engineer Task Breakdown

1. Create migration file `supabase/migrations/<timestamp>_fix_notification_trigger_gaps.sql`.
2. Recreate `notify_gig_created()` with the exact actor-name lookup SQL used by the live rehearsal function and the fixed title `Gig Scheduled` for confirmed gigs only; keep `NEW.is_potential` title behavior unchanged.
3. Recreate `notify_rehearsal_created()` to use the same exact actor lookup SQL and include year in all date text variants while preserving recurring-parent guard and recurrence copy behavior.
4. Recreate `notify_blockout_created()` against `block_dates.date` schema with the same exact actor lookup SQL, fixed title `Member Unavailable`, and year-inclusive body.
5. Add trigger DDL to bind `blockout_created_notification` to `public.block_dates` AFTER INSERT.
6. Ensure function definitions include `SECURITY DEFINER` and `SET search_path = public`.
7. Run Tier 1 SQL checks before deploy.
8. Execute `supabase db push` (or equivalent migration apply process).
9. Run the post-deploy verification query after deploy; this migration does not include insert-based integration tests because the fix is limited to trigger copy/ownership and text formatting, not a new event flow.
10. Record SQL evidence in `ENGINEER_REPORT.md` and include exact queries/results summaries.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

(All tests run against current DB, with zero schema changes applied. Do not call functions being replaced.)

```sql
-- PRE-DEPLOY TEST 1: Verify users schema has no `name` column and does have first/last names.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'users'
  AND column_name IN ('name', 'first_name', 'last_name')
ORDER BY column_name;
```

```sql
-- PRE-DEPLOY TEST 2: Verify current trigger bindings for event-created notifications.
SELECT event_object_table, trigger_name, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN ('gigs', 'rehearsals', 'block_dates', 'block_out_dates')
ORDER BY event_object_table, trigger_name;
```

```sql
-- PRE-DEPLOY TEST 3: Verify block_dates schema (date-only), confirming mismatch risk in old blockout function.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'block_dates'
ORDER BY ordinal_position;
```

```sql
-- PRE-DEPLOY TEST 4: Inspect function text for known defects before replacement.
SELECT proname,
       (pg_get_functiondef(p.oid) ILIKE '%COALESCE(name,%') AS uses_missing_name_column,
       (pg_get_functiondef(p.oid) ILIKE '%MON FMDD%') AS uses_yearless_fmt
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND proname IN ('notify_gig_created', 'notify_rehearsal_created', 'notify_blockout_created')
ORDER BY proname;
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

This migration is intentionally narrow. The real verification is the static function-text checks in Tier 1 plus the production sample query below. The migration does not include insert-based integration tests because the defect is limited to trigger copy/ownership and title/date text, not to a new event flow or schema contract.

```sql
-- POST-DEPLOY TEST 1: Verify updated function definitions contain expected fixes.
SELECT proname,
       (pg_get_functiondef(p.oid) ILIKE '%first_name%') AS has_first_name_lookup,
       (pg_get_functiondef(p.oid) ILIKE '%Gig Scheduled%') AS has_fixed_gig_title,
       (pg_get_functiondef(p.oid) ILIKE '%MON FMDD, YYYY%') AS has_year_in_rehearsal_fmt,
       (pg_get_functiondef(p.oid) ILIKE '%NEW.date%') AS blockout_uses_date_column
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND proname IN ('notify_gig_created', 'notify_rehearsal_created', 'notify_blockout_created')
ORDER BY proname;
```

```sql
-- POST-DEPLOY TEST 2: Verify blockout trigger exists on the live table.
SELECT event_object_table, trigger_name, action_timing, event_manipulation, action_statement
FROM information_schema.triggers
WHERE trigger_schema='public'
  AND event_object_table='block_dates'
  AND trigger_name='blockout_created_notification';
```

```sql
-- PRODUCTION VERIFICATION QUERY: sample recent notification rows for the 7-day window after deploy.
SELECT type,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE type='gig_created' AND title='Gig Scheduled') AS gig_title_ok,
       COUNT(*) FILTER (WHERE type='rehearsal_created' AND body ~ ', [0-9]{4}$') AS rehearsal_year_ok,
       COUNT(*) FILTER (WHERE type='blockout_created' AND body ILIKE '%unavailable on%') AS blockout_copy_ok
FROM notifications
WHERE created_at > NOW() - INTERVAL '7 days'
  AND type IN ('gig_created','rehearsal_created','blockout_created')
GROUP BY type
ORDER BY type;
```

This is the real verification for the migration: static function-text checks in Tier 1 plus the 7-day production sample query above. There are no runnable insert-based Tier 2 integration tests for this migration, because the migration is a server-side trigger copy/ownership fix, not a new user flow requiring fixture data inserts.

## 16. QA Regression Areas

- Event creation notification (primary):
  - Gig created -> title is fixed `Gig Scheduled`; body uses creator first name and includes year.
  - Rehearsal created (one-off + recurring parent) -> body includes year.
  - Block-out created -> notification now emitted to other band members.
- Other notification types:
  - Potential gig creation still behaves correctly.
  - Existing unrelated notification flows (setlists and others) unchanged.
- Notification preference toggles:
  - Verify disabled categories still suppress notifications.
  - Verify master toggle still suppresses all.
- iOS push end-to-end:
  - Notification row creation -> push dispatch still works.
  - Actor exclusion still enforced (creator does not receive own notification).

## 17. Rollout / Migration Strategy

1. Ship as a single additive migration in one deploy unit.
2. Run Tier 1 checks pre-deploy.
3. Apply migration (`supabase db push`).
4. Run Tier 2 verification immediately.
5. Monitor notification creation counts and push logs for 24 hours.
6. Rollback approach: deploy a follow-up migration that restores previous function bodies/trigger binding only if critical regression appears.

## 18. Out of Scope

- Rewriting notification delivery architecture (cron vs webhook/path refactors).
- New notification types or edit/delete event notifications.
- UI/wording overhaul beyond specified bug fixes.
- Device token lifecycle optimizations.
- Any Flutter, mobile platform, or routing changes.
