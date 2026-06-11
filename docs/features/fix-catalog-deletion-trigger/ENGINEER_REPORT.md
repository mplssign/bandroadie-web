# Engineer Report

## Feature Slug

fix-catalog-deletion-trigger

## Feature Title

Fix `prevent_catalog_deletion_trigger` to allow cascade deletes

## Goal

The `prevent_catalog_deletion()` trigger function was blocking all deletes of
Catalog setlist rows, including legitimate cascade paths (band deletion, account
teardown). This migration replaces the function body with a `pg_trigger_depth()`
guard so only direct user-initiated deletes are blocked.

## Architect Tasks Completed

- [x] Task 1 — Added new SQL migration file in `supabase/migrations/` with timestamp `20260611000000`
- [x] Task 2 — Implemented `CREATE OR REPLACE FUNCTION public.prevent_catalog_deletion()` with `pg_trigger_depth() = 0` guard on the exception path
- [x] Task 3 — Preserved existing exception message text (`Cannot delete Catalog setlist`)
- [x] Task 4 — Function uses `LANGUAGE plpgsql` and includes `SET search_path = public`
- [x] Task 5 — Did not recreate or rename `prevent_catalog_deletion_trigger`; relies on function replacement only
- [x] Task 6 — Added concise migration comments describing direct vs cascade behavior

## Files Created

- supabase/migrations/20260611000000_fix_prevent_catalog_deletion_trigger_cascade.sql

## Files Modified

- none

## Analyzer Results

Command: `flutter analyze`
Result: Not run — no Flutter/Dart files were changed. Migration is pure SQL.

## Test Results

Not run — no Flutter test coverage applies to this SQL-only change. Post-deploy
verification SQL is provided in the Architect plan (Section 15).

## Verification

Manual steps performed:

- Confirmed trigger `prevent_catalog_deletion_trigger` is not redefined in any
  existing local migration (grep returned no results); function replacement only
  is safe.
- Confirmed `delete_band` RPC (20260607000000_fix_delete_band_cascade.sql) issues
  `DELETE FROM public.setlists WHERE band_id = band_uuid` directly — this is a
  nested context that `pg_trigger_depth() > 0` will allow through after the fix.
- Confirmed Catalog detection uses `COALESCE(OLD.is_catalog, false)` consistent
  with the pattern in `delete_setlist` RPC.
- Confirmed exception message `Cannot delete Catalog setlist` preserved verbatim.

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes
