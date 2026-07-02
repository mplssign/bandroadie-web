# Architect Plan — Potential Gig Toggle Visibility

## Feature Slug

`bug/potential-gig-toggle-visibility`

## Problem Summary

The Potential Gig toggle switch on the Edit Gig screen is not visible when in the off state. Users cannot see the control to turn it on. The Light Mode and Notifications toggles render correctly in both states because they use different implementations. The root cause is that toggle switches across the app use inconsistent styling — some set inactive colors, others do not.

## Root Cause

**Confidence: HIGH** (confirmed by direct code inspection)

The Potential Gig toggle (`lib/features/events/widgets/gig_form_fields.dart:625-637`) uses `Switch.adaptive()` with only `activeTrackColor: AppColors.primary` and a custom `thumbColor` property. It **does not set** `inactiveTrackColor` or `inactiveThumbColor`.

When the switch is in the off state, Flutter uses default inactive colors that blend with the dark theme background (`Color(0xFF09090B)`), making the control invisible or nearly invisible against the dark surface.

The Light Mode toggle (`lib/features/settings/settings_screen.dart:418-424`) works correctly because it explicitly sets:

- `inactiveTrackColor: context.colors.surfaceOverlay` (`#3F3F46` dark, `#E4E4E7` light)
- `inactiveThumbColor: context.colors.textSecondary` (`#A1A1AA` dark, `#020617` light)

These colors provide sufficient contrast in both light and dark themes.

## Reference Docs Consulted

No relevant reference documentation found in `docs/reference/`. The only UI reference doc (`docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md`) covers the landing page, not component styling.

## Existing System Analysis

### Toggle Implementations Found

1. **Potential Gig toggle** — `lib/features/events/widgets/gig_form_fields.dart:625-637`
   - Direct `Switch.adaptive()` usage
   - Sets `activeTrackColor: AppColors.primary`
   - Sets `thumbColor` with `WidgetStateProperty` (white when active)
   - **Missing: `inactiveTrackColor`, `inactiveThumbColor`** ← ROOT CAUSE

2. **Light Mode toggle** — `lib/features/settings/settings_screen.dart:418-424`
   - Direct `Switch()` usage (not adaptive)
   - Sets `activeTrackColor: AppColors.primary`
   - **Sets `inactiveTrackColor: context.colors.surfaceOverlay`** ✓
   - **Sets `inactiveThumbColor: context.colors.textSecondary`** ✓
   - Visible in both states (WORKING)

3. **Notifications master toggle** — `lib/features/notifications/notification_settings_screen.dart:302-306`
   - Direct `Switch.adaptive()` usage in `_MasterToggleCard` widget
   - Sets `activeTrackColor: AppColors.primary`
   - **Missing: `inactiveTrackColor`, `inactiveThumbColor`**
   - Potentially has the same invisibility issue

4. **Shared AppToggleTile** — `lib/shared/widgets/toggle_tile.dart:93-97`
   - Used in Calendar subscription dialog (5 instances)
   - Used in Notification preferences screen (6 instances)
   - Sets `activeTrackColor: AppColors.primary`
   - **Missing: `inactiveTrackColor`, `inactiveThumbColor`**
   - All instances potentially affected

### Design Tokens Available

From `lib/app/theme/brand_colors.dart`:

- `context.colors.surfaceOverlay` — Dark: `#3F3F46`, Light: `#E4E4E7`
- `context.colors.textSecondary` — Dark: `#A1A1AA`, Light: `#020617`

These are the correct colors to use for inactive toggle state (proven working in Light Mode toggle).

## Proposed Solution

Add the missing `inactiveTrackColor` and `inactiveThumbColor` properties to all Switch widgets that currently lack them. Use the same colors as the working Light Mode toggle for consistency.

### Changes Required

1. **Update `lib/shared/widgets/toggle_tile.dart:93-97`**
   - Add `inactiveTrackColor: context.colors.surfaceOverlay`
   - Add `inactiveThumbColor: context.colors.textSecondary`
   - This fixes all 11 instances that use AppToggleTile

2. **Update `lib/features/events/widgets/gig_form_fields.dart:625-637`**
   - Add `inactiveTrackColor: context.colors.surfaceOverlay`
   - Keep existing `thumbColor` property (white when active)
   - Add inactive thumb color fallback in `thumbColor` WidgetStateProperty
   - This fixes the Potential Gig toggle (primary issue)

3. **Update `lib/features/notifications/notification_settings_screen.dart:302-306`**
   - Add `inactiveTrackColor: context.colors.surfaceOverlay`
   - Add `inactiveThumbColor: context.colors.textSecondary`
   - This fixes the Notifications master toggle

### Why Not Migrate to AppToggleTile?

The Potential Gig toggle has a custom `thumbColor` property (white when active) that differs from the standard AppToggleTile. The Notifications master toggle is embedded in a custom card layout. Migrating these to use AppToggleTile would require either:

- Extending AppToggleTile to support custom styling (scope creep)
- Restructuring the layouts (scope creep)

The minimal fix is to add the missing properties directly to each Switch widget. This solves the invisibility issue without architectural changes.

## Database Impact

**Not applicable** — UI-only change, no database interaction.

## Flutter Architecture Changes

**Widget Layer Only:**

- Three Switch widgets receive additional color properties
- No state management changes
- No controller changes
- No repository changes
- No data model changes
- No navigation changes

## Files to Create

**None**

## Files to Modify

| File                                                           | Changes                                                                                                                            |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `lib/shared/widgets/toggle_tile.dart`                          | Add `inactiveTrackColor` and `inactiveThumbColor` to the `Switch.adaptive()` at line 93                                            |
| `lib/features/events/widgets/gig_form_fields.dart`             | Add `inactiveTrackColor` to the `Switch.adaptive()` at line 625, and add inactive fallback to the `thumbColor` WidgetStateProperty |
| `lib/features/notifications/notification_settings_screen.dart` | Add `inactiveTrackColor` and `inactiveThumbColor` to the `Switch.adaptive()` at line 302                                           |

## Files Off-Limits

| File                                         | Reason                                                          |
| -------------------------------------------- | --------------------------------------------------------------- |
| `lib/features/settings/settings_screen.dart` | Light Mode toggle already works correctly; no change required   |
| `lib/app/theme/design_tokens.dart`           | No new color definitions required; using existing design tokens |
| `lib/app/theme/brand_colors.dart`            | Existing colors are sufficient; no changes required             |
| All files not listed in "Files to Modify"    | Out of scope                                                    |

## System Impact Map

| System                                 | Impact                                                                                             |
| -------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Gigs                                   | **affected** — Potential Gig toggle visibility fixed                                               |
| Rehearsals                             | unaffected                                                                                         |
| Setlists / Catalog                     | unaffected                                                                                         |
| Members / RBAC                         | unaffected                                                                                         |
| Auth / Session                         | unaffected                                                                                         |
| Routing                                | unaffected                                                                                         |
| Notifications                          | **affected** — Notifications master toggle and sub-toggles (via AppToggleTile) visibility improved |
| Calendar                               | **affected** — Calendar subscription toggles (via AppToggleTile) visibility improved               |
| Platform (iOS / Android / Web / macOS) | **affected** — All platforms, UI-level fix                                                         |

## Regression Risk

**Level: LOW**

**Rationale:**

- Pure UI change — adding missing visual properties only
- No logic changes, no state changes, no data flow changes
- No auth, session, routing, or initialization changes
- No database or RPC interaction
- The properties being added are standard Flutter Switch properties with well-defined behavior
- Light Mode toggle has used these same properties successfully (proven pattern)
- Change affects only the off-state appearance of switches; on-state behavior is unchanged
- Users cannot interact with an invisible toggle, so fixing visibility cannot introduce new interaction bugs

## Engineer Task Breakdown

Execute in order:

1. **Fix AppToggleTile** (`lib/shared/widgets/toggle_tile.dart`)
   - Locate the `Switch.adaptive()` widget at line 93
   - Add `inactiveTrackColor: context.colors.surfaceOverlay,` after `activeTrackColor`
   - Add `inactiveThumbColor: context.colors.textSecondary,` on the next line
   - Preserve existing `value`, `onChanged`, and `activeTrackColor` properties

2. **Fix Potential Gig toggle** (`lib/features/events/widgets/gig_form_fields.dart`)
   - Locate the `Switch.adaptive()` widget at line 625
   - Add `inactiveTrackColor: context.colors.surfaceOverlay,` after `activeTrackColor`
   - In the `thumbColor` WidgetStateProperty at line 631-636:
     - Keep the existing white thumb when selected
     - Add a fallback for the default state: `return context.colors.textSecondary;` after the selected check
   - Preserve existing `value` and `onChanged` properties

3. **Fix Notifications master toggle** (`lib/features/notifications/notification_settings_screen.dart`)
   - Locate the `Switch.adaptive()` in the `_MasterToggleCard` widget at line 302
   - Add `inactiveTrackColor: context.colors.surfaceOverlay,` after `activeTrackColor`
   - Add `inactiveThumbColor: context.colors.textSecondary,` on the next line
   - Preserve existing `value`, `onChanged`, and `activeTrackColor` properties

4. **Run `flutter analyze`**
   - Confirm zero errors
   - Confirm zero warnings related to the changes

5. **Visual verification (required before marking complete)**
   - Launch the app on at least one platform (iOS, Android, web, or macOS)
   - Navigate to Edit Gig screen and verify the Potential Gig toggle is visible in both on and off states
   - Navigate to Settings and verify the Notifications toggle is visible in both states
   - Navigate to Calendar and verify subscription toggles are visible in both states
   - Test in both light and dark themes (toggle Light Mode in Settings)
   - Confirm all toggles render with visible track and thumb in both states

## Verification Plan

### Pre-deployment (Flutter analyze only)

```bash
# TEST 1: Static analysis passes
flutter analyze
# Expected: 0 errors, 0 warnings related to toggle changes
```

### Post-implementation (Visual testing required)

#### TEST 1: Potential Gig toggle visibility (primary issue)

1. Launch the app
2. Navigate to Gigs tab
3. Open an existing gig or create a new one
4. Tap Edit
5. Scroll to the Potential Gig toggle
6. **Verify OFF state:**
   - Toggle is clearly visible
   - Track is visible (gray color, not black)
   - Thumb is visible (gray color, positioned left)
7. Tap the toggle
8. **Verify ON state:**
   - Toggle remains visible
   - Track is rose/primary color
   - Thumb is white, positioned right

#### TEST 2: Notifications master toggle visibility

1. Navigate to Home → Profile icon (top right)
2. Tap Settings
3. Tap Notifications
4. Locate the master Notifications toggle
5. **Verify OFF state** (if currently on, turn it off first):
   - Toggle is clearly visible
   - Track and thumb have gray colors
6. Tap the toggle
7. **Verify ON state:**
   - Toggle remains visible
   - Track is rose/primary color

#### TEST 3: Calendar subscription toggles visibility (AppToggleTile instances)

1. Navigate to Calendar tab
2. Tap the subscription/export button (if available)
3. Locate the toggle switches for Gigs, Rehearsals, etc.
4. **Verify OFF state** (for any toggle that is off):
   - Toggle is clearly visible
   - Track and thumb have gray colors
5. Tap a toggle
6. **Verify ON state:**
   - Toggle remains visible
   - Track is rose/primary color

#### TEST 4: Light/Dark theme compatibility

1. Navigate to Settings
2. Locate the Light mode toggle
3. Toggle light mode ON
4. Repeat TEST 1, TEST 2, and TEST 3 in light theme
5. Verify all toggles are visible in both on and off states in light theme
6. Toggle light mode OFF (return to dark theme)
7. Verify all toggles remain visible in dark theme

#### TEST 5: Regression check — Light Mode toggle

1. In Settings, verify the Light mode toggle still works correctly
2. Verify it's visible in both on and off states
3. Tap to toggle — verify the theme changes
4. Tap to toggle back — verify the theme reverts

**Success criteria:**

- All toggles are clearly visible in both on and off states
- All toggles are visible in both light and dark themes
- Track colors are distinguishable from the background
- Thumb colors are distinguishable from the track
- No console errors or warnings
- `flutter analyze` reports 0 errors

## QA Regression Areas

QA must specifically test:

1. **Potential Gig toggle (primary):**
   - Visibility in both on/off states
   - Visibility in both light/dark themes
   - Interaction (tap to toggle works)
   - Layout is unchanged (no spacing issues)

2. **All toggle switches across the app:**
   - Settings → Notifications master toggle
   - Settings → Notifications → individual notification type toggles (Gigs, Rehearsals, etc.)
   - Calendar → subscription toggles (if accessible)
   - Settings → Light Mode toggle (regression check — ensure it still works)

3. **Theme compatibility:**
   - All toggles tested in both light and dark themes
   - Colors are theme-appropriate (gray in off state, rose in on state)

4. **No functional regressions:**
   - Toggling on/off still changes state correctly
   - Potential Gig toggle still controls member availability visibility
   - Notifications toggle still enables/disables notifications
   - Calendar subscription toggles still control feed inclusion

5. **Platform coverage:**
   - Test on at least two platforms (e.g., iOS + web, or Android + macOS)
   - Verify `Switch.adaptive()` renders correctly on each platform

## Rollout / Migration Strategy

**Not applicable** — UI-only change, no data migration required.

**Deployment:**

- Standard web deployment via `./tools/deploy_web.sh`
- Mobile app update via App Store / Play Store (next release)

**Rollback:**

- If issue discovered post-deploy, revert the three file changes
- No data cleanup required

## Out of Scope

- Creating a unified toggle component (AppToggleTile already exists; extending it is not required to fix the bug)
- Refactoring all Switch usages to use AppToggleTile (the Light Mode toggle works and has a custom layout)
- Changing toggle behavior or interaction patterns
- Adding new toggle controls elsewhere in the app
- Performance optimization
- Accessibility improvements (ARIA labels, screen reader support)
- Animation or transition effects
- Adding tests for toggle appearance (Flutter integration tests do not test visual rendering)
