# Engineer Report

## Feature Slug

bug/notification-trigger-gaps

## Feature Title

Notification Trigger Gaps

## Goal

Repair the database trigger functions for gig, rehearsal, and blockout creation notifications, and bind the missing `block_dates` trigger. This was implemented as a single additive SQL migration in the project’s Supabase migration folder.

## Architect Tasks Completed

- [x] Task 1 — Created the migration file `supabase/migrations/20260901170853_fix_notification_trigger_gaps.sql`.
- [x] Task 2 — Rebuilt `notify_gig_created()` using the exact actor-name lookup SQL and corrected non-potential title logic.
- [x] Task 3 — Rebuilt `notify_rehearsal_created()` using the exact actor-name lookup SQL and year-inclusive date formatting.
- [x] Task 4 — Rebuilt `notify_blockout_created()` against `public.block_dates` and corrected the date column usage.
- [x] Task 5 — Added the `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER` binding for `blockout_created_notification` on `public.block_dates`.
- [x] Task 6 — Added `SECURITY DEFINER` and `SET search_path = public` to the recreated functions.
- [ ] Task 7 — Tier 1 live checks: blocked because the migration push failed before the migration was able to apply.
- [ ] Task 8 — `supabase db push --linked` apply: blocked by local/remote migration history mismatch.
- [ ] Task 9 — Post-deploy Tier 2 verification: blocked for the same reason.
- [ ] Task 10 — Final report and commit: completed locally, but deployment is still blocked.

## Files Created

- `supabase/migrations/20260901170853_fix_notification_trigger_gaps.sql`
- `docs/features/notification-trigger-gaps/ENGINEER_REPORT.md`

## Files Modified

- `supabase/migrations/20260901170853_fix_notification_trigger_gaps.sql`

## Migration SQL Content (created, not yet applied)

```sql
CREATE OR REPLACE FUNCTION notify_gig_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_gig_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_notification_type TEXT;
BEGIN
  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_gig_date := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_gig_date := UPPER(v_gig_date);

  IF NEW.is_potential THEN
    v_notification_type := 'potential_gig_created';
    v_body := v_actor_name || ' created a potential gig for ' || v_gig_date;
    v_title := COALESCE(NEW.name, 'New Gig');
  ELSE
    v_notification_type := 'gig_created';
    v_body := v_actor_name || ' created a gig for ' || v_gig_date;
    v_title := 'Gig Scheduled';
  END IF;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    v_notification_type,
    v_title,
    v_body,
    jsonb_build_object('gig_id', NEW.id, 'gig_date', NEW.date)
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION notify_rehearsal_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_rehearsal_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_recurrence_text TEXT;
  v_day_names TEXT[];
BEGIN
  IF NEW.parent_rehearsal_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_rehearsal_date := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_rehearsal_date := UPPER(v_rehearsal_date);

  v_title := 'Rehearsal Scheduled';

  IF NEW.is_recurring AND NEW.recurrence_frequency IS NOT NULL THEN
    v_day_names := ARRAY['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];

    IF NEW.recurrence_days IS NOT NULL AND array_length(NEW.recurrence_days, 1) > 0 THEN
      SELECT string_agg(v_day_names[d + 1], ', ')
      INTO v_recurrence_text
      FROM unnest(NEW.recurrence_days) AS d
      ORDER BY d;

      v_recurrence_text := CASE NEW.recurrence_frequency
        WHEN 'weekly' THEN 'on ' || v_recurrence_text
        WHEN 'biweekly' THEN 'every other ' || v_recurrence_text
        WHEN 'monthly' THEN 'monthly on ' || v_recurrence_text
        ELSE 'recurring'
      END;
    ELSE
      v_recurrence_text := CASE NEW.recurrence_frequency
        WHEN 'weekly' THEN 'weekly'
        WHEN 'biweekly' THEN 'biweekly'
        WHEN 'monthly' THEN 'monthly'
        ELSE 'recurring'
      END;
    END IF;

    v_body := v_actor_name || ' scheduled a rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
  ELSE
    v_body := v_actor_name || ' scheduled a rehearsal for ' || v_rehearsal_date;
  END IF;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    'rehearsal_created',
    v_title,
    v_body,
    jsonb_build_object(
      'rehearsal_id', NEW.id,
      'rehearsal_date', NEW.date,
      'is_recurring', COALESCE(NEW.is_recurring, FALSE),
      'recurrence_frequency', NEW.recurrence_frequency
    )
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION notify_blockout_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_date_text TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_title := 'Member Unavailable';
  v_date_text := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_date_text := UPPER(v_date_text);

  v_body := v_actor_name || ' is unavailable on ' || v_date_text;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    'blockout_created',
    v_title,
    v_body,
    jsonb_build_object(
      'blockout_id', NEW.id,
      'date', NEW.date
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS blockout_created_notification ON public.block_dates;
CREATE TRIGGER blockout_created_notification
  AFTER INSERT ON public.block_dates
  FOR EACH ROW
  EXECUTE FUNCTION notify_blockout_created();
```

## Tier 1 / Tier 2 verification output

### Attempted live apply command

```text
cd /Users/tonyholmes/apps/bandroadie && supabase db push --linked --yes
Initialising login role...
Connecting to remote database...
{"_tag":"Error","error":{"code":"LegacyDbPushMissingLocalError","message":"Remote migration versions not found in local migrations directory.","suggestion":"Make sure your local git repo is up-to-date. If the error persists, try repairing the migration history table:\n\u001b[1msupabase migration repair --status reverted 20260829013242\u001b[22m\n\nAnd update local migrations to match remote database:\n\u001b[1msupabase db pull\u001b[22m\n"}}
```

### Attempted direct live query call

```text
cd /Users/tonyholmes/apps/bandroadie && supabase db query --linked "SELECT 1 AS ok;"
Initialising login role...
{"_tag":"Error","error":{"code":"LegacyDbConfigConnectTempRoleError","message":"failed to connect as temp role: failed to connect to `host=aws-1-us-east-2.pooler.supabase.com user=cli_login_postgres.nekwjxvgbveheooyorjo database=postgres`: server error (FATAL: (EAUTHQUERY) unsupported or invalid secret format (SQLSTATE XX000))","suggestion":"Connect to your database by setting the env var correctly: SUPABASE_DB_PASSWORD"}}
```

### Result

The live Supabase project could not be verified or migrated because the local CLI state is not aligned with the remote migration history and the required DB secret is not available in this environment. This prevented the required Tier 1 live schema checks and all Tier 2 post-deploy checks from running against the production-linked database.

## Trigger binding confirmation

The trigger binding line was added to the migration file as required:

```sql
DROP TRIGGER IF EXISTS blockout_created_notification ON public.block_dates;
CREATE TRIGGER blockout_created_notification
  AFTER INSERT ON public.block_dates
  FOR EACH ROW
  EXECUTE FUNCTION notify_blockout_created();
```

This binding is present in the migration file, but it was not able to be applied to the live linked project because the apply step was blocked by the remote migration-history mismatch noted above.

## Blockers Encountered

- `supabase db push --linked --yes` failed with `LegacyDbPushMissingLocalError` because the remote migration history is not present in the local migrations directory.
- `supabase db query --linked` failed with `LegacyDbConfigConnectTempRoleError` because the required `SUPABASE_DB_PASSWORD` is unavailable in this environment.
- Because of these blockers, the migration could not be applied to the linked project, so live Tier 1 and Tier 2 SQL verification could not complete.

## Ready For QA

No — deployment is blocked by Supabase CLI state and missing DB credentials. Once the migration history is repaired and the DB secret is available, the migration file is ready to be applied and revalidated.

---

## Addendum 2 — Notification Title Standardization (2026-09-01)

### New migration file

`supabase/migrations/20260901204500_standardize_notification_titles.sql`

### Full SQL applied

```sql
-- ============================================================================
-- Standardize notification titles across gig/rehearsal/blockout create flows
-- Purpose: enforce final product title contract without changing type semantics.
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_gig_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_gig_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_notification_type TEXT;
BEGIN
  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_gig_date := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_gig_date := UPPER(v_gig_date);

  IF NEW.is_potential THEN
    v_notification_type := 'potential_gig_created';
    v_body := v_actor_name || ' created a potential gig for ' || v_gig_date;
    v_title := 'Potential Gig Created';
  ELSE
    v_notification_type := 'gig_created';
    v_body := v_actor_name || ' created a gig for ' || v_gig_date;
    v_title := 'Gig Scheduled';
  END IF;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    v_notification_type,
    v_title,
    v_body,
    jsonb_build_object('gig_id', NEW.id, 'gig_date', NEW.date)
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION notify_rehearsal_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_rehearsal_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_recurrence_text TEXT;
  v_day_names TEXT[];
BEGIN
  IF NEW.parent_rehearsal_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_rehearsal_date := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_rehearsal_date := UPPER(v_rehearsal_date);

  IF NEW.is_potential THEN
    v_title := 'Potential Rehearsal Created';
  ELSE
    v_title := 'Rehearsal Scheduled';
  END IF;

  IF NEW.is_recurring AND NEW.recurrence_frequency IS NOT NULL THEN
    v_day_names := ARRAY['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];

    IF NEW.recurrence_days IS NOT NULL AND array_length(NEW.recurrence_days, 1) > 0 THEN
      SELECT string_agg(v_day_names[d + 1], ', ')
      INTO v_recurrence_text
      FROM unnest(NEW.recurrence_days) AS d
      ORDER BY d;

      v_recurrence_text := CASE NEW.recurrence_frequency
        WHEN 'weekly' THEN 'on ' || v_recurrence_text
        WHEN 'biweekly' THEN 'every other ' || v_recurrence_text
        WHEN 'monthly' THEN 'monthly on ' || v_recurrence_text
        ELSE 'recurring'
      END;
    ELSE
      v_recurrence_text := CASE NEW.recurrence_frequency
        WHEN 'weekly' THEN 'weekly'
        WHEN 'biweekly' THEN 'biweekly'
        WHEN 'monthly' THEN 'monthly'
        ELSE 'recurring'
      END;
    END IF;

    IF NEW.is_potential THEN
      v_body := v_actor_name || ' scheduled a potential rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
    ELSE
      v_body := v_actor_name || ' scheduled a rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
    END IF;
  ELSE
    IF NEW.is_potential THEN
      v_body := v_actor_name || ' scheduled a potential rehearsal for ' || v_rehearsal_date;
    ELSE
      v_body := v_actor_name || ' scheduled a rehearsal for ' || v_rehearsal_date;
    END IF;
  END IF;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    'rehearsal_created',
    v_title,
    v_body,
    jsonb_build_object(
      'rehearsal_id', NEW.id,
      'rehearsal_date', NEW.date,
      'is_recurring', COALESCE(NEW.is_recurring, FALSE),
      'recurrence_frequency', NEW.recurrence_frequency
    )
  );

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION notify_blockout_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_date_text TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_title := 'Blockout Scheduled';
  v_date_text := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_date_text := UPPER(v_date_text);

  v_body := v_actor_name || ' is unavailable on ' || v_date_text;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    'blockout_created',
    v_title,
    v_body,
    jsonb_build_object(
      'blockout_id', NEW.id,
      'date', NEW.date
    )
  );

  RETURN NEW;
END;
$$;
```

### Apply-step outcome

Blocked by Supabase CLI login/session state. The required migration apply command was attempted:

```bash
cd /Users/tonyholmes/apps/bandroadie && supabase db push --linked --yes
```

Result:

```text
Initialising login role...
```

The terminal timed out after 180000 ms without any further authenticated connection result, with no credential prompt, no migration summary, and no SQL execution output. This is consistent with a stalled CLI login/session issue and prevented any database verification against the linked project `nekwjxvgbveheooyorjo`.

### Verification query and output

The required verification SQL from the plan was:

```sql
WITH f AS (
  SELECT
    p.proname,
    pg_get_functiondef(p.oid) AS def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('notify_gig_created', 'notify_rehearsal_created', 'notify_blockout_created')
)
SELECT
  MAX((proname = 'notify_gig_created' AND def ILIKE '%Potential Gig Created%')::int)::boolean AS gig_has_potential_created_title,
  MAX((proname = 'notify_gig_created' AND def ILIKE '%Gig Scheduled%')::int)::boolean AS gig_has_scheduled_title,
  MAX((proname = 'notify_gig_created' AND def ILIKE '%''potential_gig_created''%')::int)::boolean AS gig_keeps_potential_gig_type,
  MAX((proname = 'notify_gig_created' AND def ILIKE '%''gig_created''%')::int)::boolean AS gig_keeps_gig_created_type,

  MAX((proname = 'notify_rehearsal_created' AND def ILIKE '%Potential Rehearsal Created%')::int)::boolean AS rehearsal_has_potential_created_title,
  MAX((proname = 'notify_rehearsal_created' AND def ILIKE '%Rehearsal Scheduled%')::int)::boolean AS rehearsal_has_scheduled_title,
  MAX((proname = 'notify_rehearsal_created' AND def ILIKE '%''rehearsal_created''%')::int)::boolean AS rehearsal_keeps_single_type,

  MAX((proname = 'notify_blockout_created' AND def ILIKE '%Blockout Scheduled%')::int)::boolean AS blockout_has_scheduled_title,
  MAX((proname = 'notify_blockout_created' AND def ILIKE '%''blockout_created''%')::int)::boolean AS blockout_keeps_type,

  BOOL_OR(def ILIKE '%potential_rehearsal_created%') AS introduces_forbidden_potential_rehearsal_type,
  BOOL_OR(def ILIKE '%Member Unavailable%') AS still_contains_old_blockout_title,
  BOOL_OR(def ILIKE '%Potential Rehearsal Scheduled%') AS still_contains_old_potential_rehearsal_title,
  BOOL_OR(def ILIKE '%COALESCE(NEW.name, ''New Gig'')%') AS still_contains_old_potential_gig_title_logic
FROM f;
```

Execution result:

```text
No output — the remote database was not reached because the `supabase db push --linked --yes` command stalled during CLI auth initialization before migration execution.
```

### Historical migration integrity check

No diffs were made against the two previously applied migration files:

- `supabase/migrations/20260901170853_fix_notification_trigger_gaps.sql`
- `supabase/migrations/20260901193000_fix_potential_rehearsal_title.sql`

This was confirmed by `git diff -- <those files>` returning no output.

### Final status

The addendum-2 migration file was created locally as required, but the apply-and-verify step is blocked by the Supabase CLI state in this environment. No further retries or SQL modifications were performed.

## Addendum - Potential Rehearsal Title Fix (2026-09-01)

### Migration file

- `supabase/migrations/20260901193000_fix_potential_rehearsal_title.sql`

### Full SQL applied

```sql
-- ============================================================================
-- Fix potential rehearsal notification title/body wording
-- Purpose: preserve notification type while differentiating potential rehearsal
-- copy in notify_rehearsal_created().
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_rehearsal_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_name TEXT;
  v_rehearsal_date TEXT;
  v_title TEXT;
  v_body TEXT;
  v_recurrence_text TEXT;
  v_day_names TEXT[];
BEGIN
  IF NEW.parent_rehearsal_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(
    NULLIF(TRIM(first_name), ''),
    SPLIT_PART(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''), ' ', 1),
    'Someone'
  ) INTO v_actor_name
  FROM users
  WHERE id = auth.uid();

  v_rehearsal_date := TO_CHAR(NEW.date, 'MON FMDD, YYYY');
  v_rehearsal_date := UPPER(v_rehearsal_date);

  IF NEW.is_potential THEN
    v_title := 'Potential Rehearsal Scheduled';
  ELSE
    v_title := 'Rehearsal Scheduled';
  END IF;

  IF NEW.is_recurring AND NEW.recurrence_frequency IS NOT NULL THEN
    v_day_names := ARRAY['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'];

    IF NEW.recurrence_days IS NOT NULL AND array_length(NEW.recurrence_days, 1) > 0 THEN
      SELECT string_agg(v_day_names[d + 1], ', ')
      INTO v_recurrence_text
      FROM unnest(NEW.recurrence_days) AS d
      ORDER BY d;

      v_recurrence_text := CASE NEW.recurrence_frequency
        WHEN 'weekly' THEN 'on ' || v_recurrence_text
        WHEN 'biweekly' THEN 'every other ' || v_recurrence_text
        WHEN 'monthly' THEN 'monthly on ' || v_recurrence_text
        ELSE 'recurring'
      END;
    ELSE
      v_recurrence_text := CASE NEW.recurrence_frequency
        WHEN 'weekly' THEN 'weekly'
        WHEN 'biweekly' THEN 'biweekly'
        WHEN 'monthly' THEN 'monthly'
        ELSE 'recurring'
      END;
    END IF;

    IF NEW.is_potential THEN
      v_body := v_actor_name || ' scheduled a potential rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
    ELSE
      v_body := v_actor_name || ' scheduled a rehearsal ' || v_recurrence_text || ' starting ' || v_rehearsal_date;
    END IF;
  ELSE
    IF NEW.is_potential THEN
      v_body := v_actor_name || ' scheduled a potential rehearsal for ' || v_rehearsal_date;
    ELSE
      v_body := v_actor_name || ' scheduled a rehearsal for ' || v_rehearsal_date;
    END IF;
  END IF;

  PERFORM notify_band_members(
    NEW.band_id,
    auth.uid(),
    'rehearsal_created',
    v_title,
    v_body,
    jsonb_build_object(
      'rehearsal_id', NEW.id,
      'rehearsal_date', NEW.date,
      'is_recurring', COALESCE(NEW.is_recurring, FALSE),
      'recurrence_frequency', NEW.recurrence_frequency
    )
  );

  RETURN NEW;
END;
$$;
```

### Apply step outcome

```text
cd /Users/tonyholmes/apps/bandroadie && supabase db push --linked --yes
Initialising login role...
Connecting to remote database...
Do you want to push these migrations to the remote database?
 • 20260901193000_fix_potential_rehearsal_title.sql
 [Y/n] y
Applying migration 20260901193000_fix_potential_rehearsal_title.sql...
{"upToDate":false,"dryRun":false,"migrations":["20260901193000_fix_potential_rehearsal_title.sql"],"seeds":[],"roles":[],"message":"Finished supabase db push."}
```

Result: success, migration applied to linked remote database.

### Scoped verification query output (post-apply)

```text
{
  "rows": [
    {
      "has_potential_one_off_body": true,
      "has_potential_recurring_body": true,
      "has_potential_title": true,
      "introduces_forbidden_type": false,
      "keeps_rehearsal_created_type": true
    }
  ]
}
```

Expected outcome check:

- `has_potential_title = true`
- `has_potential_one_off_body = true`
- `has_potential_recurring_body = true`
- `keeps_rehearsal_created_type = true`
- `introduces_forbidden_type = false`
