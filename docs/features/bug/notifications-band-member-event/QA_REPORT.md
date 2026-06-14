# QA Report

## Feature Slug

bug/notifications-band-member-event

## Feature Title

Notifications for Band Member Event Creation

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

I validated the required agent docs, reviewed the Architect and Engineer reports, inspected the migration SQL directly, and ran branch/worktree/diff checks plus flutter analyze. The new helper function and backfill SQL match the intended fix at code level. However, scope compliance and verification completeness do not fully meet the Architect plan and QA gate requirements.

## Architect Scope Review

- Scope adherence: violated
- Files modified: deviations noted below
- Files off-limits: not touched

Observed modified files relevant to this feature:

- docs/features/bug/notifications-band-member-event/ARCHITECT_PLAN.md (modified)
- docs/features/bug/notifications-band-member-event/ENGINEER_REPORT.md (new)
- supabase/migrations/20260614000000_fix_notification_default_on_missing_preferences.sql (new)

Architect-approved implementation scope in Section 9/10 was limited to creating/modifying the new migration file. Additional docs are outside that explicit implementation list.

## Completeness Check

- All Architect tasks implemented: no
- Missing tasks:

1. No evidence in repo artifacts that Engineer Task 1 (dashboard confirmation of webhook/cron overlap) was completed.
2. No evidence in repo artifacts that Engineer Task 2 (Tier 1 pre-deploy SQL diagnostics) was completed.
3. No evidence in repo artifacts that Engineer Task 5 (apply in test/staging) was completed; deployment was direct to linked production via query.
4. No evidence in repo artifacts that Engineer Task 7 (real iOS end-to-end push verification with account lacking preferences) was completed.

## Behavior Verification

- Validation method: code-path analysis plus reported live SQL verification excerpts
- Result: partially matches expected

Requested check results:

1. should_receive_notification() default-on behavior and category logic:
   - PASS. Missing row now returns true.
   - PASS. Global notifications_enabled=false still returns false.
   - PASS. Category mapping preserved:
     - gig_created/gig_confirmed -> gigs_enabled
     - potential_gig_created -> potential_gigs_enabled
     - rehearsal_created -> rehearsals_enabled
     - blockout_created -> blockouts_enabled
     - other types -> true (unchanged fallback)
2. Backfill implementation:
   - PASS. INSERT targets only user_id and therefore relies on table defaults.
   - PASS. Uses ON CONFLICT (user_id) DO NOTHING.

## Regression Check

- Risk level: MEDIUM
- Systems reviewed: Gigs, Rehearsals, Notifications, Members/RBAC (query scope), Platform delivery assumptions
- Regressions found: no direct code-level regressions in touched SQL; verification gaps remain

QA regression-area gaps not covered by fix/backfill evidence:

1. No direct evidence of owner-created event notification parity test.
2. No direct evidence of recipient category-disabled behavior test after deploy.
3. No direct evidence of notifications_enabled=false recipient suppression test after deploy.
4. No direct evidence of actor-never-notified regression check post-deploy.
5. No direct evidence of iOS push banner end-to-end test in this change set.
6. No direct evidence of Android push parity test.

## Database Safety

Issues found:

1. Two remote-only migrations are present in linked DB but absent locally: 20260607095329 and 20260611063525.
2. Because those SQL bodies are not available in the repo, they could alter notification_preferences defaults, should_receive_notification(), triggers, or related policy/function behavior.
3. Migration history remains drifted (local-only rows and remote-only rows), so reproducibility and rollback confidence are reduced.

## Analyzer Results

Command: flutter analyze
Result: 0 errors

## Test Results

Not run (no flutter test execution in this QA pass)

## Diff Safety Review

- Secrets: none found
- Debug artifacts: none found
- Unrelated changes: found (ARCHITECT_PLAN.md formatting/content edits during implementation cycle)

## Issues Found

### Critical (must fix before commit)

1. Resolve migration-history drift documentation for this feature by capturing the SQL content/intended effect of remote-only migrations 20260607095329 and 20260611063525 in repo-visible form (or equivalent audited reference), then confirm they do not conflict with this fix.
2. Complete Architect-required verification evidence for production-path checks (webhook/cron state) and post-fix behavioral checks that remain unproven in current artifacts.

### Warnings (should fix)

1. Keep implementation scope to Architect-approved files; avoid additional plan-document edits in the same implementation branch unless explicitly requested.

### Suggestions (optional)

1. Add a short SQL verification transcript file under docs/features/bug/notifications-band-member-event with exact queries and timestamped outputs for Tier 1/Tier 2 parity.
