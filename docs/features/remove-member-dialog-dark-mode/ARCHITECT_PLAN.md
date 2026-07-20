# ARCHITECT_PLAN.md

## 1. Feature Slug

bug/remove-member-dialog-dark-mode

## 2. Problem Summary

The Remove Band Member confirmation dialog in the member management flow renders with light-mode styling while the app is in dark mode. This creates a visual mismatch against the rest of the screen, which correctly uses dark theme tokens. The issue is isolated to the dialog presentation layer, not member-removal business logic.

## 3. Root Cause

Diagnosed cause: a hardcoded light gray dialog background color is used in the remove-member confirmation dialog.

- File: lib/features/members/widgets/role_management_sheet.dart
- Evidence: AlertDialog sets `backgroundColor: const Color(0xFFD1D5DB)` in `_removeMember()`
- Why this fails: the hardcoded color bypasses `BrandColors`/theme extension resolution (`context.colors.*`), so the dialog does not adapt to dark mode.

Confidence: HIGH (directly confirmed in code)

## 4. Reference Docs Consulted

- docs/agents/ARCHITECT.md
- docs/agents/GUARDRAILS.md
- docs/agents/OPERATING_MODEL.md
- docs/features/setlist-modals-dark-mode/ARCHITECT_PLAN.md
- docs/features/setlist-modals-dark-mode/ENGINEER_REPORT.md

Note: there is no dedicated dark-mode/theming reference package under docs/reference specifically for this bug area; diagnosis is code-first and pattern-confirmed from prior dark-mode modal fix docs.

## 5. Existing System Analysis

Current flow:

1. User opens member management and navigates to role management for a member.
2. User taps Remove from band.
3. `_removeMember()` in `RoleManagementSheet` calls `showDialog<bool>`.
4. Dialog is built inline via `AlertDialog`.
5. Dialog title/content/button text mostly use `context.colors.textPrimary`/`textSecondary` and `AppColors.error`.
6. Dialog background uses hardcoded `0xFFD1D5DB`, forcing light appearance.

Observed architecture behavior:

- The surrounding screen and most dialog text already follow theme tokens.
- Only background color is not theme-aware.
- Prior bug fix `bug/setlist-modals-dark-mode` addressed separate setlist/tuning surfaces and did not include this members dialog path.

## 6. Proposed Solution

Apply the minimal in-place fix in the dialog builder:

- Replace hardcoded dialog background color with `context.colors.surface`.

Why this is minimal and correct:

- One-line presentation-layer change.
- Reuses existing theme extension already imported and used in the file.
- No state, routing, repository, or RBAC behavior changes.
- Matches pattern used in other corrected dialogs.

## 7. Database Impact

Database: not applicable.

- Migrations: unaffected
- RLS policies: unaffected
- RPC signatures/functions: unaffected
- Triggers: unaffected

## 8. Flutter Architecture Changes

- State management: unaffected (existing Riverpod providers unchanged)
- Widgets: affected (only dialog background token in RoleManagementSheet)
- Repositories/services/controllers: unaffected
- Navigation/routing: unaffected

## 9. Files to Create

- docs/features/remove-member-dialog-dark-mode/ARCHITECT_PLAN.md (required architecture artifact for this feature)

## 10. Files to Modify

| File                                                    | What changes                                                                                                                     |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| lib/features/members/widgets/role_management_sheet.dart | In `_removeMember()` dialog, replace hardcoded light background (`Color(0xFFD1D5DB)`) with theme-aware `context.colors.surface`. |

## 11. Files Off-Limits

| File                                         | Reason                                                         |
| -------------------------------------------- | -------------------------------------------------------------- |
| lib/main.dart                                | Initialization order is guarded and unrelated to this UI bug.  |
| lib/features/members/members_controller.dart | Member removal logic is not part of the theme rendering issue. |
| lib/features/members/members_repository.dart | Data layer is not involved in dialog styling.                  |
| lib/app/theme/design_tokens.dart             | Theme tokens already exist and are functioning.                |
| lib/app/theme/brand_colors.dart              | Theme extension already provides correct dark/light surfaces.  |
| pubspec.yaml                                 | No dependency changes required.                                |

## 12. System Impact Map

| System                                 | Impact                                                      |
| -------------------------------------- | ----------------------------------------------------------- |
| Gigs                                   | unaffected                                                  |
| Rehearsals                             | unaffected                                                  |
| Setlists / Catalog                     | unaffected                                                  |
| Members / RBAC                         | affected (UI surface only; no permission logic change)      |
| Auth / Session                         | unaffected                                                  |
| Routing                                | unaffected                                                  |
| Notifications                          | unaffected                                                  |
| Platform (iOS / Android / Web / macOS) | affected (shared Flutter widget rendering across platforms) |

## 13. Regression Risk

LOW

Rationale:

- Single-file, one-line visual fix.
- No business logic changes.
- No backend or schema touch.
- Existing theme token is already used broadly and stable.

## 14. Engineer Task Breakdown

1. Edit `lib/features/members/widgets/role_management_sheet.dart` in `_removeMember()`.
2. Change AlertDialog `backgroundColor` from hardcoded `const Color(0xFFD1D5DB)` to `context.colors.surface`.
3. Do not refactor dialog structure, button behavior, or messaging.
4. Run analyzer checks for the modified file/workspace as standard implementation validation.
5. Provide before/after evidence in ENGINEER_REPORT for this exact line-level change.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

Database migration path is not used for this feature.

- PRE-DEPLOY TEST 1: Static code verification confirms no SQL/database object changes are included in the diff.
- PRE-DEPLOY TEST 2: Confirm modified file count is limited to planned UI file(s) plus feature docs.

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

No `supabase db push` changes are required because this is a Flutter UI-only fix.

- POST-DEPLOY TEST 1: Launch app in dark mode, open member role management, trigger Remove Band Member dialog, verify dark surface styling.
- POST-DEPLOY TEST 2: Launch app in light mode, repeat flow, verify light surface styling.
- POST-DEPLOY TEST 3: Confirm dialog action behavior (Cancel/Remove) unchanged.
- POST-DEPLOY TEST 4: Production verification check: no unintended member removal side effects introduced by styling-only change (manual smoke: remove flow still succeeds/fails exactly as before with same snackbar outcomes).

## 16. QA Regression Areas

- Primary: Remove member confirmation dialog dark-mode styling in member management.
- Cross-theme: same dialog in light mode.
- Functional safety: remove action success/failure paths and snackbars remain unchanged.
- Adjacent checks: other role-management sheet visuals still render correctly (title, text contrast, buttons).
- Platform pass: spot-check on at least iOS + one additional shared-code target (Android or web/macOS).

## 17. Rollout / Migration Strategy

- No migration or backend rollout required.
- Ship with normal client release cadence.
- Include in next QA pass focused on members-management UI and dark-mode consistency.

## 18. Out of Scope

- Refactoring dialog to reusable component (`confirm_action_dialog.dart`).
- Updating other unrelated dialogs that may also be hardcoded unless separately ticketed.
- Any RBAC, repository, network, or Supabase changes.
