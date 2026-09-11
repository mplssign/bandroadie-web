## Summary

Both demo teardown paths — the pg_cron sweep `cleanup_expired_demo_sessions()` and the client-invoked "Exit Demo" button — deleted the `demo_sessions` ledger row and cascaded the visitor's cloned bands, but never touched the visitor's anonymous `auth.users` row. Every demo entry left a permanent orphaned row in `auth.users`. Prod held ~59 already-orphaned rows accumulated over roughly two days of traffic.

## Fix

- **Cron path** (`cleanup_expired_demo_sessions()`): rewritten to capture expired session user ids, delete `demo_sessions` (cascading bands/setlists/gigs/band_members), then delete each user's `auth.users` row **individually**, each iteration guarded by its own `EXCEPTION WHEN foreign_key_violation` handler. A per-user loop was required rather than a single batched delete — QA-discovered defect: a batched delete lets one user's FK violation abort the whole statement, silently orphaning every other clean user in the same sweep. Fixed and re-verified.
- **Client path** ("Exit Demo" button): new Edge Function `exit-demo-session` orchestrates the existing `exit_demo_session()` RPC followed by `auth.admin.deleteUser()`, following the same convention as the existing `delete_user_account` RPC. `demo_session_service.dart` now calls the Edge Function instead of the RPC directly.
- One-time backfill (same migration) deletes the historically-orphaned rows, excluding the 13 permanent template-fixture accounts.

## Verification

- `flutter analyze` clean on the changed Dart file.
- Full SQL/diff review across 7 QA cycles.
- Three Tier 1 database tests executed against a real Postgres instance running the actual migration (not code-path analysis alone): normal cascade (6/6 assertions), FK-violation-handling path (8/8, including the collateral-damage regression this found and fixed), and backfill-filter safety excluding template accounts (2/2).
- No RLS changes, no new client-facing RPC surface, no changes to real-user auth flows.

## Residual / accepted limitation

QA's broader ephemeral-database tooling (Supabase branching / MCP access from an automated QA session) remains unreliable in this environment — a pre-existing, repo-wide gap unrelated to this fix (the full base schema predates migration tracking). The Tier 1 database verification for this feature was completed via manual execution against a real Postgres instance instead. This gap is tracked separately and does not block this fix.

## Not included in this PR (deploy is manual, outside this pipeline)

- Applying the migration to prod.
- Deploying the `exit-demo-session` Edge Function.
- Shipping the client build carrying the updated `demo_session_service.dart`.
