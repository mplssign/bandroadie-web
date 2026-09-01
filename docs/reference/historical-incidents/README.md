# Historical Incident SQL Scripts

Frozen forensic artifacts from prior incidents and one-off backfills. **Not
runnable as migrations.** Kept for historical reference only.

The authoritative schema lives in `supabase/migrations/`. Any change to
production schema must go through a proper migration — never through these
scripts.

## Layout

- `diagnostics/` — read-only investigation queries.
- `fixes/` — one-off remediation scripts already applied by hand.
- `notifications/` — obsolete notification-system experiments (superseded by
  current `send-push` architecture).
- `schema/` — pre-migration schema exploration.
- `triggers/` — trigger investigation.

Relocated from `sql/` in `bug/dead-code-and-doc-cleanup` (2026-08-30).
