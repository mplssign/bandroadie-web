# AI Decisions Log — BandRoadie

This document records architectural decisions made during AI-assisted development sessions. Every decision that changes initialization order, introduces new architecture, or requires a guardrails exception must be logged here before implementation begins.

Agents must read this file before designing solutions. If a proposed solution conflicts with a logged decision, the agent must stop and escalate to Tony.

---

## Decision Log Format

Each entry follows this structure:

```
## [DECISION-XXX] Short Title
**Date:** YYYY-MM-DD
**Feature:** feature/<slug> or bug/<slug>
**Agent:** Architect / Manager
**Status:** Active | Superseded by DECISION-XXX

### Context
Why this decision was needed.

### Decision
What was decided.

### Rationale
Why this approach was chosen over alternatives.

### Constraints Imposed
What this decision prevents or requires going forward.
```

---

## Decisions

## [DECISION-001] Web Auth Flow Migration: Implicit → PKCE

**Date:** 2026-04-14
**Feature:** bug/web-auth-magic-link-failure
**Status:** Active

### Context

Web magic link authentication was failing for users with email security scanners
(Microsoft Defender Safe Links) that pre-fetch URLs in emails. The implicit flow
embedded a direct Supabase /auth/v1/verify?token=... URL in the email; scanners
followed it immediately, consuming the OTP token before the user could click.
Supabase auth logs confirmed OTP tokens consumed within 13 seconds of issuance.

### Decision

Migrate web auth from implicit flow to PKCE flow (AuthFlowType.pkce). Email link
changes from a direct Supabase endpoint to the app's /auth/confirm?token_hash=...
route. The PKCE code_verifier is stored in the user's browser localStorage and is
required to complete the token exchange. Scanners cannot access localStorage from
the user's browser session and therefore cannot complete the exchange.

### Rationale

1. PKCE is the modern, recommended flow for OAuth/OIDC
2. code_verifier requirement prevents unauthorized token consumption by scanners
3. AuthConfirmScreen already contains full PKCE handling logic
4. Native platforms already use PKCE successfully
5. One-line config change; all downstream logic already exists

### Constraints Imposed

- Web users must click magic links in the same browser where they requested them
- Browser localStorage must be enabled (standard requirement)
- Users who request a link in Safari but open it in Chrome will see a
  "Browser Mismatch" error — already handled in auth_confirm_screen.dart

### Rollback Plan

Revert lib/main.dart line 64 to:
authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
No database migration or RLS changes required. Rollback is safe.

---

## [DECISION-002] Remove AcousticBrainz BPM Fallback

**Date:** 2026-05-27
**Feature:** bug/cleanup-p1-p2-p3
**Agent:** Architect
**Status:** Active

### Context

`_fetchAcousticBrainzBpm()` in `setlist_repository.dart` invoked a Supabase Edge
Function (`acousticbrainz_bpm`) that called the AcousticBrainz API. AcousticBrainz
was permanently shut down in November 2022. Every invocation failed silently, adding
200–500 ms latency to the BPM enrichment fallback path and consuming Edge Function
invocation quota.

### Decision

Remove the `_fetchAcousticBrainzBpm()` method and its call site in
`_attemptBpmEnrichment()`. The Supabase Edge Function source code
(`supabase/functions/acousticbrainz_bpm/`) is retained on disk for Tony to undeploy
manually via `supabase functions delete acousticbrainz_bpm`.

### Rationale

The API is permanently gone. There is no recovery path. The Spotify fallback
(Strategy 1) is the only working BPM source. Removing the dead code eliminates
latency and invocation waste with zero functional regression.

### Constraints Imposed

BPM enrichment now relies solely on Spotify Audio Features. Any future BPM fallback
source (e.g., MusicBrainz, AcoustID) must be implemented as a new named strategy
with its own edge function and decision log entry.

---

## [DECISION-003] Restore Band Members RPC — SECURITY DEFINER for atomic multi-member restore

**Date:** 2026-06-20
**Feature:** bug/restore-fails-multi-member-band
**Agent:** Architect
**Status:** Active

### Context

Multi-member band restore fails during `band_members` batch upsert with RLS permission error (42501). The `is_band_member()` RLS helper is `STABLE`, causing snapshot visibility issues during batch INSERT. Serialized single-row inserts risk partial restore state and are inefficient. Broadening the RLS policy to allow band creators to insert members bypasses the invitation model and is a security risk.

### Decision

Introduce a narrow `SECURITY DEFINER` RPC `restore_band_members(p_band_id uuid, p_members jsonb)` that:

- Validates caller created the band (`bands.created_by = auth.uid()`)
- Validates caller is an active admin of the band
- Atomically inserts/upserts all member rows in a single transaction
- Bypasses RLS for the INSERT (since caller authority is validated server-side)

### Rationale

1. **Atomic:** Transaction rollback prevents partial member restore
2. **Scoped:** Only affects restore flow, not normal member addition/invitation
3. **Secure:** Explicit server-side validation of caller authority
4. **Minimal:** No changes to existing RLS policies or helper functions
5. **Efficient:** Single round-trip, no N+1 queries

### Constraints Imposed

- The RPC must only be called immediately after `create_band` during restore
- Caller must be the band creator and an active admin
- JSONB parameter must be validated (no SQL injection, role ENUM enforcement)
- `SET search_path = public` is mandatory (per GUARDRAILS)
- Any future changes to `band_members` schema must update this RPC

---

## [DECISION-004] Add GetSongBPM as New-Song Key/BPM Enrichment Provider

**Date:** 2026-07-30
**Feature:** feature/new-song-key-enrichment
**Agent:** Architect
**Status:** Active

### Context

The new-song lookup flow (search → select → song lands in the Catalog) does not
retrieve musical key, and saves BPM/duration with no review step. `musical_key`
already exists on `songs` (migration `20260630000000_add_musical_key_to_songs.sql`)
but is never auto-populated on this path. The existing BPM enrichment path
(`_attemptBpmEnrichment` → Spotify Audio Features) is effectively dead code here:
the live search source is iTunes + MusicBrainz, neither of which supplies a
`spotify_id`, so Strategy 1 never runs. GetSongBPM was evaluated as a new external
provider to fill both gaps (see `docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md`
§6.4 for the full provider-viability writeup and §14 Task 1 for a live API spike
confirming the request/response contract).

### Decision

Add a new external service, GetSongBPM (`api.getsong.co`), as the BPM/key
enrichment source for the new-song review screen. A new Edge Function
(`supabase/functions/getsongbpm_lookup/`) calls GetSongBPM server-side (API key
held in Supabase Vault, never exposed to the client) using `type=both` combined
title+artist search, normalizes the returned key notation to the app's 24-key
vocabulary, and returns `confidence: 'medium'` only on an unambiguous single
artist-name match — otherwise `confidence: 'none'`. ISRC-based lookup was
evaluated and confirmed unsupported by GetSongBPM's API (`type=isrc` and an
`isrc=` param both 400); the medium-confidence title+artist path is the only
tier implemented in this phase, with the ISRC parameter wired through end-to-end
but dormant (see plan §19).

GetSongBPM's terms require a live, crawlable attribution backlink. Attribution is
provided in three places: an authenticated Settings-screen row (§6.6/§14 Task 11),
a public marketing-footer link (`lib/features/landing/widgets/footer_section.dart`,
added ahead of Task 11 per a Tony-directed scope amendment — see this feature's
`ENGINEER_REPORT.md`), and a Privacy Policy disclosure
(`lib/features/legal/privacy_policy_screen.dart`, `marketing/privacy.html`, added
in `bug/getsongbpm-hosting-doc-audit`).

### Rationale

1. GetSongBPM is free, requires only a static `api_key` query param (no OAuth), and
   has a rate limit (3,000 req/hr) that is a non-issue for one lookup per new-song save.
2. The two fields this feature needs (`tempo`, `key_of`) are confirmed present in
   live API responses.
3. The provider is called only server-side (Edge Function), consistent with every
   other existing third-party integration (`spotify_search`, `musicbrainz_search`) —
   no API key reaches the client.
4. The enrichment call is non-blocking: the review screen never gates Save on this
   fetch completing, matching the existing "BPM is a convenience, not a dependency"
   principle.
5. No per-song attribution is added to the primary song-enrichment UI (review
   screen, song cards) — only the two static, non-conditional surfaces above satisfy
   the backlink requirement without cluttering the core UX.

### Constraints Imposed

- `GETSONGBPM_API_KEY` must be present in Supabase Vault (or as an Edge Function
  env var fallback) for `getsongbpm_lookup` to return anything beyond `confidence: 'none'`.
- The three attribution surfaces (Settings, marketing footer, Privacy Policy) must
  all remain in place for as long as GetSongBPM is in use — GetSongBPM's terms
  permit key suspension "without notice" if the backlink disappears.
- Any future attempt to wire a real ISRC into this path must first re-verify
  GetSongBPM's API still lacks ISRC support (confirmed absent as of 2026-07-30) or
  swap in a working parameter if one is ever added.
- `key_of` normalization assumes GetSongBPM continues returning Unicode-sharp
  notation exclusively (confirmed via ~40-result sample this session, not a
  documented guarantee) — if flat notation is ever observed, `normalizeKey()` in
  `getsongbpm_lookup/index.ts` must be extended, not replaced.

---

## [DECISION-005] Atomic demo admission via transaction advisory lock + faster abandoned-slot reclaim

**Date:** 2026-09-12
**Feature:** bug/demo-capacity-check-race-and-leak
**Agent:** Architect
**Status:** Active

### Context

`provision_demo_session()` enforces a hardcoded 30-concurrent-session ceiling with
a non-atomic count-then-insert: the `SELECT count(*) ... WHERE expires_at > now()`
and the subsequent `INSERT INTO demo_sessions` are not serialized, so under READ
COMMITTED N concurrent first-time visitors can each read `count < 30` before any
commits and provision more than 30 sessions (each cloning two full template
bands). Separately, a demo slot is released only on the explicit "Exit Demo" tap;
a visitor who closes/kills the app instead holds the slot until `expires_at` (a
sliding TTL) plus the cron sweep interval — up to ~20 minutes per drive-by
visitor, which compounds the race by lowering real available capacity.

### Decision

1. **Atomic admission.** Add a single transaction-scoped advisory lock —
   `PERFORM pg_advisory_xact_lock(8675309001)` — in `provision_demo_session()`
   immediately before the ceiling count and after the idempotency early-return.
   Transaction-scoped so it auto-releases on commit OR rollback (cannot leak on
   error) and spans the whole single-statement RPC body. Because the reservation
   `INSERT` commits before the lock releases, each serialized provision sees the
   prior reservation in its count, so live rows with `expires_at > now()` never
   exceed 30.
2. **Faster reclaim.** Reduce the sliding demo-session TTL from 15 minutes to a
   fixed **8 minutes** (`expires_at` default + `heartbeat_demo_session()` renewal)
   and the `cleanup_demo_sessions` cron sweep from `*/5` to `*/2`. Paired with a
   best-effort client teardown on `AppLifecycleState.detached` (anonymous sessions
   only) in `auth_gate.dart`, which frees the slot immediately on graceful close.

### Rationale

- The advisory lock is one line, cannot leak, and fully satisfies the correctness
  requirement. Rejected alternatives (documented, not implemented): a counter
  table (state-sync complexity), serializable isolation + client retry (retry
  storms), and a session-level `pg_advisory_lock`/`unlock` bracketing only the
  reservation to let clones run concurrently (needs an EXCEPTION handler to
  guarantee unlock; higher risk under pooling). The only cost of the transaction
  lock is serializing the bounded (≤30) clone bodies under a cold burst —
  acceptable at the current 1/30 load; the session-lock variant is the documented
  upgrade path if burst throughput ever matters.
- **8-minute TTL (Tony, decided):** the advisory lock independently enforces the
  hard 30-session safety cap, so TTL is **not** the capacity guarantee — it only
  governs abandoned-slot turnover. Because there is no background heartbeat
  execution (the renewal timer is suspended while the app is backgrounded) and
  demo use is interruption-prone, a longer TTL gives a backgrounded-but-alive demo
  materially more grace before it must re-provision. At 1/30 load faster turnover
  buys nothing operationally, while 8 minutes still cuts worst-case abandoned-slot
  reclamation from ~20 min to ≤10 min (≤8 min TTL + ≤2 min cron). Implemented as a
  fixed constant in both the `expires_at` default and the heartbeat renewal — no
  apply-time tuning.

### Constraints Imposed

- The layered migration re-declares `provision_demo_session()` and
  `heartbeat_demo_session()` verbatim (plpgsql has no in-place line insert); both
  must retain `SECURITY DEFINER` + `SET search_path = public` and re-issue their
  exact `REVOKE ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated` so
  `anon` never gains EXECUTE. No new SECURITY DEFINER function is introduced.
- The 8-minute TTL and 2-minute cron interval are decided fixed constants — do not
  reintroduce apply-time tuning for them.
- The advisory-lock key `8675309001` is reserved for demo admission; reuse for any
  other lock would create false contention.
- The `detached` teardown must stay gated on `isAnonymous` and on `detached` only
  — never on backgrounding — so it cannot regress the "background briefly and
  return" flow or fire for real users.

### Rollback Plan

Revert the migration (a follow-up `CREATE OR REPLACE` restoring the prior function
bodies without the advisory lock, the 15-minute `expires_at` default, the
15-minute heartbeat renewal, and the `*/5` cron interval) and revert the two Dart
files (`auth_gate.dart`, `demo_session_service.dart`). No RLS change to unwind.

---

## Categories Requiring a Logged Decision

Any of the following changes **must** produce a new entry before implementation:

- Changes to the app initialization order (see `RUNTIME_CONFIG.md`)
- Introduction of a new state management pattern or provider type
- Introduction of a new config loading mechanism
- Changes to Supabase auth flow type (PKCE vs. implicit)
- New SECURITY DEFINER functions added to the database
- Any approved exception to a GUARDRAILS.md rule
- New external services or dependencies added to the stack
- Changes to the RLS policy architecture

---

_Maintained by the Manager Agent. Updated by the Architect when a plan requires a guardrails exception or architectural change._
