# Feature Slug

bug/app-card-test-brand-colors-context

# Problem Summary

`AppCard` widget tests fail because the test harness does not populate the `BrandColors` `ThemeExtension` required by `context.colors` in `lib/components/ui/app_card.dart`. The production app is unaffected because `ThemeData.extensions` is correctly registered in `lib/app/theme/app_theme.dart` and `lib/main.dart` wires both light and dark themes into `MaterialApp`. This is a test-only failure caused by a missing theme extension in the widget tree used during `pumpWidget`.

# Root Cause

The root cause is that `AppCard.build()` resolves colors via `context.colors`, and `BrandColorsX.colors` asserts that `Theme.of(context).extension<BrandColors>()` is non-null. The existing widget tests wrap the app with a bare `MaterialApp` and `FTheme` only; they never provide a `ThemeData` that includes `BrandColors.dark` or `BrandColors.light`. Because the extension is missing, the assertion in `BrandColorsX.colors` fires and the test fails before assertions about padding or tap behavior can even run.

Root cause confidence: HIGH

# Reference Docs Consulted

- `docs/reference/notifications/` — not applicable to this issue; no notifications-domain implementation or reference docs are relevant to the failing `AppCard` widget harness. The directory is not used for this bug.

# Existing System Analysis

- `lib/components/ui/app_card.dart` gets default border/background values from `context.colors`.
- `BrandColorsX.colors` resolves `Theme.of(context).extension<BrandColors>()` and asserts the extension is registered.
- `lib/app/theme/app_theme.dart` registers `BrandColors.dark` in `darkTheme` and `BrandColors.light` in `lightTheme` via `extensions: const [...]`.
- `lib/main.dart` wires both `AppTheme.lightTheme` and `AppTheme.darkTheme` into `MaterialApp`.
- `test/components/ui/app_card_test.dart` creates a `MaterialApp` with only `FTheme` data in the builder and no `theme` or `darkTheme` values. The resulting `ThemeData` lacks the `BrandColors` extension, so the widget tree is invalid for `AppCard` rendering.
- This is a test harness bug only; no production rendering path is broken.

# Proposed Solution

Implement the minimal fix in the test harness only: every `pumpWidget` in `test/components/ui/app_card_test.dart` must create a `ThemeData` whose `extensions` include `BrandColors` while preserving the existing `FTheme` wrapper. The most direct implementation is to give the `MaterialApp` a `theme: AppTheme.lightTheme` (or `ThemeData.light().copyWith(extensions: const [BrandColors.light])`) while keeping the `FTheme` builder as-is. This satisfies `context.colors` without changing app production code.

The fix must not modify:

- `lib/components/ui/app_card.dart`
- `lib/app/theme/brand_colors.dart`
- `lib/app/theme/app_theme.dart`
- `lib/main.dart`

The change should be scoped solely to the widget test harness and should preserve the existing test assertions and semantics.

# Database Impact

Database: not applicable

- No schema changes
- No migrations
- No RLS updates
- No new RPCs, triggers, or SQL objects
- No production-state mutation occurs in the failing code path

# Flutter Architecture Changes

- Test UI setup only
- No widget architecture changes
- No state, controller, repository, or provider changes
- No app runtime behavior changes
- The harness will provide a valid `ThemeData` with the required `BrandColors` extension for the widget under test

# Files to Create

none

# Files to Modify

| File                                    | What changes                                                                                                                                 |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `test/components/ui/app_card_test.dart` | Add a `ThemeData` carrying `BrandColors` to each `MaterialApp` used by the `pumpWidget` calls, while preserving the existing `FTheme` setup. |

# Files Off-Limits

| File                               | Reason                                                                                                                                            |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_card.dart`  | This is not the root cause; the widget is correctly using the brand theme contract.                                                               |
| `lib/app/theme/brand_colors.dart`  | The extension and assertion are intentionally designed to catch missing theme registration; the production theme registration is already correct. |
| `lib/app/theme/app_theme.dart`     | It already correctly registers `BrandColors.dark` and `BrandColors.light` in `ThemeData.extensions`.                                              |
| `lib/main.dart`                    | It already wires the app to both light and dark themes.                                                                                           |
| Any database migration or SQL file | This bug is entirely UI test setup and has no database impact.                                                                                    |

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

Regression risk: LOW

Reasoning:

- The issue is isolated to `flutter_test` widget setup.
- No production app code or theme logic is changing.
- The fix merely supplies the same `BrandColors` extension that the app uses in production.
- Only the test harness is affected, and the tests cover the exact widget behavior that previously failed.

# Engineer Task Breakdown

1. Update each `pumpWidget` in `test/components/ui/app_card_test.dart` to build under a valid `ThemeData` that includes `BrandColors` in `extensions`.
2. Keep the existing `FTheme` wrapper so the Forui card styling remains consistent with the current test setup.
3. Verify the file-level test suite is targeted and the four previously failing `AppCard` tests pass.
4. Avoid touching production files or any unrelated UI test assumptions.

# Verification Plan

Tier 1 — Pre-deployment (must pass before any merge):

- `-- PRE-DEPLOY TEST 1: flutter test test/components/ui/app_card_test.dart`
- This is the direct regression check for the broken harness and is sufficient to validate the root-cause fix with zero schema changes and no database dependency.

Tier 2 — Post-deployment (run after the fix is merged and the branch is ready for release QA):

- `-- POST-DEPLOY TEST 1: flutter test test/components/ui/app_card_test.dart`
- This confirms the targeted UI regression remains resolved in the final branch state.
- `-- POST-DEPLOY TEST 2: flutter test`
- This is the broader smoke check to confirm the test harness change does not disturb adjacent widget tests or application theme assumptions.

Note: No SQL migration or backend deployment verification is required because this issue has no database, RPC, or runtime data-side behavior. The fix is entirely test-harness scoped.

# QA Regression Areas

QA must specifically confirm:

- `AppCard` renders without throwing when the theme extension is present.
- Existing padding and tap-behavior assertions still pass after the harness update.
- The fix remains valid for both light and dark theme contexts (or at minimum the configured test theme path that matches app usage).
- The production app behavior is unchanged; only the test harness is corrected.

# Rollout / Migration Strategy

No rollout or migration is required.

This is a test-only fix with no schema, no deployment, and no runtime data migration. The safe rollout path is simply to merge the updated test file after the targeted widget test passes.

# Out of Scope

- Changing `AppCard` rendering logic
- Editing theme registration in `AppTheme` or `main.dart`
- Any database or backend change
- Any unrelated UI polish tasks
- Any work in the in-progress feature or date-based version worktrees
