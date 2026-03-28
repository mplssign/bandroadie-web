# Engineer Report

## Feature Slug
`bug/accept-invite-partial-failure-stale-invite`

## Feature Title
Accept Invite — Partial Failure Stale Invite Fix

## Goal
Replace the two non-atomic sequential database operations in the `accept-invite` edge function with a single PostgreSQL RPC call (`accept_band_invite`) that atomically upserts the band membership and marks the invitation as accepted within a single transaction boundary. This eliminates the possibility of a partial-failure state where a user becomes a band member but their invitation remains pending/sent.

## Pre-Implementation Verification
- **`band_members.status` column type confirmed:** TEXT
- **Verification method:** Reviewed all migration files. No `band_member_status_type` ENUM exists in any migration (only `band_role_type` and `special_item_type` ENUMs). The `20260302000000_band_user_roles.sql` migration converted `role` to `band_role_type` ENUM but left `status` untouched. All SQL references use bare string comparisons (`'active'`, `'invited'`, etc.) without type casts.

## Architect Tasks Completed
- [x] Task 1 — Verify `band_members.status` column type (confirmed TEXT)
- [x] Task 2 — Create migration with `accept_band_invite` RPC
- [x] Task 3 — Update edge function to call RPC
- [x] Task 4 — Verify: ON CONFLICT DO NOTHING matches current semantics (identical — `ON CONFLICT (band_id, user_id) DO NOTHING`)
- [x] Task 5 — Verify: Edge function response shape unchanged (`{ success, accepted_count, band_names }` preserved exactly)
- [ ] Task 6 — Test: Happy path invite acceptance (deferred to QA — requires deployment)
- [ ] Task 7 — Test: Idempotent re-acceptance (deferred to QA — requires deployment)
- [ ] Task 8 — Test: Already-a-member scenario (deferred to QA — requires deployment)

## Files Created
- `supabase/migrations/20260328000000_accept_band_invite_rpc.sql`

## Files Modified
- `supabase/functions/accept-invite/index.ts`

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings. No issues found.

## Test Results
Not run — no Flutter source changes; Architect plan does not require `flutter test`.

## Verification

### Migration File Verification
- `REVOKE ALL ON FUNCTION public.accept_band_invite(UUID, UUID) FROM PUBLIC` is included before the GRANT — confirmed present
- `IF NOT FOUND` is used for the row existence check (not `IF v_band_id IS NULL`) — confirmed correct
- Role cast uses `'member'::band_role_type` ENUM cast — confirmed present
- `FOR UPDATE` row locking on SELECT — confirmed present
- `SECURITY DEFINER` with `SET search_path = public` — confirmed present
- `GRANT EXECUTE` scoped to `service_role` only — confirmed present

### Edge Function Verification
- Two sequential DB operations replaced with single `supabaseAdmin.rpc("accept_band_invite", ...)` call
- Only two RPC parameters: `p_invite_id` and `p_user_id`
- `for` loop structure preserved
- `try/catch` per invite preserved
- Response shape `{ success, accepted_count, band_names }` unchanged
- Band name extraction from pre-fetched `invite.bands.name` unchanged
- Formatted with Prettier

### Manual Testing
- Deferred to QA — requires `supabase db push` (migration) and `supabase functions deploy accept-invite` (edge function deployment), which are user actions per the operating model.

## Deviations From Architect Plan
None

## Blockers Encountered
None

## Ready For QA
Yes
