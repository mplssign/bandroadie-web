# Feature Slug

bug/band-switch-circular-dependency-crash

# Problem Summary

Switching bands from the band switcher overlay throws an unhandled `CircularDependencyError` on `Provider<Band?>`. The crash is real even though the app continues and loads the new band's data afterward. The failure happens during band selection, so the fix must remove the self-referential provider invalidation without changing the rest of the band-switch flow.

# Root Cause

Confidence: HIGH

`ActiveBandNotifier.selectBand()` in `lib/features/bands/active_band_controller.dart` updates `activeBand` state and then manually invalidates `displayBandProvider`. That provider is a derived `Provider<Band?>` that watches `activeBandProvider`, so invalidating it from inside the same band-selection path creates the circular dependency Riverpod reports. The state change itself is sufficient to refresh all `watch(displayBandProvider)` consumers, so the invalidation is redundant and unsafe.

# Reference Docs Consulted

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/notifications.md`

These were read per session instructions; they are unrelated to the band-switch crash and do not affect the root cause.

# Existing System Analysis

Band switching is initiated from the band switcher overlay, which calls `activeBandProvider.notifier.selectBand(band)`. Inside `selectBand()`, the notifier persists the selection, updates `ActiveBandState.activeBand`, invalidates `displayBandProvider`, invalidates `currentUserPermissionsProvider`, clears the selected setlist, and returns the dashboard tab.

`displayBandProvider` is purely derived from `draftBandProvider` and `activeBandProvider`. All consumers in the app use `ref.watch(displayBandProvider)`, so changing `activeBandProvider` already causes the displayed band to update. The manual invalidation is the only code path that can produce the `Provider<Band?>` circular dependency.

# Proposed Solution

Remove the manual `ref.invalidate(displayBandProvider);` call from `ActiveBandNotifier.selectBand()`. Keep the existing state update, permission refresh, selected-setlist clear, dashboard navigation, and persistence behavior unchanged.

Do not introduce new providers, controllers, or widget-level workarounds. Do not move the fix into the band switcher overlay or any caller, because the defect is in the notifier's invalidation behavior.

# Database Impact

Not applicable.

No migrations, RLS changes, RPC changes, or trigger updates are required.

# Flutter Architecture Changes

The only code change is in the active-band controller. No widget tree changes are required because every consumer of `displayBandProvider` already rebuilds from the `activeBandProvider` state change.

# Files to Create

none

# Files to Modify

| File                                             | What changes                                                                                                                                           |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/bands/active_band_controller.dart` | Remove the `ref.invalidate(displayBandProvider);` call from `selectBand()` so band switching no longer self-invalidates the derived `Provider<Band?>`. |

# Files Off-Limits

| File                                                                   | Reason                                                                                          |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `lib/features/shell/app_shell.dart`                                    | Caller is not the defect source; keep the band-switch UI unchanged.                             |
| `lib/features/home/widgets/band_switcher.dart`                         | Overlay behavior is correct; the notifier must be fixed instead.                                |
| `lib/features/bands/active_band_controller.dart` provider declarations | `displayBandProvider` remains the correct derived provider; only the invalidation site changes. |
| Any notification docs, database files, or migrations                   | Unrelated to this crash and must not be touched.                                                |

# System Impact Map

| System                                 | Impact     |
| -------------------------------------- | ---------- |
| Gigs                                   | unaffected |
| Rehearsals                             | unaffected |
| Setlists / Catalog                     | unaffected |
| Members / RBAC                         | unaffected |
| Auth / Session                         | unaffected |
| Routing                                | unaffected |
| Notifications                          | unaffected |
| Platform (iOS / Android / Web / macOS) | unaffected |

# Regression Risk

LOW

The change is a one-line removal in a single notifier method. It does not alter persisted data, band selection semantics, auth, routing, or platform behavior. The only intended effect is eliminating the unhandled Riverpod circular dependency while preserving the existing band-switch outcome.

# Engineer Task Breakdown

1. Remove the `displayBandProvider` invalidation from `ActiveBandNotifier.selectBand()`.
2. Leave the rest of the band-switch sequence intact so the active band still updates, permissions still refresh, the setlist selection clears, and the dashboard tab still opens.
3. Confirm no other band-switch path introduces a manual invalidation of `displayBandProvider`.
4. Validate the fix with a narrow analyzer pass and a local band-switch reproduction.

# Verification Plan

## Tier 1 — Pre-deployment

-- PRE-DEPLOY TEST 1: Run `flutter analyze lib/features/bands/active_band_controller.dart` and confirm the file is clean after removing the invalidation.
-- PRE-DEPLOY TEST 2: Review the diff for `lib/features/bands/active_band_controller.dart` to confirm only the band-selection invalidation line changed.

## Tier 2 — Post-deployment

-- POST-DEPLOY TEST 1: Reproduce the band switch in a local Flutter run by opening the band switcher and selecting another band; confirm no `CircularDependencyError` is thrown.
-- POST-DEPLOY TEST 2: Confirm the active band, permissions, selected setlist, and dashboard tab still update normally after the switch.
-- POST-DEPLOY TEST 3: No SQL verification query is required because this is a Flutter-only fix with no database impact.

# QA Regression Areas

- Band switcher overlay band selection should no longer throw an unhandled exception.
- Active band text/avatar rendering should still update across screens that watch `displayBandProvider`.
- Permission-dependent UI should still refresh after the band changes.
- Setlists, gigs, rehearsals, and members screens should continue to follow the new active band normally.

# Rollout / Migration Strategy

None required. This is a client-side fix only and does not require a database migration or backend deploy.

# Out of Scope

- Refactoring band switcher UI or overlay animation behavior.
- Changing provider architecture or introducing a new band-selection state source.
- Any notification system work, database trigger work, or Supabase schema changes.
- Broad cleanup of other invalidation sites unless they are proven to be part of this crash.
