# Feature Slug

feature/availability-prompt-forui-migration

# Problem Summary

The potential gig and potential rehearsal availability prompt modals remain implemented with raw Material `Dialog` shells and bespoke private widgets instead of the app’s forui-based UI wrappers. This causes drift from the rest of BandRoadie’s design system, duplicates nearly identical widget logic in both files, and leaves the only forui-backed element as a single text button. The request is a pure UI migration: preserve exact behavior while updating the dialog shell, action buttons, and detail rows to match the App UI system already adopted across the app.

# Root Cause

The root cause is a direct implementation gap in the modal layer: both `AvailabilityPromptModal` and `RehearsalAvailabilityPromptModal` still use `showDialog` with raw Material styling, local private `_DetailRow` and `_ResponseButton` classes, and custom animations instead of the existing app wrappers (`AppDialog`, `AppButton`, `AppCard`, etc.). This is confirmed by direct inspection of the target files and is a design-system migration issue, not a backend, RLS, or notification failure. Confidence: HIGH.

# Reference Docs Consulted

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/notifications.md`

These notification docs were reviewed for expected app architecture and to confirm no notification or Supabase backend behavior is relevant to this UI-only migration. They do not alter the solution scope because there is no database, preference, trigger, or push-delivery logic in the target files.

# Existing System Analysis

The affected widgets are:

- `lib/features/gigs/widgets/availability_prompt_modal.dart`
- `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart`

Current behavior:

- Both modals are launched through `showDialog<T>()` with `barrierDismissible: false` and a dark overlay.
- Each modal contains a custom gradient header, a custom detail list, and two custom response actions (`YES`/`NO`) implemented as private widgets.
- Each modal uses the same `PopScope(canPop: false)` pattern to block Android back navigation.
- Submission logic is preserved in each widget state class: `_handleResponse` sets `_isSubmitting`, triggers haptics, calls the provided `onRespond`, shows `SnackBar`/`showAppSnackbar` on error, and closes the dialog on success.
- The only forui-backed control is the final `AppButton` (`Not Sure Yet`) using `AppButtonVariant.text`.

Data flow and behavior are intentionally unchanged by this migration:

1. Caller opens the modal.
2. User taps a response button.
3. `_handleResponse` runs the existing async repository action.
4. On success the dialog pops with the response enum.
5. On error the same error messages are shown and the modal remains open.

The issue is not in the response flow; it is in the presentation layer, which has not adopted the app’s design-system wrappers. The migration should replace only the view shell and action controls while keeping the logic and error handling exactly as written.

# Proposed Solution

Implement a minimal UI migration that swaps the custom Material dialog shell and bespoke response/detail widgets for the existing forui app wrappers, without altering underlying state, repository calls, or response logic.

Required changes:

- Replace raw `Dialog`/`showDialog` usage with the app’s dialog wrapper pattern (`AppDialog` or equivalent forui dialog shell) while preserving `barrierDismissible: false`, the dark overlay, and the modal’s blocking behavior.
- Replace the custom YES/NO buttons with `AppButton` instances using the app styling conventions and the same loading/disabled state behavior.
- Replace the bespoke `_DetailRow` widget with a visually equivalent `AppCard`-based or inline app-styled row pattern that preserves icon, text alignment, spacing, and the localized time/date content.
- Keep the existing haptics, animations, `PopScope`, error snackbar feedback, and success close behavior exactly as-is.
- Decide whether to keep duplication or extract a small shared helper inside the feature area only if it reduces repetition without changing structure or behavior. No broad refactor beyond this migration.

What must not change:

- No change to the repository calls or response model enums.
- No change to Gig/Rehearsal creation or response persistence logic.
- No change to notification, auth, RLS, or database behavior.
- No change to animation timings or haptic expectations beyond using the existing app wrappers already built around the same design tokens.

New files: none required. If a tiny shared helper is justified for the duplicated response-row rendering, it should remain local to the feature area and not become a new cross-feature abstraction.

# Database Impact

Database: not applicable.

No database schema, migration, RPC, RLS policy, or trigger change is needed for this UI-only migration. The target files do not invoke Supabase persistence directly beyond the provided `onRespond` callback and the existing response repository flow, which is unchanged. The change is isolated to rendering and widget composition.

# Flutter Architecture Changes

State:

- No provider, controller, repository, or state model changes required.
- Existing widget state remains as the source of behavior and submission logic.

Widgets:

- `AvailabilityPromptModal` and `RehearsalAvailabilityPromptModal` are the primary UI targets.
- Use the existing app wrappers (`AppDialog`, `AppButton`, `AppCard`) to replace bespoke Material UI.
- The `AppButton` action buttons should keep loading state and disabled behavior during submission.

Repositories:

- No repository change required.
- The repository calls are passed in via injected callbacks and remain untouched.

# Files to Create

none

# Files to Modify

| File                                                                                                    | What changes                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/gigs/widgets/availability_prompt_modal.dart`                                              | Replace raw `Dialog` shell, bespoke detail rows, and custom response buttons with app-ui equivalents while preserving modal blocking behavior, animations, haptics, and payload handling.                                                                 |
| `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart`                              | Replace raw `Dialog` shell, bespoke detail rows, and custom response buttons with app-ui equivalents while preserving modal blocking behavior, animations, haptics, and payload handling.                                                                 |
| `lib/components/ui/app_dialog.dart` (only if required by the exact dialog API contract)                 | Extend or confirm the wrapper pattern is sufficient for the modal’s custom layout; no new abstraction to be introduced unless current wrapper capabilities are insufficient.                                                                              |
| `lib/features/home/widgets/potential_gig_card.dart` and `lib/features/home/widgets/rehearsal_card.dart` | Retint the potential card background to the same translucent orange convention as confirmed cards, keep only a subtle pulsing orange border, remove glow shadows, and align the availability prompt headers to the same orange tint with app text colors. |

# Files Off-Limits

| File                                          | Reason                                                                                                                             |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                               | Initialization order and app bootstrap must not change.                                                                            |
| `lib/features/gigs/*` outside the modal       | The migration is limited to the dialog UI and should not change unrelated gig flows.                                               |
| `lib/features/rehearsals/*` outside the modal | The migration is limited to the dialog UI and should not change unrelated rehearsal flows.                                         |
| `supabase/**`                                 | No backend, trigger, or database change is part of this feature.                                                                   |
| `lib/features/notifications/**`               | Notification delivery and preferences are outside this feature.                                                                    |
| `lib/app/theme/*`                             | Design tokens remain the source of truth; no re-theme work is required for this migration.                                         |
| `lib/features/*/repositories/*.dart`          | Response repository behavior is already correct and must remain untouched.                                                         |
| `test/**`                                     | No test refactor should be introduced as part of a pure UI migration unless the test plan requires small additions after approval. |

# System Impact Map

| System                                 | Impact     |
| -------------------------------------- | ---------- |
| Gigs                                   | affected   |
| Rehearsals                             | affected   |
| Setlists / Catalog                     | unaffected |
| Members / RBAC                         | unaffected |
| Auth / Session                         | unaffected |
| Routing                                | unaffected |
| Notifications                          | unaffected |
| Platform (iOS / Android / Web / macOS) | unaffected |

# Regression Risk

LOW

Rationale: the change is isolated to the rendering layer of two modal widgets, with no database, session, routing, or notification behavior in scope. The risk is primarily visual and structural consistency, not business logic or platform-level behavior. Existing state flow and response actions are preserved; the risk is limited to incorrect styling or accidental behavior drift in the modal presentation layer.

## Visual Refinement

- 2026-08-26: Tony approved a follow-up tuning pass that widened the pulsing orange border and glow amplitude in the two dashboard cards and both availability modals, keeping the same orange hue lerp and single-shadow glow structure while increasing border alpha from 0.35 + (pulseValue _ 0.3) to 0.35 + (pulseValue _ 0.45) and glow alpha from 0.12 + (pulseValue _ 0.18) to 0.18 + (pulseValue _ 0.27), with the glow blur increased from 8 to 10.
- 2026-08-26: Tony approved the modal update to randomize each popup pulse duration independently at initialization using a per-instance `Random()` duration in the 1000-3000ms range, matching the cards' existing per-instance pulse timing behavior while leaving all response logic and modal behavior unchanged.
- 2026-08-26: Tony approved a follow-up polish pass that synchronized the pulsing orange border across the two dashboard cards and both availability modals, slowed the card pulse cadence to 1000-3000ms, kept the modal pulse fixed at 2000ms, reduced the glow treatment to a single subtle shadow, and set the modal YES buttons to the existing success green.
- 2026-08-26: Tony approved a follow-up engineer pass that kept the synced pulse treatment in the two cards and both modals, preserved the modal's fixed 2000ms pulse, maintained the single subtle glow, and left the YES buttons matching NO until selection turns them green.

# Engineer Task Breakdown

1. Confirm the exact app-wrapper API to use for the custom modal shell (`AppDialog` or equivalent) while preserving the current blocking modal behavior.
2. Refactor `AvailabilityPromptModal` to replace the raw dialog container, custom stylistic rows, and response buttons with app-shared forui components without altering submission logic.
3. Refactor `RehearsalAvailabilityPromptModal` to mirror the same migration pattern while preserving the rehearsal-specific date/time layout.
4. Only if needed, extract a small shared widget or local helper for the repeated detail row pattern, keeping it within the feature area and not broader than the two dialogs.
5. Verify the modal still blocks outside dismissal and Android back navigation, and confirm the `Not Sure Yet` action still dismisses without saving.
6. Validate exact error handling and snackbar behavior remain unchanged after the widget swap.

# Verification Plan

## Tier 1 — Pre-deployment (must pass before `supabase db push`):

- `-- PRE-DEPLOY TEST 1:` Confirm both target files no longer construct a raw Material `Dialog` or private bespoke response widgets in the rendered tree; the modal shell is routed through the app’s forui dialog wrapper and the response controls are `AppButton`-based.
- `-- PRE-DEPLOY TEST 2:` Confirm no database objects, RLS policies, triggers, RPC signatures, or notification logic are touched by the change set; both files remain UI-only and no migration or deploy is required.

## Tier 2 — Post-deployment (run after `supabase db push` succeeds):

- `-- POST-DEPLOY TEST 1:` Open the potential gig availability modal in the app and verify the dialog title, date/time/location details, YES/NO buttons, loading state, and “Not Sure Yet” action render with app-styled forui controls and preserve spacing/layout.
- `-- POST-DEPLOY TEST 2:` Open the potential rehearsal availability modal and verify the same UI pattern and behavior, including `PopScope`, haptic feedback, loading state, and snackbar messaging on failure.
- `-- POST-DEPLOY TEST 3:` Confirm the user can submit YES/NO successfully and that the modal closes with the correct response object while the existing `onRespond` code path remains intact.
- `-- POST-DEPLOY TEST 4:` Confirm an error path still shows the same snackbar/feedback text and keeps the modal open without data-loss or regression in persistence behavior.

# QA Regression Areas

This feature is UI-only; there is no database or notification infrastructure change. QA should focus strictly on the following:

- Potential gig modal render and interaction parity with the legacy design.
- Potential rehearsal modal render and interaction parity with the legacy design.
- Confirmation that YES/NO buttons trigger the expected callbacks and maintain loading/disabled states.
- Validation that the modal still blocks outside dismissal and Android back navigation.
- Validation that `Not Sure Yet` closes without saving and does not alter underlying availability records.
- Check for SNACKBAR error messaging consistency when repository calls fail.
- Ensure the migration does not disturb haptics or the existing open/close animations.

# Rollout / Migration Strategy

No rollout or migration is required. This is a local UI migration only, with zero database schema or backend deployment impact. The change can be merged and validated as a front-end-only design-system migration.

# Out of Scope

- Any notification backend, trigger, or preference logic
- Any database schema, migration, or RLS work
- Any unrelated UI cleanup outside the two modals
- Any feature-wide theme overhaul beyond the required modal consistency migration
- Any changes to gig/rehearsal response repository flows or persistence logic
