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
