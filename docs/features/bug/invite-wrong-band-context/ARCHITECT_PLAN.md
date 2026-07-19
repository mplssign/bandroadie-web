# ARCHITECT_PLAN.md

## Feature Slug

bug/invite-wrong-band-context

---

## 1. Problem Summary

After invite acceptance, users can land in the wrong band context (Tony repro) or in a no-band fallback UI (David report). The acceptance path currently succeeds at membership write, but the client does not deterministically switch active band to the invited band.

Observed outcomes:

- Wrong band shown: accepted invite to Huge Mistake, app remained on previously persisted Toxic Crayon.
- No band shown: user sees Create New Band flow after acceptance.

---

## 2. Root Cause (Verified)

### Primary Root Cause (HIGH confidence)

Invite acceptance does not set the invited band as the active band.

Confirmed in code:

- `supabase/functions/accept-invite/index.ts` accepts invites and returns only `{ success, accepted_count, band_names }` (no band id in response).
- `lib/features/auth/auth_gate.dart` `_checkAndProcessPendingInvite()` invokes `accept-invite` and ignores response payload details; afterwards `_checkProfileComplete()` always calls `loadUserBands()`.
- `lib/features/bands/active_band_controller.dart` `loadUserBands()` restores persisted `active_band_id` first when valid. If user already has a persisted band, it is kept.

Result: invite acceptance can succeed while active context remains the previously persisted band.

### Secondary Contributor (HIGH confidence for existence, MEDIUM for causality in this report)

Band lookup failures are silently converted to empty lists.

Confirmed in code:

- `lib/features/bands/band_repository.dart` `fetchUserBands()` catches all errors and returns `[]`.
- `lib/features/bands/active_band_controller.dart` treats empty bands as legitimate no-band state and routes user to NoBandShell.

This can produce a false "no band" outcome under transient query/RLS/network failure, matching David's symptom pattern.

### Hypothesis Check: `selectBand()` invalidation gap

`selectBand()` does invalidate only a small subset of providers (`displayBandProvider`, `currentUserPermissionsProvider`, selected setlist clear), but invite acceptance path does not call `selectBand()` at all. Therefore, this is not the primary trigger for Tony's wrong-band repro.

Conclusion: the repro is primarily a post-accept selection bug (narrow call-site issue), not a direct `selectBand()` invalidation bug.

---

## 3. Existing System Analysis

### Accept flow today

1. Invite link opens `InviteScreen`.
2. `InviteScreen` calls `accept-invite` with token in body.
3. Edge function currently accepts by authenticated email and pending/sent status; token is not used for deterministic target selection.
4. `InviteScreen` redirects to `AuthGate`.
5. `AuthGate` calls `_checkAndProcessPendingInvite()` then `loadUserBands()`.
6. `loadUserBands()` restores persisted band if still present.

Net effect: previously persisted band can remain active even after successful invite acceptance.

### State reset behavior

Band switch UI handlers (`HomeScreen`, `CalendarScreen`, `AppShell`) manually call gig/rehearsal `resetForBandChange()` before `selectBand()`. Invite flow bypasses these handlers entirely.

---

## 4. Proposed Minimal Solution

Fix should target invite acceptance call site behavior, not broad band-state refactor.

### Change A (required): deterministically return selected band id from accept-invite

Update `accept-invite` edge function to:

- Honor optional `token` when provided:
  - Resolve invite row by token + email + eligible status.
  - Accept that invite first.
- Include deterministic response fields:
  - `accepted_band_id` (single band id for token flow)
  - `accepted_band_ids` (array for multi-invite fallback flow)
- Keep existing fields for backward compatibility:
  - `success`, `accepted_count`, `band_names`

### Change B (required): set active band from invite acceptance result

Update `AuthGate` pending-invite processing to:

- Parse `accepted_band_id`/`accepted_band_ids` from `accept-invite` response.
- If a deterministic accepted band id is present, call `activeBandProvider.notifier.loadAndSelectBand(acceptedBandId)`.
- Otherwise, fall back to existing `loadUserBands()`.

This explicitly sets the newly accepted band as current and prevents persisted stale band bleed-through.

### Change C (required hardening for no-band false negatives)

Stop silent failure conversion in band lookup:

- `BandRepository.fetchUserBands()` should not return `[]` on exception.
- Let error propagate so `ActiveBandNotifier.loadUserBands()` can set error state instead of false empty-band state.

This prevents starvation/fallback UI when data retrieval actually failed.

### Scope decision

Do not change `selectBand()` internals in this fix. Root issue is invite-flow selection logic and error swallowing.

---

## 5. Database / Edge Function Impact

- Database schema migration: not required.
- RPC changes: not required for this bug.
- Edge function deploy: required (`accept-invite`).

Note:

- `accept_band_invite` RPC already exists and is current on main (including intended role behavior).
- This bug fix is response-shape and token-targeting behavior in edge function orchestration, not RPC internals.

---

## 6. Flutter Architecture Changes

State management changes are narrow:

- `AuthGate` invite processing branch chooses deterministic post-accept band.
- `ActiveBandNotifier` usage remains existing API (`loadAndSelectBand`), no new provider abstractions.
- No routing/init-order changes.

---

## 7. Files To Modify

| File                                        | What changes                                                                                                               |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `supabase/functions/accept-invite/index.ts` | Add token-aware invite targeting and include accepted band id(s) in response while preserving existing response fields.    |
| `lib/features/auth/auth_gate.dart`          | Capture accept-invite response and call `loadAndSelectBand()` when accepted band id is provided.                           |
| `lib/features/bands/band_repository.dart`   | Remove silent `catch -> []` fallback; propagate errors for caller-level handling.                                          |
| `lib/features/auth/invite_screen.dart`      | Optional compatibility update: read `band_names`/new fields consistently for success UI text, no behavior change required. |

---

## 8. Files Off-Limits

| File / Area                                                     | Reason                                                                                     |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `lib/main.dart`                                                 | Initialization and routing order are guardrail-sensitive and unrelated.                    |
| `lib/features/bands/active_band_controller.dart` (`selectBand`) | Not root cause for invite acceptance repro; avoid broad invalidation refactor in this bug. |
| Supabase migrations under `supabase/migrations/`                | No schema or RPC signature change required.                                                |
| Unrelated Android/iOS manifest/entitlement files                | Out of scope for this bug.                                                                 |

---

## 9. System Impact Map

| System                            | Impact                                      |
| --------------------------------- | ------------------------------------------- |
| Auth / Session                    | affected                                    |
| Bands / Active Band Context       | affected                                    |
| Invite Acceptance (Edge Function) | affected                                    |
| Members / RBAC                    | unaffected                                  |
| Gigs                              | unaffected (indirect refresh behavior only) |
| Rehearsals                        | unaffected (indirect refresh behavior only) |
| Setlists / Catalog                | unaffected                                  |
| Notifications                     | unaffected                                  |
| Routing                           | unaffected                                  |
| Platform (Web/iOS/Android/macOS)  | affected where invite flow is used          |

---

## 10. Regression Risk

MEDIUM

Rationale:

- Touches authentication-adjacent onboarding path and active-band selection.
- Minimal file surface and no schema change reduce blast radius.
- Existing response fields preserved to reduce compatibility risk.

---

## 11. Engineer Task Breakdown

1. Update `accept-invite` edge function to honor optional token and return deterministic accepted band id field(s).
2. Keep existing `band_names` and `accepted_count` response keys unchanged.
3. Update `AuthGate` `_checkAndProcessPendingInvite()` to consume response and call `loadAndSelectBand()` when possible.
4. Ensure fallback path still calls `loadUserBands()` when no deterministic band id is returned.
5. Update `BandRepository.fetchUserBands()` to rethrow (or return explicit failure) instead of `[]` on exceptions.
6. Verify no-band screen is shown only for true empty membership, not fetch failure.

---

## 12. Verification Plan

### Tier 1 — Pre-deployment

-- PRE-DEPLOY TEST 1:

- In Flutter layer unit/integration harness, mock `accept-invite` response with `accepted_band_id`.
- Verify `AuthGate` calls `loadAndSelectBand(accepted_band_id)` and does not keep persisted stale band.

-- PRE-DEPLOY TEST 2:

- Mock `BandRepository.fetchUserBands()` throwing exception.
- Verify active band state surfaces error path, not false empty no-band state.

-- PRE-DEPLOY TEST 3:

- Verify backward compatibility parsing when response includes only legacy keys (`accepted_count`, `band_names`).

### Tier 2 — Post-deployment

-- POST-DEPLOY TEST 1:

- Deploy `accept-invite` edge function.
- Run controlled repro: invite account to Huge Mistake from mobile email link, complete acceptance on web.
- Expected: app lands with Huge Mistake active, not previously persisted band.

-- POST-DEPLOY TEST 2:

- Account with existing persisted active band accepts different-band invite.
- Expected: active band switches to invited band immediately after acceptance.

-- POST-DEPLOY TEST 3:

- Force temporary read failure (or inspect logs during simulated failure) for band fetch.
- Expected: user sees recoverable error state, not "create new band" false empty state.

-- POST-DEPLOY TEST 4:

- Validate response payload from edge function still contains legacy keys:
  - `success`, `accepted_count`, `band_names`
    and now includes deterministic band id fields.

---

## 13. Other Shared Stale-Invalidation Risks (Flagged, Not In Scope)

These call sites manually reset gig/rehearsal state before band switching and are bypassed by invite flow:

- `lib/features/home/home_screen.dart`
- `lib/features/calendar/calendar_screen.dart`
- `lib/features/shell/app_shell.dart`

Additionally, `selectBand()` invalidates a narrow set of providers only. This broader invalidation strategy should be handled in a dedicated follow-up bug, not in this fix.

---

## 14. Out of Scope

- Global refactor of band-switch invalidation architecture.
- Reworking all band-scoped repositories/controllers.
- Invite-link native deep-link transport behavior (`bug/invite-link-opens-browser-not-app`).
- Any platform manifest/association file changes.
