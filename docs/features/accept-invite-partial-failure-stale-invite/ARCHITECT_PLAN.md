# ARCHITECT_PLAN.md

## Feature Slug

`bug/accept-invite-partial-failure-stale-invite`

---

## 1. Problem Summary

The `accept-invite` Supabase edge function performs two sequential, non-atomic database operations per invitation:

1. Upsert the user into `band_members` with `status='active'`
2. Update the `band_invitations` record to `status='accepted'`

These operations run inside a `for` loop with a single `try/catch` per iteration and no wrapping transaction. If the upsert (operation 1) succeeds but the update (operation 2) fails due to a transient error, the database enters an inconsistent state: the user is an active band member, but their invitation record remains `status='pending'` or `'sent'`.

The Edit Band screen's `_loadPendingInvites()` queries `band_invitations` filtered by `status IN ('pending', 'sent')` without cross-checking `band_members`, so the stale invite appears in the "Invited" section for a user who is already an active member.

A previous client-side filter (removed in `feature/edit-band-member-display-cleanup`) masked this inconsistency by excluding emails that matched existing band members. That filter is gone, making this bug directly visible.

---

## 2. Existing System Analysis

### Edge Function: `accept-invite/index.ts`

- Authenticates the caller via JWT
- Creates an admin client using `SUPABASE_SERVICE_ROLE_KEY`
- Queries `band_invitations` for all `pending`/`sent` invites matching the user's email
- Iterates over invites, performing two independent writes per invite:
  - `band_members.upsert()` with `ignoreDuplicates: true` (ON CONFLICT DO NOTHING)
  - `band_invitations.update()` setting `status='accepted'` and `accepted_at`
- Catches errors per-invite and continues to the next
- Returns `{ success, accepted_count, band_names }`

### Client-Side Callers

Two entry points call this edge function:

1. **AuthGate** (`lib/features/auth/auth_gate.dart` ~line 293): Auto-accepts pending invites on login. Calls `supabase.functions.invoke('accept-invite', body: {})`.
2. **InviteScreen** (`lib/features/auth/invite_screen.dart` ~line 121): Direct invite acceptance via token. Calls `supabase.functions.invoke('accept-invite', body: {'token': token})`.

Both receive and handle the same response shape. Neither is affected by the backend fix.

### Edit Band Screen: `_loadPendingInvites()`

- Location: `lib/features/bands/band_form_screen.dart` lines 1058–1100
- Query: `band_invitations.select('id, email, status, created_at').eq('band_id', bandId).inFilter('status', ['pending', 'sent'])`
- Deduplicates by email, keeping the newest invite
- No cross-check against `band_members` — any invite with `status='pending'` or `'sent'` is displayed

### Data Flow

```
User clicks invite link
  → InviteScreen / AuthGate calls accept-invite edge function
    → Edge function: upsert into band_members ← CAN SUCCEED
    → Edge function: update band_invitations  ← CAN FAIL independently
  → Response returned to client
  → Edit Band screen loads → _loadPendingInvites() → stale invite visible
```

---

## 3. Root Cause

**Two non-atomic writes in the edge function with no transactional guarantee.**

The Supabase JS client executes each database operation as an independent HTTP request to the PostgREST API. There is no client-side transaction API. If the first write commits and the second fails, there is no rollback mechanism.

**Root Cause Confidence: HIGH** — directly observed in `supabase/functions/accept-invite/index.ts` lines 90–104.

---

## 4. Proposed Solution

### Approach: New PostgreSQL RPC Function

Create an `accept_band_invite` PostgreSQL function that atomically performs both writes inside a single function body (implicit transaction). Update the edge function to call this RPC instead of two sequential statements.

This aligns with the established codebase pattern. The project already uses 6+ SECURITY DEFINER RPC functions for multi-table atomic operations:
- `remove_band_member` — deletes from `band_members`
- `delete_band` — cascading multi-table delete
- `update_member_role` — updates `band_members` + manages `contributor_permissions`
- `delete_setlist` — updates `gigs`, `rehearsals`, deletes `setlist_songs`, `setlists`
- `create_band` — creates `bands`, upserts `users`, inserts `band_members`

### Why Not an Edge Function Transaction

The Supabase JS client does not expose raw SQL transactions (`BEGIN`/`COMMIT`). Each `.from().upsert()` and `.from().update()` call is an independent HTTP request to PostgREST. There is no way to wrap multiple PostgREST calls in a database transaction from the edge function.

### Edge Function Change

- Replace the two sequential statements per invite with a single `supabaseAdmin.rpc('accept_band_invite', { ... })` call
- Keep the existing `for` loop and `try/catch` per invite (each invite is independent)
- Preserve the existing response shape and error handling
- The edge function already has `invite.bands.name` from the pre-fetch query — the RPC does not need to return the band name

---

## 5. RPC Contract

### 5.1 Signature

```sql
accept_band_invite(p_invite_id UUID, p_user_id UUID) RETURNS VOID
```

**Two parameters only.** Justification for each decision:

| Parameter | Decision | Reason |
|-----------|----------|--------|
| `p_invite_id` | **Required parameter** | Primary key to locate the invitation row. Cannot be derived. |
| `p_user_id` | **Required parameter** | The edge function runs with `service_role` (no `auth.uid()` context). The user ID comes from the JWT-decoded `authUser.id`. Cannot be derived from the invite row because `band_invitations` stores `email`, not `user_id`. |
| `p_band_id` | **NOT a parameter — derived internally** | `band_invitations.band_id` is on the invite row. The RPC reads it from the row it already fetches. Passing it from the caller would create a trust gap — the caller could pass a `band_id` that disagrees with the invite row. Database truth is authoritative. |
| `p_role` | **NOT a parameter — hardcoded to `'member'`** | Accepting an invite always grants the `member` role. The current edge function hardcodes `'member'`. There is no use case where invite acceptance produces a different role. The `ON CONFLICT DO NOTHING` means existing members keep their current role regardless. Hardcoding eliminates a caller-controlled injection vector. |

### 5.2 Acceptance Invariants

The RPC enforces these invariants in order:

| # | Invariant | Enforcement |
|---|-----------|-------------|
| 1 | **Invite exists** | `SELECT ... WHERE id = p_invite_id FOR UPDATE`. If no row, `RAISE EXCEPTION 'Invitation not found'`. |
| 2 | **Invite is eligible for acceptance** | Status must be `'pending'` or `'sent'`. If status is `'expired'`, `'declined'`, or any other non-eligible value, `RAISE EXCEPTION 'Invitation is not eligible for acceptance'`. |
| 3 | **Already-accepted invite is handled** | If status is `'accepted'`, the RPC returns silently (idempotent no-op). No error, no re-write. |
| 4 | **Existing active membership is handled** | `INSERT ... ON CONFLICT (band_id, user_id) DO NOTHING`. If the user is already a member in any role, their existing role and status are preserved. The invite is still marked accepted. |
| 5 | **Row-level locking prevents races** | `SELECT ... FOR UPDATE` locks the invite row. Concurrent calls on the same invite are serialized: the first processes fully, the second hits the `'accepted'` status and returns idempotently. |

### 5.3 Idempotency and Failure Behavior

| Scenario | Behavior | Result |
|----------|----------|--------|
| **Happy path** (invite pending/sent, user not a member) | Inserts member row, updates invite to accepted | Success |
| **Happy path** (invite pending/sent, user already a member) | Member insert is DO NOTHING no-op, invite updated to accepted | Success |
| **Invite already accepted** (repeated call) | Detected by status check, returns immediately | **Idempotent success** (no error, no re-write) |
| **Invite not found** (invalid UUID) | No row returned from SELECT | **Hard failure** — `RAISE EXCEPTION 'Invitation not found'` |
| **Invite expired / declined / revoked** | Status not in `('pending', 'sent', 'accepted')` | **Hard failure** — `RAISE EXCEPTION 'Invitation is not eligible for acceptance'` |
| **Multiple invites for same band** | Each invite is an independent RPC call. First inserts member, second is DO NOTHING for member + updates its own invite row. | Success for both |
| **Concurrent duplicate calls** | `FOR UPDATE` serializes. First call accepts, second call finds status `'accepted'` and returns idempotently. | Both succeed, no duplicate writes |

### 5.4 Atomicity Boundary

**Hard rule:** The membership write (`INSERT INTO band_members`) and the invitation status update (`UPDATE band_invitations`) execute within a single PostgreSQL function body. PostgreSQL wraps the function body in an implicit transaction. Both writes commit together or both roll back together. Partial success is structurally impossible.

No client-side masking, no Flutter workaround, and no defensive filtering on the read path is permitted as a substitute for this atomicity guarantee.

---

## 6. Database Impact

| Area | Impact |
|------|--------|
| New RPC function | `accept_band_invite(UUID, UUID)` — new SECURITY DEFINER function |
| `band_members` table | Write moves into RPC. Upsert semantics preserved exactly: `ON CONFLICT (band_id, user_id) DO NOTHING`. |
| `band_invitations` table | Write moves into RPC. Same update semantics: `status='accepted'`, `accepted_at=NOW()`. |
| `band_members.role` column type | `band_role_type` ENUM (`'admin'`, `'member'`, `'contributor'`). RPC must cast: `'member'::band_role_type`. |
| `band_members.status` column type | Confirmed as TEXT (not ENUM) from current edge function usage. RPC uses bare string `'active'`. Engineer must verify against actual column definition before writing migration. |
| New migration | Required: `supabase/migrations/20260328000000_accept_band_invite_rpc.sql` |
| Existing migrations | Unaffected |
| Triggers | Unaffected |

---

## 7. RLS / RPC Changes

### New RPC Function — Full Definition

```sql
-- accept_band_invite_rpc.sql
-- Atomically accepts a band invitation: upserts the user into band_members
-- and marks the invitation as accepted, within a single transaction boundary.
-- Called exclusively by the accept-invite edge function via service_role.

CREATE OR REPLACE FUNCTION public.accept_band_invite(
  p_invite_id UUID,
  p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_band_id UUID;
  v_status TEXT;
BEGIN
  -- Lock the invite row and fetch band_id + status.
  -- FOR UPDATE prevents concurrent accept attempts from racing.
  SELECT band_id, status
    INTO v_band_id, v_status
    FROM band_invitations
   WHERE id = p_invite_id
     FOR UPDATE;

  -- Invite not found
  -- Use IF NOT FOUND (idiomatic PL/pgSQL) rather than checking v_band_id IS NULL.
  -- IF NOT FOUND is correct regardless of whether band_id is nullable.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitation not found';
  END IF;

  -- Already accepted — idempotent success, no re-write
  IF v_status = 'accepted' THEN
    RETURN;
  END IF;

  -- Only pending or sent invites may be accepted
  IF v_status NOT IN ('pending', 'sent') THEN
    RAISE EXCEPTION 'Invitation is not eligible for acceptance (status: %)', v_status;
  END IF;

  -- Upsert band membership.
  -- ON CONFLICT DO NOTHING preserves existing role (admin/contributor)
  -- for users who are already band members.
  INSERT INTO band_members (band_id, user_id, role, status)
  VALUES (v_band_id, p_user_id, 'member'::band_role_type, 'active')
  ON CONFLICT (band_id, user_id) DO NOTHING;

  -- Mark invitation as accepted
  UPDATE band_invitations
     SET status = 'accepted',
         accepted_at = NOW()
   WHERE id = p_invite_id;
END;
$$;

-- Revoke default PUBLIC execute grant before adding targeted grant.
-- PostgreSQL grants EXECUTE to PUBLIC by default on CREATE FUNCTION.
-- Without this REVOKE, any role (anon, authenticated) can call this function
-- directly with arbitrary p_user_id values — bypassing all access controls.
REVOKE ALL ON FUNCTION public.accept_band_invite(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.accept_band_invite(UUID, UUID) TO service_role;
```

### RLS Impact

- No RLS policy changes required
- The function uses `SECURITY DEFINER` which runs with the function owner's privileges
- The edge function already uses `service_role` client, which bypasses RLS
- `REVOKE ALL FROM PUBLIC` is required before the targeted GRANT — PostgreSQL grants EXECUTE to PUBLIC by default on `CREATE FUNCTION`. Without the REVOKE, any authenticated or anonymous role can call this function directly.
- `GRANT` is scoped to `service_role` only — this function must not be callable directly by authenticated clients, because it takes `p_user_id` as a parameter rather than using `auth.uid()`. Granting to `authenticated` would allow any user to accept any invite for any user.
- No self-referencing policy risk — neither `band_members` nor `band_invitations` RLS policies are being modified

---

## 8. Flutter Architecture Changes

**None.**

The fix is entirely backend. No Flutter source code changes are required.

- `_loadPendingInvites()` continues to query `band_invitations` as before — once the backend guarantees atomicity, stale invites cannot exist
- `AuthGate` and `InviteScreen` call the same edge function with the same API — no changes needed
- No new providers, controllers, repositories, or widgets

---

## 9. Exact Files to Create

| File | Justification |
|------|---------------|
| `supabase/migrations/20260328000000_accept_band_invite_rpc.sql` | New PostgreSQL RPC function for atomic invite acceptance |

---

## 10. Exact Files to Modify

| File | What Changes |
|------|-------------|
| `supabase/functions/accept-invite/index.ts` | Replace two sequential DB operations per invite with a single `supabaseAdmin.rpc('accept_band_invite', ...)` call. Preserve loop structure, error handling, response shape. |

---

## 11. Files Off-Limits

| File / Area | Reason |
|-------------|--------|
| `lib/**` (all Flutter source) | Fix is backend-only. No Flutter changes permitted. |
| `lib/features/auth/auth_gate.dart` | Client-side caller — unchanged API. |
| `lib/features/auth/invite_screen.dart` | Client-side caller — unchanged API. |
| `lib/features/bands/band_form_screen.dart` | `_loadPendingInvites()` is a read query — no masking allowed. |
| All other edge functions | Unrelated — not in scope. |
| All existing migrations | Must not be modified retroactively. |
| All existing RPC functions | No contract changes to other RPCs. |
| RLS policies on `band_members` or `band_invitations` | Not required, not permitted. |
| `lib/main.dart` | Initialization order must not change. |
| Config files, assets, tests, lockfiles | Not in scope. |

---

## 12. System Impact Map

| System | Impact |
|--------|--------|
| `accept-invite` edge function | **affected** — calls new RPC instead of two sequential statements |
| `band_members` table (write) | **affected** — write moves into RPC function |
| `band_invitations` table (write) | **affected** — write moves into RPC function |
| Edit Band screen / `_loadPendingInvites()` | **unaffected** — read-only, no changes |
| Auth / RLS policies | **unaffected** — no policy changes |
| Client-side invite acceptance (AuthGate, InviteScreen) | **unaffected** — same edge function API |
| Routing | **unaffected** |
| Members page | **unaffected** |
| Gigs | **unaffected** |
| Rehearsals | **unaffected** |
| Setlists / Catalog | **unaffected** |
| Notifications | **unaffected** |
| Platform (iOS / Android / Web / macOS) | **unaffected** |

---

## 13. Regression Risk

**MEDIUM**

Rationale:
- The invite acceptance path is a critical onboarding flow — new users joining bands
- However, the change is structural (moving two operations into a single RPC) with identical write semantics
- The edge function signature and response shape are unchanged — all client code is unaffected
- Two entry points exist (AuthGate auto-accept and InviteScreen direct accept) — both call the same edge function, so both inherit the fix
- The `ON CONFLICT DO NOTHING` upsert behavior and `status='accepted'` update are semantically identical to the current implementation
- The `FOR UPDATE` lock adds correctness for concurrent calls without changing happy-path behavior
- Established RPC pattern (6+ prior functions) reduces implementation risk

---

## 14. Risks / Edge Cases

| Risk | Mitigation |
|------|-----------|
| **Upsert semantics change** | RPC uses `ON CONFLICT (band_id, user_id) DO NOTHING` — identical to current `ignoreDuplicates: true`. Engineer must verify this exact match. |
| **Role column type mismatch** | `band_members.role` is `band_role_type` ENUM, not TEXT. RPC casts explicitly: `'member'::band_role_type`. Engineer must not use a bare string. |
| **Status column type unverified** | `band_members.status` is assumed TEXT based on current edge function usage. If a `band_member_status_type` ENUM was introduced in a migration, the bare string `'active'` will fail at runtime. Engineer must verify column type in `information_schema.columns` before writing the migration. |
| **Missing REVOKE allows public access** | PostgreSQL grants EXECUTE to PUBLIC by default. Without `REVOKE ALL FROM PUBLIC`, any authenticated user can call this RPC directly with arbitrary parameters. Migration must include the REVOKE before the GRANT. |
| **Multiple invites for same band** | The `for` loop processes invites independently. First RPC inserts member, subsequent RPCs are DO NOTHING for member + update their own invite row. Correct behavior. |
| **Edge function error reporting** | If the RPC throws (invite not found, not eligible), the catch fires, the band is not counted. If the RPC succeeds (including idempotent already-accepted), the band name is added. Behavior preserved. |
| **`accepted_at` timestamp** | Moves from `new Date().toISOString()` (JS UTC) to `NOW()` (PostgreSQL server time). Both UTC. Server time is more accurate. Acceptable. |
| **GRANT scope** | Granted to `service_role` only, not `authenticated`. Prevents direct client calls and eliminates the risk of a user calling `accept_band_invite(any_invite_id, any_user_id)`. |
| **FOR UPDATE lock contention** | Lock is held only for the duration of the function body (microseconds). No meaningful contention risk for this workload. |

---

## 15. Engineer Task Breakdown

| # | Task | File | Notes |
|---|------|------|-------|
| 0 | **Create and checkout feature branch** | — | `git checkout main && git pull origin main && git checkout -b bug/accept-invite-partial-failure-stale-invite`. Must not implement on `bug/send-invite-no-active-member-guard`. |
| 1 | **Verify `band_members.status` column type** | — | Run `SELECT column_name, data_type, udt_name FROM information_schema.columns WHERE table_name = 'band_members' AND column_name = 'status';` in Supabase SQL editor. Confirm TEXT before writing migration. If ENUM, update Section 7 SQL accordingly. |
| 2 | Create migration with `accept_band_invite` RPC | `supabase/migrations/20260328000000_accept_band_invite_rpc.sql` | Must match Section 7 definition exactly. Includes `REVOKE ALL FROM PUBLIC` before GRANT. Role must cast to `band_role_type`. |
| 3 | Update edge function to call RPC | `supabase/functions/accept-invite/index.ts` | Replace lines ~90–104 with single `supabaseAdmin.rpc()` call. Only two params: `p_invite_id`, `p_user_id`. |
| 4 | Verify: ON CONFLICT DO NOTHING matches current semantics | — | Confirm existing member rows are not overwritten. |
| 5 | Verify: Edge function response shape unchanged | — | `{ success, accepted_count, band_names }` must remain identical. |
| 6 | Test: Happy path invite acceptance | — | See QA targets below. |
| 7 | Test: Idempotent re-acceptance | — | Call twice — second call must succeed silently. |
| 8 | Test: Already-a-member scenario | — | Member row preserved, invite still marked accepted. |

Task 0 is branch setup. Tasks 1 is a pre-implementation verification gate. Tasks 2–3 are implementation. Tasks 4–8 are verification.

---

## 16. Verification Plan

### Engineer Validation Commands

```bash
# Deploy the migration to remote database
supabase db push

# Deploy the updated edge function
supabase functions deploy accept-invite

# Verify RPC exists (Supabase SQL editor or psql)
SELECT routine_name, routine_schema
FROM information_schema.routines
WHERE routine_name = 'accept_band_invite';
```

### Manual Testing

1. **Happy path:** Send an invite → accept via app → verify user appears in Members, invite disappears from Invited section
2. **Already a member:** Manually insert user into `band_members` → create a pending invite for same band → accept → member record unchanged (DO NOTHING), invite marked `accepted`
3. **Already accepted (idempotency):** After step 1, manually call the RPC again with the same invite ID → must return without error and without re-writing
4. **Invalid invite:** Call the RPC with a non-existent UUID → must raise `'Invitation not found'`
5. **Expired invite:** Set an invite to `status='expired'`, then call RPC → must raise `'Invitation is not eligible for acceptance'`
6. **Multiple invites:** Create two pending invites for same user to different bands → accept → both should resolve

---

## 17. QA Regression Areas

QA must specifically validate:

| # | Check | Expected Result |
|---|-------|-----------------|
| 1 | **Happy path acceptance** | User accepts invite → appears in Members list, invite disappears from Invited section on Edit Band |
| 2 | **Member already exists** | User is already a band member with role `admin`. Accept a pending invite for same band. Member row unchanged (still admin), invite marked accepted. |
| 3 | **Invitation already accepted** | Accept an invite, then trigger acceptance again (e.g., via AuthGate auto-accept). No error, no duplicate member row, no state change. |
| 4 | **Invitation missing or invalid** | Call edge function with a user who has no pending invites. Response: `{ success: true, accepted_count: 0, band_names: [] }`. No errors. |
| 5 | **No stale invite after partial failure** | Manufacture the pre-fix inconsistent state (member exists, invite still pending). After applying fix, re-run accept flow. Invite must transition to accepted. Verify Edit Band screen no longer shows the stale invite. |
| 6 | **Edge function response shape** | Confirm response is exactly `{ success: boolean, accepted_count: number, band_names: string[] }`. No new fields, no removed fields. |
| 7 | **AuthGate auto-accept** | Log in as a user with pending invites. AuthGate should auto-accept them. Verify identical behavior to InviteScreen flow. |
| 8 | **No Flutter regressions** | Edit Band screen loads correctly. Members section displays correctly. Invited section displays only truly pending invites. |

---

## 18. Rollout / Migration Strategy

1. **Apply migration** to create `accept_band_invite` RPC function in the database
2. **Deploy updated edge function** that calls the RPC
3. **Order matters:** The migration MUST be applied before the edge function is deployed, because the new edge function depends on the RPC existing

The migration is additive (creates a new function) and non-destructive. It can be applied without downtime. If rollback is needed, the old edge function can be redeployed — it does not depend on the RPC.

---

## 19. Out of Scope

- Client-side filtering of stale invites (symptom masking — not needed once backend is atomic)
- Changes to `_loadPendingInvites()` query
- Changes to AuthGate or InviteScreen Dart code
- Changes to RLS policies on `band_members` or `band_invitations`
- Fixing the related bug `bug/send-invite-no-active-member-guard` (separate issue)
- Adding retry logic to the edge function
- Adding a database trigger to auto-clean stale invites
- Cleaning up pre-existing stale invites in production (separate maintenance task)

---

## 20. Widget Contracts (Public API)

**Not applicable.** No Flutter widgets or APIs are modified.

---

## 21. Data Flow Architecture

### Current (Broken)

```
Edge Function (per invite):
  ┌─ supabaseAdmin.from("band_members").upsert()     ← HTTP request 1 (commits independently)
  │
  └─ supabaseAdmin.from("band_invitations").update()  ← HTTP request 2 (can fail after 1 commits)
```

### Proposed (Fixed)

```
Edge Function (per invite):
  └─ supabaseAdmin.rpc("accept_band_invite", {       ← Single HTTP request
       p_invite_id: invite.id,
       p_user_id: authUser.id
     })
       │
       PostgreSQL function body (implicit transaction):
         ├─ SELECT band_id, status FROM band_invitations WHERE id = p_invite_id FOR UPDATE
         ├─ Validate: exists, eligible, not already accepted
         ├─ INSERT INTO band_members ... ON CONFLICT DO NOTHING
         └─ UPDATE band_invitations SET status='accepted', accepted_at=NOW()
         (all commit or all rollback — partial success is impossible)
```

---

## 22. Exact Code Locations

### Edge Function — Lines to Replace

**File:** `supabase/functions/accept-invite/index.ts`

**Current code (lines ~90–104):**
```typescript
// Add user to band_members (only if not already a member).
// ignoreDuplicates = ON CONFLICT DO NOTHING — preserves the existing
// role (admin/contributor) for users who are already band members.
await supabaseAdmin.from("band_members").upsert({
  band_id: invite.band_id,
  user_id: authUser.id,
  role: 'member',
  status: 'active',
}, { onConflict: "band_id,user_id", ignoreDuplicates: true });

// Mark invitation as accepted
await supabaseAdmin
  .from("band_invitations")
  .update({ status: "accepted", accepted_at: new Date().toISOString() })
  .eq("id", invite.id);
```

**Replace with:**
```typescript
// Atomically: upsert band_members + mark invitation accepted.
// Single RPC call wraps both writes in a PostgreSQL transaction.
// band_id is derived from the invite row inside the function.
// Role is hardcoded to 'member' inside the function.
await supabaseAdmin.rpc("accept_band_invite", {
  p_invite_id: invite.id,
  p_user_id: authUser.id,
});
```

### New Migration

**File:** `supabase/migrations/20260328000000_accept_band_invite_rpc.sql`

Full function definition provided in Section 7 (RLS / RPC Changes).

---

## Revision History

| Date | Change |
|------|--------|
| 2026-03-28 | Initial draft |
| 2026-03-28 | Revision 1 — Tightened RPC contract. See revision notes below. |
| 2026-03-28 | Revision 2 — Security and correctness fixes from principal engineer review. See revision notes below. |

### Revision 1 Notes

Changes from initial draft:

1. **RPC signature minimized from 4 parameters to 2.** Removed `p_band_id` (derived from invite row — database truth over caller-supplied values) and `p_role` (hardcoded to `'member'` — no use case for caller override, eliminates injection vector).
2. **Added Section 5: RPC Contract** with explicit subsections for signature justification, acceptance invariants, idempotency matrix, and atomicity boundary.
3. **Added `FOR UPDATE` row locking** to the RPC to serialize concurrent acceptance attempts on the same invite, preventing race conditions.
4. **Added idempotent handling for already-accepted invites** — repeated calls return silently instead of failing or re-writing.
5. **Added explicit status validation** — expired/declined/revoked invites cause a hard failure rather than silent acceptance.
6. **Added explicit `band_role_type` ENUM cast** — `'member'::band_role_type` instead of bare string, matching the column's ENUM type added in `20260302000000_band_user_roles.sql`.
7. **Added Section 11: Files Off-Limits** as a separate explicit table.
8. **Expanded QA Regression Areas** (Section 17) with 8 explicit numbered checks including idempotency, invalid invites, AuthGate flow, and response shape verification.
9. **GRANT justification tightened** — documented that granting to `authenticated` would be a security issue because `p_user_id` is a parameter, not `auth.uid()`.

### Revision 2 Notes

Changes from Revision 1:

1. **`IF NOT FOUND` replaces `IF v_band_id IS NULL`** — The original check was semantically incorrect. `IF NOT FOUND` is the idiomatic PL/pgSQL post-`SELECT INTO` guard and is correct regardless of column nullability. `IF v_band_id IS NULL` would silently pass for a row where `band_id` happened to be NULL (not possible with current FK constraint, but incorrect by principle).
2. **`REVOKE ALL FROM PUBLIC` added to migration** — PostgreSQL grants `EXECUTE` to `PUBLIC` by default on `CREATE FUNCTION`. The original plan stated the intent (service_role only) but did not enforce it in the SQL. Without the REVOKE, any authenticated or anonymous Supabase client can call this function directly. Added `REVOKE ALL ON FUNCTION public.accept_band_invite(UUID, UUID) FROM PUBLIC;` before the GRANT in Section 7. Added to Section 14 risks and Section 7 RLS Impact.
3. **`band_members.status` column type added as unverified risk** — The plan confirmed `role` as `band_role_type` ENUM but did not verify `status`. Added to Section 6 Database Impact, Section 14 Risks, and as Task 1 (pre-implementation verification gate) in Section 15.
4. **Branch creation added as Task 0 in Section 15** — The Architect ran on `bug/send-invite-no-active-member-guard`. The Engineer must explicitly branch off `main` before implementing. Made explicit as a numbered task to prevent silent branch contamination.
