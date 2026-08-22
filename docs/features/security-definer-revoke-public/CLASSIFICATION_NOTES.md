# C6 — SECURITY DEFINER Function Classification Pass

**Date:** 2026-08-21
**Method:** Live queries against the BandRoadie Supabase project (`nekwjxvgbveheooyorjo`) — `pg_proc`/`pg_policies` inspection, advisor lint extraction, and cross-reference against the actual Flutter (`lib/`) and edge function (`supabase/functions/`) call sites on disk. Read-only throughout; no migrations applied, no code changed.

This is the classification pass — it feeds the Feature Input, it is not the Feature Input.

---

## 1. The "120 functions" needs a correction first

The advisor report isn't a flat list of 120 distinct functions. It's two lint categories:

| Lint | Count | What it actually means |
|---|---|---|
| `anon_security_definer_function_executable` | 58 rows → **56 unique functions** (2 have overloads) | Functions where `anon` — i.e. **anyone, no login** — can call `/rest/v1/rpc/<name>` |
| `authenticated_security_definer_function_executable` | 62 rows → **60 unique functions** | Functions where `authenticated` can call the RPC |

**56 of the 60 "authenticated" names are the same functions already on the anon list.** The lint isn't flagging 62 *additional* functions — it's Supabase's advisor nudging "review every SECURITY DEFINER function callable by a logged-in user," which is true of nearly every RPC in the app by design. The only 4 names unique to the authenticated-only list are `delete_band`, `delete_user_account`, `remove_band_member`, `update_member_role` — destructive actions that are *already* correctly scoped (authenticated-only, no anon). They don't need fixing; they're just the advisor confirming the boundary is where it should be.

**Real scope: 56 unique functions on the anon-executable list.** That's the actual fix surface, not 120.

---

## 2. Correction to both of your "must stay anon" examples

I checked both against the real code before assuming either was a legitimate exception. **Neither is.**

**`accept-invite`** — the edge function requires an `Authorization` header and calls `auth.getUser()` before doing anything (401 if missing/invalid). The actual DB write goes through `supabaseAdmin.rpc('accept_band_invite', ...)` — `supabaseAdmin` is built with `SUPABASE_SERVICE_ROLE_KEY`, not the anon key. `accept_band_invite` is called from exactly one place in the whole codebase, and it's this service-role call. Its anon EXECUTE grant does nothing for the invite flow — revoking it changes no behavior.

**`calendar-feed`** — the edge function that actually serves the `.ics` file also runs entirely on `SUPABASE_SERVICE_ROLE_KEY` and does **raw table selects** (`band_calendar_subscriptions`, `bands`, `gigs`, `rehearsals`, `block_dates`, `users`) — it never calls an RPC at all, so no SECURITY DEFINER function backs the public feed URL. The functions that *are* RPCs here (`get_band_calendar_token`, `get_my_calendar_token`, `regenerate_band_calendar_token`, `regenerate_calendar_token`, `update_band_calendar_preferences`) are called from `calendar_subscription_service.dart` only when generating/managing *your own* subscription link inside the logged-in app — i.e. you must already be authenticated to get or regenerate a calendar URL. None of them need anon.

I'm flagging this because it means the migration is *less* dangerous than either of us assumed going in — but see §4, because a different risk showed up in its place.

---

## 3. Classification of all 56

### 3a. Trigger-bound functions (16) — zero risk, pure cleanup

`auto_create_catalog_for_band`, `handle_new_user`, `handle_new_user_profile`, `notify_blockout_created`, `notify_gig_created`, `notify_new_band_member`, `notify_rehearsal_created`, `prevent_catalog_deletion`, `prevent_catalog_rename`, `reorder_setlist_positions`, `sync_gig_location_from_venue`, `sync_gig_pay_from_financial_entry`, `trigger_recompute_setlist_stats`, `trigger_send_push_notification`, `update_setlist_duration`, `update_song_notes_updated_at`

All return type `trigger`. Postgres itself refuses to invoke a trigger-return-type function outside of trigger context ("trigger functions can only be called as triggers") — PostgREST can't expose these as callable RPCs no matter what the grant says. The anon grant on these is inert. Revoking it is pure hygiene with **no functional risk whatsoever**.

### 3b. RLS/permission-check helpers (9 names, 10 rows) — no anon dependency, but 4 have a real design issue

`check_band_member`, `check_financial_view_permission`, `check_gig_response_access`, `check_rehearsal_response_access`, `is_band_admin` (both overloads), `is_band_member`, `is_band_member_with_role`, `get_bandmate_user_ids`, `get_user_band_ids`

I checked `pg_policies` across the whole schema for any policy that actually names the `anon` role — **there are none.** Every RLS policy in `public` is `{public}`-scoped but gated on `auth.uid()` matching, so `anon` (where `auth.uid()` is null) gets zero rows regardless. There is no legitimate "RLS needs anon to call this helper" case anywhere in this schema. Safe to revoke.

**However**, 4 of these take an arbitrary user id as a *parameter* rather than reading `auth.uid()` internally, and don't check that the two match:

- `is_band_admin(user_uuid, check_band_id)` (the 2-arg overload)
- `get_bandmate_user_ids(user_uuid)`
- `get_user_band_ids(user_uuid)`
- `check_rehearsal_response_access(p_rehearsal_id, p_user_id)`

Right now, with anon execute still granted, anyone who has (or guesses) a valid user UUID can call these with **no login** and learn that person's bandmate list, band membership, or admin status. This is a real information-disclosure gap, not just "fragile but safe" — it doesn't fail closed, it just answers. Revoking anon fixes the immediate exposure; whether the parameter design itself needs tightening (should these even accept an arbitrary id, or always resolve from `auth.uid()`?) is a question worth putting to the Architect.

### 3c. `accept_band_invite` (1) — see §2, anon grant unused, safe to revoke

### 3d. Calendar token functions (5 names, 6 rows) — see §2, safe to revoke

`get_band_calendar_token`, `get_my_calendar_token`, `regenerate_band_calendar_token`, `regenerate_calendar_token`, `update_band_calendar_preferences` (both overloads)

### 3e. Action/mutation functions with a verified internal authorization check (~21) — accidental exposure, safe to revoke

Checked for an `auth.uid()` guard plus an explicit failure path (`RAISE EXCEPTION` or an early `RETURN` with an error payload): `bulk_add_songs_to_setlist`, `clear_song_metadata`, `create_band`, `create_venue_for_gig_save`, `delete_setlist`, `delete_song_from_catalog`, `delete_song_from_setlist`, `get_or_create_calendar_preferences`, `get_or_create_notification_preferences`, `get_unread_notification_count`, `mark_all_notifications_read`, `move_song_between_setlists`, `reorder_band_members`, `reorder_setlists`, `restore_band_members`, `update_calendar_preferences`, `update_song_metadata`, `upsert_device_token`.

I full-body-read two of these (`clear_song_metadata`, `delete_song_from_catalog`) to confirm the pattern holds — both check `auth.uid()` is non-null *and* that the caller is an active member of the specific `band_id` being touched before doing anything. The rest I confirmed via a heuristic query (presence of `auth.uid()` + an exception/error path in the function body) rather than a full manual read — high confidence, not full verification. This bucket matches the 08-17 audit's "internally fail-closed" claim: safe to revoke anon, no authenticated-side gap found.

### 3f. Action functions with NO internal authorization check — new finding, higher priority than the grant issue itself

Four functions do real writes and have **no membership check at all** — not even an `auth.uid()` read:

- **`add_special_item_to_setlist(p_setlist_id, p_special_item_id, p_item_type)`** — inserts into `setlist_songs` for whatever `p_setlist_id` is passed. No check that the caller belongs to the band that owns that setlist.
- **`ensure_catalog_setlist(p_band_id)`** — creates/merges catalog setlists for whatever `p_band_id` is passed, including deleting duplicate catalog rows. No membership check.
- **`increment_setlist_positions(p_setlist_id)`** — bumps every song's position in whatever setlist is passed. No membership check.
- **`reorder_setlist_items(p_setlist_id, p_row_ids)`** (and its thin wrapper `reorder_setlist_songs`) — validates that the row ids belong to the setlist, but never validates that the *caller* belongs to the band. No membership check.

All four are called directly from the Flutter app today (`special_item_repository.dart`, `setlist_repository.dart`) as top-level RPCs, so this isn't dead surface — it's live, reachable code that happens to have always been called by legitimate users in practice.

This matters more than the anon-grant question: **revoking `PUBLIC`/`anon` alone does not fix this.** `authenticated` still has execute on all four, and there's no check inside them that the caller is even a member of the target band — so today, any logged-in BandRoadie user (in any band) can call these four RPCs against a setlist ID belonging to a band they have nothing to do with, and it will succeed. That's a real cross-tenant data-tampering path, independent of C6.

**Recommendation:** file this as its own item — call it C6a or a new Critical — scoped as "add band-membership checks to `add_special_item_to_setlist`, `ensure_catalog_setlist`, `increment_setlist_positions`, `reorder_setlist_items`," separate from the grant-revoke migration. It's a code fix (add an `is_band_member`-style check), not a grants-only fix, and arguably shouldn't wait for the rest of C6 to be scoped.

---

## 4. Net effect on the C6 scope you asked me to de-risk

- **Real fix surface: 56 functions**, not 120 — the "authenticated" list is mostly the same functions, not a second pile of work.
- **16 of the 56 are inert (trigger-bound)** — zero-risk cleanup.
- **Both of your named "must stay anon" cases turn out not to need anon** — checked against actual call sites, not assumed.
- **I did not find any function in the 56 with a verified, legitimate reason to keep anon access.** That's a meaningfully different starting point than "there may be others like the invite/calendar cases I haven't classified" — I went through all 56, and the pre-auth exception category came up empty.
- **New, separate finding:** 4 of the 56 have no internal authorization check at all — a real cross-tenant tampering path for any authenticated user, not just an anon-hygiene issue. This should be scoped (and probably fixed) independently of, and likely before, the grants migration.

This doesn't remove the need for the caution you asked for — Supabase branch testing, batched migrations, and an explicit rollback plan are all still the right call for a 56-function production grants change, and I'd keep that in the Architect plan regardless of how clean this classification came back. What it changes is the "which functions do we have to carve out and treat specially" question — based on everything checked, the answer looks like none, contingent on the Architect (or a second pass) doing a full manual read of the ~16 functions in §3e that I only checked heuristically before the migration ships.

---

## 4a. Addendum — a plain `REVOKE ... FROM PUBLIC` will not close all 56

The audit's root-cause framing ("migrations grant `TO authenticated` but never revoke `FROM PUBLIC`, and Postgres auto-grants EXECUTE to PUBLIC on function creation") describes the *majority* mechanism, but not all of it. Checking the actual ACL rows (not just "is anon in the effective grantee set") shows **3 of the 56 have an explicit, separate `GRANT EXECUTE ... TO anon` with no `PUBLIC` grantee present at all**:

- `accept_band_invite`
- `create_band`
- `is_band_member`

For these three, `PUBLIC` was already revoked at some point (or never carried the default) — anon access survives because someone granted it directly. A migration that only runs `REVOKE EXECUTE ... FROM PUBLIC` across the board will silently do nothing for these three; they need `REVOKE EXECUTE ... FROM anon` explicitly. This is the same failure shape Tony flagged for overloaded functions (right pattern, wrong target, fails quietly) — worth the Architect building the migration to revoke from both `PUBLIC` and `anon` explicitly for every function in scope, rather than assuming the PUBLIC-only mechanism covers everything.

Note this also applies to `accept_band_invite` specifically — the function §2 already establishes doesn't need anon access functionally. This addendum is about *how* to revoke it correctly, not a reversal of that conclusion.

---

## 5. Not yet done / explicitly out of scope of this pass

- Full manual line-by-line read of all ~16 functions in bucket 3e (heuristic-checked only).
- Whether the 4 parameter-design functions in 3b (`get_bandmate_user_ids` etc.) should have their signatures changed vs. just having anon revoked — Architect call.
- The `get_user_band_role` `search_path` fix (C5 residual) — untouched, still a one-line migration you'd mentioned bundling in.
- No migration, grant change, or code edit was made. This is investigation only, per the Manager Agent's operating constraints.
