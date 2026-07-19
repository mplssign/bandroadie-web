# ARCHITECT_PLAN.md

## Feature Slug

bug/invite-screen-direct-accept-band-selection

---

## 1. Problem Summary

Invite acceptance that runs inside `InviteScreen` can still land users on the wrong active band after showing successful acceptance. The direct `InviteScreen` acceptance path calls `accept-invite`, but does not apply `accepted_band_id` to active band state before routing to `AuthGate`. After navigation, `AuthGate` falls back to `loadUserBands()` behavior, which restores the previously persisted active band when valid.

---

## 2. Root Cause (Verified)

### Primary Root Cause (HIGH confidence)

`InviteScreen._acceptInvite()` ignores deterministic band selection fields returned by `accept-invite`.

Confirmed in code:

- `supabase/functions/accept-invite/index.ts` returns `accepted_band_id` and `accepted_band_ids`.
- `lib/features/auth/invite_screen.dart` parses only success + band name text, clears pending token, and routes to new `AuthGate` without selecting accepted band.
- `lib/features/bands/active_band_controller.dart` persists active selection via `loadAndSelectBand()`, but this is never called from `InviteScreen` direct acceptance flow.

### Why prior fix did not fully close this

`AuthGate._checkAndProcessPendingInvite()` was fixed previously to parse `accepted_band_id` when _AuthGate_ performs invite acceptance. In this bug, `InviteScreen` already accepts the invite first and clears pending token, so remounted `AuthGate` has no deterministic token context and usually restores old persisted band.

---

## 3. Existing System Analysis

### Direct invite acceptance flow in `InviteScreen`

1. `InviteScreen` mounts with `token`.
2. Entry point A: `_handleInvite()` sees authenticated session and calls `_acceptInvite(token)`.
3. Entry point B: if unauthenticated initially, magic-link auth completes later; `onAuthStateChange` listener calls `_acceptInvite(token)`.
4. `_acceptInvite()` invokes edge function successfully and shows joined message.
5. It clears pending token and navigates to a fresh `AuthGate`.
6. No active band selection is applied in this flow.

### Real-world magic-link path assessment

For the mobile browser magic-link scenario, both entry points are possible due to timing:

- If session exists by the `_handleInvite()` session check, Entry point A runs.
- If PKCE completion lands after that check, Entry point B runs.

Both converge into the same `_acceptInvite()` body, so the fix must be inside shared `_acceptInvite()` logic (not only at one trigger site).

---

## 4. Proposed Solution

### Chosen approach

**Approach 1**: Convert `InviteScreen` to `ConsumerStatefulWidget` / `ConsumerState` and call `activeBandProvider.notifier.loadAndSelectBand(acceptedBandId)` inside `_acceptInvite()` before routing to `AuthGate`.

### Why this approach

- Minimal behavioral surface: fixes the exact flow that still fails.
- Avoids re-opening `AuthGate` routing/init logic that was just merged and reviewed.
- Reuses existing, architecturally-correct active-band API (`loadAndSelectBand`) that already persists active band id.
- Covers both `InviteScreen` trigger paths automatically because both use `_acceptInvite()`.

### SharedPreferences relay alternative (not chosen)

Persisting `accepted_band_id` and adding a new `AuthGate` read path is viable, but introduces additional cross-screen relay state and new key lifecycle management. For this bug, direct selection in `InviteScreen` is a smaller, cleaner closure.

---

## 5. Database / Edge Function Impact

- Schema migration: not required.
- RPC changes: not required.
- Edge function deploy: not required for this fix (response fields already present).

---

## 6. Flutter Architecture Changes

- `InviteScreen` becomes Riverpod-aware (`ConsumerStatefulWidget`) to access `ref`.
- `_acceptInvite()` parses `accepted_band_id` first, then falls back to first non-empty `accepted_band_ids` value.
- On successful acceptance with deterministic band id, call `loadAndSelectBand(acceptedBandId)` prior to navigation.
- If no deterministic id exists, preserve current fallback behavior (navigate to `AuthGate` without forcing band selection).

---

## 7. Files To Create

- none

---

## 8. Files To Modify

| File                                   | What changes                                                                                                                                                         |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/auth/invite_screen.dart` | Convert to `ConsumerStatefulWidget`; parse accepted band id fields; call `loadAndSelectBand()` before redirect; keep existing success UI and token cleanup behavior. |

---

## 9. Files Off-Limits

| File / Area                                      | Reason                                                                                                       |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `lib/features/auth/auth_gate.dart`               | Do not add more band-selection logic for this bug; keep recently shipped review-sensitive routing unchanged. |
| `lib/features/bands/active_band_controller.dart` | Use existing API only (`loadAndSelectBand`); no controller behavior changes needed.                          |
| `supabase/functions/accept-invite/index.ts`      | Already returns deterministic fields; avoid unrelated backend edits.                                         |
| `lib/main.dart`                                  | Initialization order guardrails; unrelated to this bug.                                                      |

---

## 10. System Impact Map

| System                           | Impact                                         |
| -------------------------------- | ---------------------------------------------- |
| Auth / Session                   | affected (invite accept continuation path)     |
| Bands / Active Band Context      | affected                                       |
| Invite Acceptance UI             | affected                                       |
| Routing                          | affected (post-success destination state only) |
| Members / RBAC                   | unaffected                                     |
| Gigs                             | unaffected                                     |
| Rehearsals                       | unaffected                                     |
| Setlists / Catalog               | unaffected                                     |
| Notifications                    | unaffected                                     |
| Platform (Web/iOS/Android/macOS) | affected where `InviteScreen` flow is used     |

---

## 11. Regression Risk

**LOW to MEDIUM**

Rationale:

- Single-file Flutter change.
- No backend/schema modifications.
- Uses established `activeBandProvider` selection API.
- Main risk is async ordering in `_acceptInvite()`; mitigate with existing `mounted` checks and preserving current user messaging/navigation behavior.

---

## 12. Engineer Task Breakdown

1. Update `InviteScreen` widget/state base classes to Riverpod consumer variants.
2. Add imports needed for Riverpod + `activeBandProvider` access.
3. In `_acceptInvite()`, extract deterministic accepted band id from `accepted_band_id` or first `accepted_band_ids` string.
4. After successful invite acceptance and token cleanup, call `loadAndSelectBand(acceptedBandId)` when id exists.
5. Keep current UX behavior: success message, delay, then navigate to fresh `AuthGate`.
6. Keep behavior unchanged when deterministic id is absent.
7. Ensure async safety (`mounted` guard) remains correct around delayed navigation and state updates.

---

## 13. Verification Plan

### Functional verification

1. Repro path (mobile browser magic-link): invite to non-active band, accept via `InviteScreen`, confirm app lands in invited band context after success screen.
2. Existing-session path: open `/invite?token=...` while already signed in, confirm accepted band becomes active after success.
3. No deterministic id fallback: simulate response without `accepted_band_id` and ensure current navigation still works.
4. Ensure pending invite token is still cleared after successful acceptance.

### Regression checks

1. Invite success UI still shows expected band name copy.
2. Invite failure path still displays error and Go to App action.
3. No new analyzer errors.

---

## 14. QA Regression Areas

- Primary: invite acceptance lands in invited band (not previously persisted band).
- Both acceptance triggers:
  - initial session already present,
  - auth-state-change completion after magic-link sign-in.
- Verify no regression to `AuthGate` fallback when invite response has no deterministic id.
- Confirm no visual/flow regressions in InviteScreen loading, success, and error states.

---

## 15. Rollout / Migration Strategy

- Flutter-only change.
- No migration.
- No edge deploy required.
- Standard web/mobile client rollout applies.

---

## 16. Out of Scope

- `bug/invite-link-opens-browser-not-app` deep-link transport issue.
- Any additional `AuthGate` routing refactors.
- Broad band-switch invalidation architecture changes.
