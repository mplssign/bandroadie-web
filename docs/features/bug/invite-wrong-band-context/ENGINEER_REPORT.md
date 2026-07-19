# Engineer Report

## Feature Slug

bug/invite-wrong-band-context

## Feature Title

Invite Acceptance Uses Wrong Band Context

## Goal

Ensure invite acceptance deterministically sets the invited band as active context.
Prevent false no-band fallback states caused by swallowed band fetch errors.
Keep backward compatibility for existing accept-invite response consumers.

## Architect Tasks Completed

- [x] Task 1 — Updated accept-invite edge function to honor optional token and return deterministic accepted band id fields.
- [x] Task 2 — Kept existing accepted_count and band_names response keys unchanged.
- [x] Task 3 — Updated AuthGate \_checkAndProcessPendingInvite() to parse response and call loadAndSelectBand() when deterministic band id exists.
- [x] Task 4 — Preserved fallback behavior by calling loadUserBands() when deterministic band id is not returned or on accept-invite failure paths.
- [x] Task 5 — Updated BandRepository.fetchUserBands() to rethrow exceptions instead of returning empty list.
- [x] Task 6 — Verified logic path now treats fetch failure as error state (via propagated exception handled by ActiveBandNotifier) instead of empty membership fallback.

## Files Created

- docs/features/bug/invite-wrong-band-context/ENGINEER_REPORT.md

## Files Modified

- supabase/functions/accept-invite/index.ts
- lib/features/auth/auth_gate.dart
- lib/features/bands/band_repository.dart
- lib/features/auth/invite_screen.dart

## Analyzer Results

Command: flutter analyze
Result: 0 errors, 0 warnings

## Test Results

Not run (Architect plan required flutter analyze only)

## Verification

Manual steps performed:

- Confirmed branch is bug/invite-wrong-band-context before edits.
- Confirmed AuthGate now consumes accepted_band_id/accepted_band_ids and selects invited band when present.
- Confirmed AuthGate fallback still loads user bands when deterministic id is absent.
- Confirmed fetchUserBands now propagates errors so ActiveBandNotifier sets error instead of false empty-band state.
- Confirmed AuthGate routes to an inline error-state UI (with retry action) when bandState.error is present, before empty-membership routing.
- Confirmed retry action re-invokes loadUserBands().
- Confirmed InviteScreen compatibility parsing accepts both legacy and current response name fields for success text.
- Ran flutter analyze and confirmed no issues found.

## Deviations From Architect Plan

Follow-up correction after manager review:

- Initial submission closed repository and notifier error propagation but missed AuthGate routing consumption of bandState.error.
- Updated AuthGate to branch on bandState.error before empty-membership routing and render a minimal retry UI that calls loadUserBands().
- This closes Architect Task 6 end-to-end by ensuring fetch failures no longer render the same UI as true empty membership.

## Blockers Encountered

None.

## Ready For QA

Yes
