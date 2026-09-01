# QA Report

## Feature Slug

bug/notification-trigger-gaps

## Feature Title

Notification Trigger Gaps

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

Branch and live database verification were completed for the server-side fix, and the static trigger/function checks against the live Supabase project passed. The remaining blocker is the required app-level functional validation: the four authenticated live-app notification tests in the plan were not executed in this environment, so runtime behavior cannot be claimed as validated.

## Branch State

```bash
git branch --show-current
```

Output:

```text
bug/notification-trigger-gaps
```

## Architect Scope Review

- Scope adherence: compliant
- Files modified: as expected — report only; no migration or trigger function modifications were made by this QA session
- Files off-limits: not touched — no `lib/**` changes, no migration edits, no trigger edits

## Completeness Check

- All Architect tasks implemented: no runtime validation completed in this session; static verification is complete, but the app-level live functional tests remain unexecuted
- Missing tasks:
  1. Real authenticated live app creation of one confirmed gig, one potential gig, one rehearsal, and one block-out date
  2. Screenshots or explicit confirmation text for each of the 4 live functional checks
  3. Post-deploy production query evidence tied to newly created live notifications in the last hour

## Behavior Verification

- Validation method: live read-only SQL inspection against the linked production project (`nekwjxvgbveheooyorjo`) + blocked runtime app validation
- Result: static root-cause checks match the expected fix, but the required real user flow tests were not executed.

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: Gigs, Rehearsals, Notifications, Band members / RBAC, Auth / Session context, Trigger bindings
- Regressions found: none in static database verification; runtime regression checks remain unexecuted because the authenticated app workflow was not available in this environment

## Database Safety

Verified for the static trigger/function state against the live project:

- `notify_gig_created()` includes a first-name lookup and `Gig Scheduled` fixed title for non-potential gigs
- `notify_rehearsal_created()` includes year-inclusive formatting and correct first-name lookup
- `notify_blockout_created()` uses `NEW.date` and the `blockout_created_notification` trigger exists on `public.block_dates`
- No migration or trigger file was changed by QA in this session

## Static Re-verification (Tier 2 checks)

SQL used:

```sql
SELECT proname,
       (pg_get_functiondef(p.oid) ILIKE '%first_name%') AS has_first_name_lookup,
       (pg_get_functiondef(p.oid) ILIKE '%Gig Scheduled%') AS has_fixed_gig_title,
       (pg_get_functiondef(p.oid) ILIKE '%MON FMDD, YYYY%') AS has_year_in_rehearsal_fmt,
       (pg_get_functiondef(p.oid) ILIKE '%NEW.date%') AS blockout_uses_date_column
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND proname IN ('notify_gig_created','notify_rehearsal_created','notify_blockout_created')
ORDER BY proname;

SELECT event_object_table, trigger_name, action_timing, event_manipulation, action_statement
FROM information_schema.triggers
WHERE trigger_schema='public' AND event_object_table='block_dates' AND trigger_name='blockout_created_notification';
```

Output:

```json
[
  {
    "proname": "notify_blockout_created",
    "has_first_name_lookup": true,
    "has_fixed_gig_title": false,
    "has_year_in_rehearsal_fmt": true,
    "blockout_uses_date_column": true
  },
  {
    "proname": "notify_gig_created",
    "has_first_name_lookup": true,
    "has_fixed_gig_title": true,
    "has_year_in_rehearsal_fmt": true,
    "blockout_uses_date_column": true
  },
  {
    "proname": "notify_rehearsal_created",
    "has_first_name_lookup": true,
    "has_fixed_gig_title": false,
    "has_year_in_rehearsal_fmt": true,
    "blockout_uses_date_column": true
  }
]
```

Trigger output:

```json
[
  {
    "event_object_table": "block_dates",
    "trigger_name": "blockout_created_notification",
    "action_timing": "AFTER",
    "event_manipulation": "INSERT",
    "action_statement": "EXECUTE FUNCTION notify_blockout_created()"
  }
]
```

Pass/Fail:

- Static re-verification: PASS

## Live Functional Tests (must be run via real app, authenticated as a band member)

The required app-level tests were not executed in this environment. No authenticated live app session, browser automation, or real band-member event creation was available here, so these are recorded as blocked rather than passed.

### Test 1 — Confirmed (non-potential) gig creates notification titled `Gig Scheduled`

- Requirement: as authenticated band member, create one non-potential gig; another member receives notification with title exactly `Gig Scheduled`, body names creator first name, and the correct date.
- Status: NOT EXECUTED / BLOCKED
- Explicit confirmation text: not generated because no live app session was available in this environment.

### Test 2 — Potential gig remains unchanged (title remains gig name / `New Gig`)

- Requirement: create a potential gig (`is_potential = true`) and confirm it is not given `Gig Scheduled` title.
- Status: NOT EXECUTED / BLOCKED
- Explicit confirmation text: not generated because no live app session was available in this environment.

### Test 3 — Rehearsal body includes creator first name and year-inclusive date

- Requirement: create a rehearsal and confirm body includes first name and year in the date, e.g. `... scheduled a rehearsal for SEP 12, 2026`.
- Status: NOT EXECUTED / BLOCKED
- Explicit confirmation text: not generated because no live app session was available in this environment.

### Test 4 — Block-out date creates `Member Unavailable` notification

- Requirement: create a block-out date and confirm a notification now fires with title `Member Unavailable`, creator first name, and correct date.
- Status: NOT EXECUTED / BLOCKED
- Explicit confirmation text: not generated because no live app session was available in this environment.

## Post-deploy Production Sample Query

SQL used:

```sql
SELECT type, COUNT(*) AS total,
       COUNT(*) FILTER (WHERE type='gig_created' AND title='Gig Scheduled') AS gig_title_ok,
       COUNT(*) FILTER (WHERE type='rehearsal_created' AND body ~ ', [0-9]{4}$') AS rehearsal_year_ok,
       COUNT(*) FILTER (WHERE type='blockout_created' AND body ILIKE '%unavailable on%') AS blockout_copy_ok
FROM notifications
WHERE created_at > NOW() - INTERVAL '1 hour'
  AND type IN ('gig_created','rehearsal_created','blockout_created')
GROUP BY type ORDER BY type;
```

Output:

```json
[]
```

Interpretation:

- No notifications were present in the last hour at the time of this read-only verification.
- This does not prove the fix is broken; it simply means no fresh records were present during the passive observation window.
- It cannot substitute for the required live authenticated functional checks.

## Test Plan Result Summary

| Test plan item                          | Result                                                            | Notes                                                                       |
| --------------------------------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 1. Static re-verification               | PASS                                                              | Function and trigger definitions match the expected fix on the live project |
| 2. Live functional check: confirmed gig | NOT EXECUTED / BLOCKED                                            | No authenticated app session available                                      |
| 3. Live functional check: potential gig | NOT EXECUTED / BLOCKED                                            | No authenticated app session available                                      |
| 4. Live functional check: rehearsal     | NOT EXECUTED / BLOCKED                                            | No authenticated app session available                                      |
| 5. Live functional check: block-out     | NOT EXECUTED / BLOCKED                                            | No authenticated app session available                                      |
| 6. Post-deploy production sample query  | PASS as a read-only query (0 rows returned, no data in last hour) | No live-event evidence available in this session                            |
| 7. Notification badge/list still loads  | NOT EXECUTED / BLOCKED                                            | No app validation performed                                                 |

## Analyzer Results

Not run for this QA session because the change under review is database-side only and no Dart files were modified. The report is validation-only.

## Test Results

- Static SQL checks: passed
- Runtime app checks: not executed in this environment
- Badge/list UI verification: not executed in this environment

## Diff Safety Review

- Secrets: none found in this QA activity
- Debug artifacts: none found
- Unrelated changes: none created by this QA session; we did not modify any file other than creating this report file

## Code Efficiency Review

- Dead code / unused imports, vars, params: none found
- Redundant restating comments: none found
- Unnecessary abstraction for single call sites: none found
- Unneeded defensive checks: none found
- Duplicated logic that should reuse existing code: none found
- Overall assessment: lean / acceptable

## Issues Found

### Critical (must fix before commit)

1. Live app functional validation was not completed in this session — the required authenticated notification flows could not be executed here, so runtime correctness remains unverified.

### Warnings (should fix)

1. The final functional check required by the plan is still pending: this fix is static-sql verified but not end-to-end app validated in a real authenticated band workflow.

### Suggestions (optional)

1. Run the four authenticated live-app notification tests in a real local or device session, then re-run the 1-hour production query after those actions to produce the required confirmation evidence.

## Final QA Conclusion

The live database state for the fix appears correct: the static trigger and function checks are passing against the linked project, and the trigger binding for `block_dates` is present. However, the required end-to-end runtime validation for the actual app notification flows was not performed in this environment, so the feature cannot be approved as fully validated. The correct verdict for this session is: **REQUIRES CHANGES**.
